// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

import {StockRunner} from "../runner/StockRunner.sol";
import {IRunPriceOracle} from "./IRunPriceOracle.sol";
import {RevenueSplitter} from "./RevenueSplitter.sol";

/// @title The Black Market — where Stock//Runners change hands, run by the Fence
/// @notice Fixed-price mint and market, priced in $RUN. Genesis activates a blank unit for
///         1,000,000 $RUN. Secondary is a pool: operators sell units in, buyers take a random one
///         cheaply or pay a premium to pick a specific one.
///
/// @dev **This is the floor, not the ceiling.** The pool quotes one price for every unit it holds,
///      so it cannot pay a premium for a built, tenured Runner — and is not meant to. Premium units
///      trade on external venues, which is precisely what the 5% ERC-2981 royalty exists to capture
///      ("a unit changing hands funds every other unit regardless of venue"). The pool's job is
///      instant liquidity and a legible floor, and in phase 6 it is what the Fixer's $RUN loans
///      draw from.
///
///      The curve is linear on the pool's own spot price rather than on inventory count: each buy
///      steps the price up by `delta`, each sale steps it down. Simple enough that an operator can
///      predict the next quote without modelling anything, which is the same reasoning behind the
///      linear tenure curve.
contract BlackMarket is Ownable, ReentrancyGuard, IERC721Receiver {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Fee on buying a random unit out of the pool — 10%.
    uint256 public constant BUY_RANDOM_BPS = 1000;

    /// @notice Fee on buying a named unit — 15%. You pay for the right to choose.
    uint256 public constant BUY_SPECIFIC_BPS = 1500;

    /// @notice Sell fee tiers, by the unit's value in ETH at the current $RUN price.
    uint256 public constant SELL_BPS_BELOW_FLOOR = 2500; // under 0.1 ETH
    uint256 public constant SELL_BPS_MID = 1500; // 0.1 – 1 ETH
    uint256 public constant SELL_BPS_ABOVE = 1000; // over 1 ETH

    /// @notice Tier boundaries, in wei.
    uint256 public constant TIER_FLOOR_WEI = 0.1 ether;
    uint256 public constant TIER_CEILING_WEI = 1 ether;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable RUN_TOKEN;
    StockRunner public immutable RUNNER;
    RevenueSplitter public immutable SPLITTER;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Current pool quote for one unit, in $RUN. Steps up on a buy, down on a sale.
    uint256 public spotPrice;

    /// @notice How far each trade moves `spotPrice`.
    uint256 public delta;

    /// @notice `spotPrice` never falls below this, so the pool can't be walked to zero.
    uint256 public minSpotPrice;

    /// @notice The $RUN/ETH reference the sell fee tiers key off.
    IRunPriceOracle public priceOracle;

    /// @dev Units currently held by the pool, and each unit's index for O(1) removal.
    uint256[] private _inventory;
    mapping(uint256 tokenId => uint256 index) private _inventoryIndex;
    mapping(uint256 tokenId => bool held) private _inPool;

    /// @dev Mixed into random selection so two draws in one block differ.
    uint256 private _drawNonce;

    /// @notice Lifetime fee total routed to the splitter, in $RUN.
    uint256 public lifetimeFees;

    /*//////////////////////////////////////////////////////////////
                          LENDING (phase 6)
    //////////////////////////////////////////////////////////////*/

    /// @notice The Fixer. The only address permitted to borrow pool $RUN.
    /// @dev Spec: the Fixer's $RUN loans "draw from and repay into the Black Market's own liquidity
    ///      pool rather than a separate reserve, which keeps $RUN supply genuinely fixed and couples
    ///      borrowing to the pool's TWAP."
    address public fixer;

    /// @notice Principal currently lent out to the Fixer.
    uint256 public totalLent;

    /// @notice Ceiling on how much of the pool may be lent, in basis points of total pool $RUN.
    /// @dev Not in the spec — a safety rail. Without it the Fixer could drain the pool's $RUN and
    ///      `sell` would start reverting, stranding operators who expect a floor bid. Defaults to
    ///      50% so the pool always retains buying capacity.
    uint256 public maxLendBps = 5000;

    event FixerUpdated(address indexed fixer);
    event Lent(address indexed to, uint256 amount, uint256 totalLent);
    event LoanRepaid(address indexed from, uint256 amount, uint256 totalLent);
    event MaxLendUpdated(uint256 bps);

    error NotFixer();
    error LendCeilingReached(uint256 requested, uint256 allowed);

    modifier onlyFixer() {
        if (msg.sender != fixer) revert NotFixer();
        _;
    }

    /// @notice Lend pool $RUN to the Fixer, which passes it on to the borrower.
    function lendRun(address to, uint256 amount) external onlyFixer {
        uint256 poolBalance = RUN_TOKEN.balanceOf(address(this));
        uint256 allowed = ((poolBalance + totalLent) * maxLendBps) / BPS_DENOMINATOR;
        if (totalLent + amount > allowed) {
            revert LendCeilingReached(totalLent + amount, allowed);
        }
        if (amount > poolBalance) revert InsufficientPoolFunds(amount, poolBalance);

        totalLent += amount;
        RUN_TOKEN.safeTransfer(to, amount);
        emit Lent(to, amount, totalLent);
    }

    /// @notice Return borrowed principal to the pool. Permissionless — repaying is never harmful.
    function repayRun(uint256 amount) external {
        RUN_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        totalLent = totalLent > amount ? totalLent - amount : 0;
        emit LoanRepaid(msg.sender, amount, totalLent);
    }

    /// @notice How much more the Fixer may borrow right now.
    function lendableRun() external view returns (uint256) {
        uint256 poolBalance = RUN_TOKEN.balanceOf(address(this));
        uint256 allowed = ((poolBalance + totalLent) * maxLendBps) / BPS_DENOMINATOR;
        if (allowed <= totalLent) return 0;
        uint256 headroom = allowed - totalLent;
        return headroom < poolBalance ? headroom : poolBalance;
    }

    function setFixer(address fixer_) external onlyOwner {
        if (fixer_ == address(0)) revert ZeroAddress();
        fixer = fixer_;
        emit FixerUpdated(fixer_);
    }

    function setMaxLendBps(uint256 bps) external onlyOwner {
        if (bps > BPS_DENOMINATOR) revert LendCeilingReached(bps, BPS_DENOMINATOR);
        maxLendBps = bps;
        emit MaxLendUpdated(bps);
    }

    /*//////////////////////////////////////////////////////////////
                            EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/

    event GenesisActivated(address indexed operator, uint256 indexed tokenId, uint256 paid);
    event UnitBought(
        address indexed buyer, uint256 indexed tokenId, uint256 price, uint256 fee, bool specific
    );
    event UnitSold(address indexed seller, uint256 indexed tokenId, uint256 payout, uint256 fee);
    event SpotPriceMoved(uint256 newSpotPrice);
    event CurveUpdated(uint256 delta, uint256 minSpotPrice);
    event PriceOracleUpdated(address indexed oracle);

    error PoolEmpty();
    error UnitNotInPool();
    error NotUnitOwner();
    error InsufficientPoolFunds(uint256 required, uint256 available);
    error SlippageExceeded(uint256 quoted, uint256 limit);
    error ZeroAddress();
    error ZeroDelta();

    constructor(
        address runToken,
        address runner_,
        address splitter_,
        address priceOracle_,
        uint256 initialSpotPrice,
        uint256 delta_,
        uint256 minSpotPrice_
    ) Ownable(msg.sender) {
        if (
            runToken == address(0) || runner_ == address(0) || splitter_ == address(0)
                || priceOracle_ == address(0)
        ) revert ZeroAddress();
        if (delta_ == 0) revert ZeroDelta();

        RUN_TOKEN = IERC20(runToken);
        RUNNER = StockRunner(runner_);
        SPLITTER = RevenueSplitter(payable(splitter_));
        priceOracle = IRunPriceOracle(priceOracle_);

        spotPrice = initialSpotPrice;
        delta = delta_;
        minSpotPrice = minSpotPrice_;
    }

    /*//////////////////////////////////////////////////////////////
                             GENESIS MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice Activate a blank Stock//Runner for exactly 1,000,000 $RUN. No fee, no allowlist.
    /// @dev The $RUN round-trips: this contract pays the StockRunner, which forwards it to its
    ///      treasury — set to this contract — so genesis proceeds capitalise the pool. That is what
    ///      gives the pool the $RUN to buy units back with, and what the Fixer lends against later.
    function activateGenesis() external nonReentrant returns (uint256 tokenId) {
        uint256 price = RUNNER.GENESIS_PRICE();

        RUN_TOKEN.safeTransferFrom(msg.sender, address(this), price);
        RUN_TOKEN.forceApprove(address(RUNNER), price);

        tokenId = RUNNER.mint();
        RUNNER.safeTransferFrom(address(this), msg.sender, tokenId);

        emit GenesisActivated(msg.sender, tokenId, price);
    }

    /*//////////////////////////////////////////////////////////////
                              BUY / SELL
    //////////////////////////////////////////////////////////////*/

    /// @notice Buy a random unit out of the pool. 10% fee.
    ///
    /// @dev **KNOWN LIMITATION — the draw is predictable to a contract caller.**
    ///      `block.prevrandao` is not entropy on this Orbit chain: the mixHash is a structured
    ///      Arbitrum L1-info encoding, byte-identical across hundreds of consecutive blocks
    ///      (verified against the RPC). Every other input — `blockhash(n-1)`, `msg.sender`,
    ///      `_drawNonce`, `n` — is also known at call time.
    ///
    ///      So a contract can compute which unit it would receive and revert unless it is the one it
    ///      wanted, retrying until it gets it. That buys "specific" selection at the random-unit
    ///      price, saving the 5-percentage-point fee difference for the cost of gas per attempt.
    ///      An EOA cannot do this.
    ///
    ///      Accepted deliberately rather than fixed: closing it properly requires commit-reveal,
    ///      which turns a one-click purchase into two transactions. The Chop Shop, where real value
    ///      rides on each outcome, does use commit-reveal (see IRandomnessSource). Revisit if
    ///      Chainlink VRF ever lands on Robinhood Chain — it is not supported there today.
    ///
    /// @param maxTotal Slippage guard — the most $RUN the caller will pay in total.
    function buyRandom(uint256 maxTotal) external nonReentrant returns (uint256 tokenId) {
        uint256 n = _inventory.length;
        if (n == 0) revert PoolEmpty();

        // Bound to the caller and to a per-call nonce, so you cannot cheaply retry until a draw
        // hands you the unit you actually wanted at the random-unit discount.
        uint256 idx = uint256(
            keccak256(abi.encode(blockhash(block.number - 1), block.prevrandao, msg.sender, _drawNonce++, n))
        ) % n;
        tokenId = _inventory[idx];

        _buy(tokenId, BUY_RANDOM_BPS, false, maxTotal);
    }

    /// @notice Buy a named unit out of the pool. 15% fee — you pay for the right to choose.
    function buySpecific(uint256 tokenId, uint256 maxTotal) external nonReentrant {
        if (!_inPool[tokenId]) revert UnitNotInPool();
        _buy(tokenId, BUY_SPECIFIC_BPS, true, maxTotal);
    }

    function _buy(uint256 tokenId, uint256 feeBps, bool specific, uint256 maxTotal) private {
        uint256 price = spotPrice;
        uint256 fee = (price * feeBps) / BPS_DENOMINATOR;
        uint256 total = price + fee;
        if (total > maxTotal) revert SlippageExceeded(total, maxTotal);

        RUN_TOKEN.safeTransferFrom(msg.sender, address(this), total);

        _removeFromInventory(tokenId);
        _routeFee(fee);

        // Each unit leaving the pool makes the next one dearer.
        spotPrice = price + delta;
        emit SpotPriceMoved(spotPrice);

        RUNNER.safeTransferFrom(address(this), msg.sender, tokenId);
        emit UnitBought(msg.sender, tokenId, price, fee, specific);
    }

    /// @notice Sell a unit into the pool at the current quote, less the TWAP-tiered sell fee.
    /// @param minPayout Slippage guard — the least $RUN the caller will accept.
    /// @dev The caller must have approved this contract for the token first.
    function sell(uint256 tokenId, uint256 minPayout) external nonReentrant returns (uint256 payout) {
        if (RUNNER.ownerOf(tokenId) != msg.sender) revert NotUnitOwner();

        uint256 price = quoteSell();
        uint256 fee = (price * sellFeeBps()) / BPS_DENOMINATOR;
        payout = price - fee;
        if (payout < minPayout) revert SlippageExceeded(payout, minPayout);

        uint256 available = RUN_TOKEN.balanceOf(address(this));
        if (available < price) revert InsufficientPoolFunds(price, available);

        RUNNER.safeTransferFrom(msg.sender, address(this), tokenId);

        _routeFee(fee);
        RUN_TOKEN.safeTransfer(msg.sender, payout);

        // Each unit entering the pool makes the next one cheaper.
        uint256 next = spotPrice > delta ? spotPrice - delta : 0;
        spotPrice = next < minSpotPrice ? minSpotPrice : next;
        emit SpotPriceMoved(spotPrice);

        emit UnitSold(msg.sender, tokenId, payout, fee);
    }

    function _routeFee(uint256 fee) private {
        if (fee == 0) return;
        RUN_TOKEN.forceApprove(address(SPLITTER), fee);
        SPLITTER.deposit(address(RUN_TOKEN), fee);
        lifetimeFees += fee;
    }

    /*//////////////////////////////////////////////////////////////
                                QUOTES
    //////////////////////////////////////////////////////////////*/

    /// @notice What the pool charges for a unit right now, before fees.
    function quoteBuy() public view returns (uint256) {
        return spotPrice;
    }

    /// @notice What the pool pays for a unit right now, before fees.
    /// @dev One `delta` below the buy quote, so the pool never buys at the same price it sells —
    ///      that spread is what stops a buy-and-immediately-sell round trip draining the pool.
    function quoteSell() public view returns (uint256) {
        uint256 price = spotPrice > delta ? spotPrice - delta : 0;
        return price < minSpotPrice ? minSpotPrice : price;
    }

    /// @notice Total $RUN a buyer pays, including fee.
    function buyTotal(bool specific) external view returns (uint256 price, uint256 fee, uint256 total) {
        price = quoteBuy();
        fee = (price * (specific ? BUY_SPECIFIC_BPS : BUY_RANDOM_BPS)) / BPS_DENOMINATOR;
        total = price + fee;
    }

    /// @notice Net $RUN a seller receives, after the tiered fee.
    function sellNet() external view returns (uint256 price, uint256 fee, uint256 payout) {
        price = quoteSell();
        fee = (price * sellFeeBps()) / BPS_DENOMINATOR;
        payout = price - fee;
    }

    /// @notice The sell fee tier that applies right now, in basis points.
    /// @dev Tiered by the unit's ETH value at the current $RUN price: 25% below a 0.1 ETH floor,
    ///      15% between 0.1 and 1 ETH, 10% above 1 ETH. Cheap units pay the most, which keeps the
    ///      pool from being used as a free dumping ground at the bottom of the market.
    function sellFeeBps() public view returns (uint256) {
        uint256 valueWei = unitValueInWei();
        if (valueWei < TIER_FLOOR_WEI) return SELL_BPS_BELOW_FLOOR;
        if (valueWei <= TIER_CEILING_WEI) return SELL_BPS_MID;
        return SELL_BPS_ABOVE;
    }

    /// @notice The pool's sell quote expressed in wei, via the $RUN price oracle.
    function unitValueInWei() public view returns (uint256) {
        return (quoteSell() * priceOracle.ethPerRun()) / 1e18;
    }

    /*//////////////////////////////////////////////////////////////
                               INVENTORY
    //////////////////////////////////////////////////////////////*/

    function poolSize() external view returns (uint256) {
        return _inventory.length;
    }

    function inventory() external view returns (uint256[] memory) {
        return _inventory;
    }

    function isInPool(uint256 tokenId) external view returns (bool) {
        return _inPool[tokenId];
    }

    /// @notice $RUN the pool holds — the ceiling on how many units it can buy back.
    function poolLiquidity() external view returns (uint256) {
        return RUN_TOKEN.balanceOf(address(this));
    }

    function _addToInventory(uint256 tokenId) private {
        if (_inPool[tokenId]) return;
        _inventoryIndex[tokenId] = _inventory.length;
        _inventory.push(tokenId);
        _inPool[tokenId] = true;
    }

    /// @dev Swap-and-pop, so removal is O(1) regardless of pool size.
    function _removeFromInventory(uint256 tokenId) private {
        if (!_inPool[tokenId]) revert UnitNotInPool();
        uint256 idx = _inventoryIndex[tokenId];
        uint256 last = _inventory.length - 1;
        if (idx != last) {
            uint256 moved = _inventory[last];
            _inventory[idx] = moved;
            _inventoryIndex[moved] = idx;
        }
        _inventory.pop();
        delete _inventoryIndex[tokenId];
        delete _inPool[tokenId];
    }

    /// @dev Units arrive here two ways: minted by `activateGenesis` (immediately forwarded on, so
    ///      never added to inventory) and sold in via `sell`. Only the latter becomes pool stock.
    function onERC721Received(address, address from, uint256 tokenId, bytes calldata)
        external
        override
        returns (bytes4)
    {
        if (msg.sender == address(RUNNER) && from != address(0) && from != address(this)) {
            _addToInventory(tokenId);
        }
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function setCurve(uint256 delta_, uint256 minSpotPrice_) external onlyOwner {
        if (delta_ == 0) revert ZeroDelta();
        delta = delta_;
        minSpotPrice = minSpotPrice_;
        emit CurveUpdated(delta_, minSpotPrice_);
    }

    /// @notice Swap the $RUN price source. Mainnet points this at a real pool TWAP or feed.
    function setPriceOracle(address oracle) external onlyOwner {
        if (oracle == address(0)) revert ZeroAddress();
        priceOracle = IRunPriceOracle(oracle);
        emit PriceOracleUpdated(oracle);
    }
}
