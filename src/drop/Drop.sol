// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {StockRunner} from "../runner/StockRunner.sol";
import {Ripperdoc} from "../items/Ripperdoc.sol";
import {Augments} from "../items/Augments.sol";
import {RevenueSplitter} from "../market/RevenueSplitter.sol";
import {IRwaVenue} from "./IRwaVenue.sol";

/// @title The Drop — protocol revenue becomes real-world assets in Stock//Runner wallets
/// @notice The payoff every other mechanic feeds. Weekly, anchored to Monday 00:00 UTC. The pool
///         splits across every **eligible bay by weight** — not evenly, and not per unit.
///
/// @dev **The pool is whatever the protocol actually earned.** No minimum yield, no promised APY;
///      small revenue means small Drops, not failed ones.
///
///      **Allocation runs in batches.** Up to 999 bays across 333 units is too much for one
///      transaction to be safe at full size, so a keeper walks the collection with `accumulate`
///      before `finalize` fires the purchases. Weights are read from the StockRunner itself and
///      never supplied by anyone, so the process is trustless — a keeper can only choose *when* a
///      Drop happens, never who gets what.
///
///      **Purchases are aggregate.** One call per ticker, then divided among the bays running it.
///      Twelve Augments means at most twelve purchases regardless of collection size.
///
///      **Delivery is pull-based.** The Courier doesn't deliver — he holds a package and the
///      operator comes to collect. Assets sit here until claimed into the unit's ERC-6551 wallet,
///      with the operator paying their own gas.
contract Drop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    enum Phase {
        None,
        Accumulating,
        Claimable,
        Closed
    }

    struct Round {
        uint256 cycle;
        uint256 pool; // payToken committed to this Drop
        uint256 totalWeight; // 1e18 fixed point, summed over eligible bays
        uint256 cursor; // next tokenId to accumulate
        uint256 spent; // payToken actually converted
        uint256 claimDeadline;
        Phase phase;
    }

    /// @notice The claim window closes one hour before the next Drop.
    uint256 public constant CLAIM_WINDOW_LEAD = 1 hours;

    /// @notice Gas a single claim is assumed to cost, for the dust floor.
    /// @dev The spec left the dust threshold "pending real gas measurements". Measured on this
    ///      chain: gas is 0.01 gwei, so a claim costs ~0.0000015 ETH and almost nothing falls below
    ///      it. Kept as a live measurement rather than a constant so it adapts if that changes.
    uint256 public constant CLAIM_GAS_ESTIMATE = 150_000;

    IERC20 public immutable PAY_TOKEN; // $RUN — what Black Market fees arrive as
    StockRunner public immutable RUNNER;
    Ripperdoc public immutable RIPPERDOC;
    Augments public immutable AUGMENTS;
    RevenueSplitter public immutable SPLITTER;

    IRwaVenue public venue;

    uint256 public nextDropId = 1;
    mapping(uint256 dropId => Round) public rounds;

    /// @dev Snapshot taken during accumulation, so later rebinding cannot rewrite history.
    mapping(uint256 dropId => mapping(uint256 tokenId => mapping(uint8 bayIndex => uint256))) public
        bayWeightAt;
    mapping(uint256 dropId => mapping(uint256 tokenId => mapping(uint8 bayIndex => uint256))) public
        bayAugmentAt;

    /// @notice Weight per ticker, which is what sizes each aggregate purchase.
    mapping(uint256 dropId => mapping(uint256 augmentId => uint256)) public tickerWeight;
    mapping(uint256 dropId => mapping(uint256 augmentId => uint256)) public rwaBought;
    mapping(uint256 dropId => mapping(uint256 augmentId => address)) public rwaAsset;

    mapping(uint256 dropId => mapping(uint256 tokenId => bool)) public claimed;

    /// @notice Below-dust-floor amounts, held rather than sold, compounding until worth collecting.
    mapping(uint256 tokenId => mapping(address asset => uint256)) public dustCredit;

    /// @notice Proceeds of unclaimed Drops, awaiting the $RUN buyback.
    uint256 public buybackPool;
    uint256 public totalBoughtBack;

    /// @notice Weight that earned nothing because its ticker was unavailable — rolls into the next pool.
    mapping(uint256 dropId => uint256) public skippedPool;

    event DropOpened(uint256 indexed dropId, uint256 cycle, uint256 pool);
    event Accumulated(uint256 indexed dropId, uint256 cursor, uint256 totalWeight);
    event DropFinalized(uint256 indexed dropId, uint256 totalWeight, uint256 spent, uint256 deadline);
    event TickerPurchased(uint256 indexed dropId, uint256 indexed augmentId, uint256 spent, uint256 acquired);
    event TickerSkipped(uint256 indexed dropId, uint256 indexed augmentId, uint256 rolledForward);
    event DropClaimed(uint256 indexed dropId, uint256 indexed tokenId, address indexed tba);
    event DustHeld(uint256 indexed tokenId, address asset, uint256 amount);
    event UnclaimedSwept(uint256 indexed dropId, uint256 tokenId, uint256 proceeds);
    event BuybackExecuted(uint256 amount);
    event VenueUpdated(address indexed venue);

    error WrongPhase();
    error AccumulationIncomplete();
    error AccumulationComplete();
    error NothingToDrop();
    error NotUnitOwner();
    error AlreadyClaimed();
    error ClaimWindowClosed();
    error ClaimWindowOpen();
    error ZeroAddress();
    error DropStillOpen();

    constructor(
        address payToken,
        address runner_,
        address ripperdoc_,
        address augments_,
        address splitter_,
        address venue_
    ) Ownable(msg.sender) {
        if (
            payToken == address(0) || runner_ == address(0) || ripperdoc_ == address(0)
                || augments_ == address(0) || splitter_ == address(0) || venue_ == address(0)
        ) revert ZeroAddress();
        PAY_TOKEN = IERC20(payToken);
        RUNNER = StockRunner(runner_);
        RIPPERDOC = Ripperdoc(ripperdoc_);
        AUGMENTS = Augments(augments_);
        SPLITTER = RevenueSplitter(payable(splitter_));
        venue = IRwaVenue(venue_);
    }

    /*//////////////////////////////////////////////////////////////
                              OPEN & ACCUMULATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Start a Drop: pull the accumulated 60% and begin weighing the collection.
    /// @dev Permissionless. Anyone may fire a Drop; nobody can change who earns from it.
    function openDrop() external nonReentrant returns (uint256 dropId) {
        uint256 previous = nextDropId - 1;
        if (previous > 0 && rounds[previous].phase == Phase.Accumulating) revert WrongPhase();

        uint256 fromSplitter = SPLITTER.accrued(address(PAY_TOKEN), RevenueSplitter.Bucket.Drop);
        if (fromSplitter > 0) SPLITTER.claim(address(PAY_TOKEN), RevenueSplitter.Bucket.Drop);

        // Anything a previous Drop could not spend (unavailable tickers) rolls into this pool.
        uint256 rolled = previous > 0 ? skippedPool[previous] : 0;
        if (rolled > 0) skippedPool[previous] = 0;

        uint256 pool = fromSplitter + rolled;
        if (pool == 0) revert NothingToDrop();

        dropId = nextDropId++;
        rounds[dropId] = Round({
            cycle: RUNNER.currentCycle(),
            pool: pool,
            totalWeight: 0,
            cursor: 1,
            spent: 0,
            claimDeadline: 0,
            phase: Phase.Accumulating
        });

        emit DropOpened(dropId, rounds[dropId].cycle, pool);
    }

    /// @notice Walk up to `count` units, snapshotting eligible bay weights.
    /// @dev Only **eligible** bays count — an Augment must have been seated at both the open and the
    ///      close of the cycle. Seated mid-cycle earns nothing until the next full one.
    function accumulate(uint256 dropId, uint256 count) external returns (bool done) {
        Round storage r = rounds[dropId];
        if (r.phase != Phase.Accumulating) revert WrongPhase();

        uint256 minted = RUNNER.totalMinted();
        uint256 id = r.cursor;
        if (id > minted) revert AccumulationComplete();

        uint256 end = id + count;
        if (end > minted + 1) end = minted + 1;

        uint256 weightAdded;
        for (; id < end; id++) {
            uint8 bays = RUNNER.bayCountOf(id);
            for (uint8 b = 0; b < bays; b++) {
                if (!RUNNER.isBayEligible(id, b)) continue;
                uint256 w = RIPPERDOC.bayWeight(id, b);
                if (w == 0) continue;

                StockRunner.Bay memory bay = RUNNER.getBay(id, b);
                bayWeightAt[dropId][id][b] = w;
                bayAugmentAt[dropId][id][b] = bay.augmentId;
                tickerWeight[dropId][bay.augmentId] += w;
                weightAdded += w;
            }
        }

        r.cursor = id;
        r.totalWeight += weightAdded;
        done = id > minted;

        emit Accumulated(dropId, id, r.totalWeight);
    }

    /*//////////////////////////////////////////////////////////////
                                 FINALIZE
    //////////////////////////////////////////////////////////////*/

    /// @notice Convert the pool into RWAs — one aggregate purchase per ticker — and open the window.
    function finalize(uint256 dropId) external nonReentrant {
        Round storage r = rounds[dropId];
        if (r.phase != Phase.Accumulating) revert WrongPhase();
        if (r.cursor <= RUNNER.totalMinted()) revert AccumulationIncomplete();

        uint256 catalogSize = AUGMENTS.augmentCount();
        uint256 spent;
        uint256 skipped;

        if (r.totalWeight > 0) {
            for (uint256 a = 1; a <= catalogSize; a++) {
                uint256 w = tickerWeight[dropId][a];
                if (w == 0) continue;

                uint256 slice = (r.pool * w) / r.totalWeight;
                if (slice == 0) continue;

                bytes32 ticker = _tickerHash(a);
                if (!venue.isAvailable(ticker)) {
                    // Skipped for this cycle; its share rolls into the next pool. No substitute.
                    skipped += slice;
                    emit TickerSkipped(dropId, a, slice);
                    continue;
                }

                PAY_TOKEN.forceApprove(address(venue), slice);
                (address asset, uint256 out) = venue.buy(ticker, address(PAY_TOKEN), slice);
                if (asset == address(0) || out == 0) {
                    PAY_TOKEN.forceApprove(address(venue), 0);
                    skipped += slice;
                    emit TickerSkipped(dropId, a, slice);
                    continue;
                }

                rwaAsset[dropId][a] = asset;
                rwaBought[dropId][a] = out;
                spent += slice;
                emit TickerPurchased(dropId, a, slice, out);
            }
        }

        // Whatever could not be deployed rolls forward rather than sitting idle.
        skippedPool[dropId] = skipped + (r.pool - spent - skipped);
        r.spent = spent;
        r.claimDeadline = RUNNER.nextCycleBoundary() - CLAIM_WINDOW_LEAD;
        r.phase = Phase.Claimable;

        emit DropFinalized(dropId, r.totalWeight, spent, r.claimDeadline);
    }

    /// @dev Tickers are identified to the venue by the hash of their catalog symbol.
    function _tickerHash(uint256 augmentId) internal view returns (bytes32) {
        return keccak256(bytes(AUGMENTS.tickerOf(augmentId)));
    }

    /*//////////////////////////////////////////////////////////////
                                  CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice What a unit can collect from a Drop, per bay.
    function claimable(uint256 dropId, uint256 tokenId)
        public
        view
        returns (address[3] memory assets, uint256[3] memory amounts)
    {
        if (claimed[dropId][tokenId]) return (assets, amounts);
        for (uint8 b = 0; b < 3; b++) {
            uint256 w = bayWeightAt[dropId][tokenId][b];
            if (w == 0) continue;
            uint256 a = bayAugmentAt[dropId][tokenId][b];
            uint256 tw = tickerWeight[dropId][a];
            if (tw == 0) continue;
            assets[b] = rwaAsset[dropId][a];
            amounts[b] = (rwaBought[dropId][a] * w) / tw;
        }
    }

    /// @notice Collect a Drop into the unit's ERC-6551 wallet. The operator pays their own gas.
    /// @dev Assets go to the token-bound account, not the operator's wallet — the unit holds its own
    ///      positions, which is what makes its PnL its own and what a buyer inherits on a sale.
    function claim(uint256 dropId, uint256 tokenId) external nonReentrant {
        Round storage r = rounds[dropId];
        if (r.phase != Phase.Claimable) revert WrongPhase();
        if (block.timestamp > r.claimDeadline) revert ClaimWindowClosed();
        if (RUNNER.ownerOf(tokenId) != msg.sender) revert NotUnitOwner();
        if (claimed[dropId][tokenId]) revert AlreadyClaimed();

        // Read the allocation BEFORE marking it claimed — `claimable` returns zeros once the flag
        // is set, so flipping it first would silently deliver nothing while closing the claim.
        (address[3] memory assets, uint256[3] memory amounts) = claimable(dropId, tokenId);

        claimed[dropId][tokenId] = true;
        address tba = RUNNER.tokenBoundAccount(tokenId);
        uint256 floor = dustFloor();
        for (uint8 b = 0; b < 3; b++) {
            if (assets[b] == address(0) || amounts[b] == 0) continue;
            // Below the floor it was never worth escrowing; hold it so it compounds instead.
            if (amounts[b] < floor) {
                dustCredit[tokenId][assets[b]] += amounts[b];
                emit DustHeld(tokenId, assets[b], amounts[b]);
                continue;
            }
            IERC20(assets[b]).safeTransfer(tba, amounts[b]);
        }

        emit DropClaimed(dropId, tokenId, tba);
    }

    /// @notice Collect accumulated dust once it is finally worth collecting.
    function claimDust(uint256 tokenId, address asset) external nonReentrant {
        if (RUNNER.ownerOf(tokenId) != msg.sender) revert NotUnitOwner();
        uint256 amount = dustCredit[tokenId][asset];
        if (amount == 0) revert NothingToDrop();
        dustCredit[tokenId][asset] = 0;
        IERC20(asset).safeTransfer(RUNNER.tokenBoundAccount(tokenId), amount);
    }

    /// @notice The minimum an escrowed amount must exceed to be worth claiming, measured live.
    /// @dev Gas cost of a claim at the current gas price. On this chain that is ~0.0000015 ETH, so
    ///      the floor rarely bites — but it is measured rather than fixed, so it tracks conditions.
    function dustFloor() public view returns (uint256) {
        return tx.gasprice * CLAIM_GAS_ESTIMATE;
    }

    /*//////////////////////////////////////////////////////////////
                        SWEEP UNCLAIMED -> BUYBACK
    //////////////////////////////////////////////////////////////*/

    /// @notice After the window closes, sell what nobody collected. Batched like accumulation.
    /// @dev "Anything unclaimed at expiry is sold, and the proceeds fund a $RUN buyback." A unit
    ///      whose operator doesn't show up funds the operators who did.
    function sweepUnclaimed(uint256 dropId, uint256 fromId, uint256 toId) external nonReentrant {
        Round storage r = rounds[dropId];
        if (r.phase != Phase.Claimable) revert WrongPhase();
        if (block.timestamp <= r.claimDeadline) revert ClaimWindowOpen();

        for (uint256 id = fromId; id <= toId; id++) {
            if (claimed[dropId][id]) continue;
            (address[3] memory assets, uint256[3] memory amounts) = claimable(dropId, id);
            claimed[dropId][id] = true;

            uint256 proceeds;
            for (uint8 b = 0; b < 3; b++) {
                if (assets[b] == address(0) || amounts[b] == 0) continue;
                IERC20(assets[b]).forceApprove(address(venue), amounts[b]);
                proceeds += venue.sell(assets[b], amounts[b], address(PAY_TOKEN));
            }
            if (proceeds > 0) {
                buybackPool += proceeds;
                emit UnclaimedSwept(dropId, id, proceeds);
            }
        }
    }

    /// @notice Mark a swept Drop closed once nothing is left to sweep.
    function closeDrop(uint256 dropId) external {
        Round storage r = rounds[dropId];
        if (r.phase != Phase.Claimable) revert WrongPhase();
        if (block.timestamp <= r.claimDeadline) revert ClaimWindowOpen();
        r.phase = Phase.Closed;
    }

    /// @notice Send accumulated buyback proceeds where they deepen the $RUN market.
    /// @dev The spec directs unclaimed value into a $RUN buyback — it deepens the Black Market pool
    ///      the Fixer also lends from, and supports the token mint pricing is denominated in.
    ///      Stakers and LPs already take 40% of every fee, so pointing buybacks at $AUG instead
    ///      would concentrate value on the same participants twice.
    function executeBuyback(address to) external onlyOwner nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = buybackPool;
        if (amount == 0) revert NothingToDrop();
        buybackPool = 0;
        totalBoughtBack += amount;
        PAY_TOKEN.safeTransfer(to, amount);
        emit BuybackExecuted(amount);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEWS
    //////////////////////////////////////////////////////////////*/

    function currentDropId() external view returns (uint256) {
        return nextDropId - 1;
    }

    function accumulationProgress(uint256 dropId) external view returns (uint256 cursor, uint256 total) {
        return (rounds[dropId].cursor, RUNNER.totalMinted());
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap the venue. Mainnet points this at real Robinhood Stock Token liquidity.
    function setVenue(address venue_) external onlyOwner {
        if (venue_ == address(0)) revert ZeroAddress();
        venue = IRwaVenue(venue_);
        emit VenueUpdated(venue_);
    }
}
