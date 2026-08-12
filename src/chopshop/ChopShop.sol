// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

import {IRandomnessSource} from "./IRandomnessSource.sol";
import {RevenueSplitter} from "../market/RevenueSplitter.sol";

/// @title The Chop Shop — run by the Scrapper
/// @notice Deposit a Stock//Runner or an Augment, backed by an amount of USDG. **The less you back
///         it with, the better everyone's odds on a roll** — backing is how a depositor sets the
///         difficulty. Entry costs the expected value of the roll plus 30%; 10% of that is revenue.
///         The table rotates daily.
///
/// @dev **The odds curve.** The spec left this an open item. Implemented as:
///
///          p(win) = V / (V + B)
///
///      where V is the item's declared USDG value and B the backing. Backing nothing is a certain
///      win; backing equal to value is a coin flip; backing three times value is 25%. Monotonically
///      decreasing in B, exactly as the spec requires, and legible without a model — the same
///      standard applied to the tenure and bonding curves.
///
///      A **backing floor** of 25% of declared value stops a heavily-built unit being listed at
///      trivial backing. Declared value is otherwise self-policing: understating it makes your own
///      item easy to win, and overstating it prices rollers out.
///
///      **Rolls are two-step.** Chainlink VRF does not support this chain, so entropy comes from a
///      future block hash via IRandomnessSource. `roll` commits, `resolve` settles. Resolution is
///      permissionless so a keeper can drive it; a request that outruns its window is expired and
///      the entry is refunded in full.
contract ChopShop is Ownable, ReentrancyGuard, IERC721Receiver, ERC1155Holder {
    using SafeERC20 for IERC20;

    enum ItemKind {
        Runner, // ERC-721 Stock//Runner
        Augment // ERC-1155 Augment

    }

    enum RollState {
        None,
        Committed,
        Won,
        Lost,
        Refunded
    }

    enum Payout {
        TakeItem, // receive the deposited item
        CashOut, // 85% of the backing in USDG instead
        Convert // 90% of declared value in $AUG instead

    }

    struct Listing {
        address depositor;
        ItemKind kind;
        address token;
        uint256 tokenId;
        uint256 declaredValue; // USDG
        uint256 backing; // USDG
        uint256 expiresAt;
        bool open; // still rollable
        bool settled; // item has left
    }

    struct Roll {
        uint256 listingId;
        address roller;
        uint256 entryPaid;
        uint256 requestId;
        /// @dev The source this roll was committed against. Pinned per roll because
        ///      `setRandomnessSource` would otherwise strand every in-flight roll: the new source
        ///      knows nothing of the old request id, so it can neither resolve nor expire, and the
        ///      listing stays closed behind it. Found by swapping the source on a live roll.
        IRandomnessSource source;
        RollState state;
    }

    /// @notice Entry costs expected value plus 30%.
    uint256 public constant ENTRY_MARKUP_BPS = 13_000;

    /// @notice 10% of every entry payment is taken as revenue.
    uint256 public constant ENTRY_REVENUE_BPS = 1000;

    /// @notice Cash-out pays 85% of the backing; the rest is revenue.
    uint256 public constant CASHOUT_BPS = 8500;

    /// @notice Convert pays 90% of declared value; the rest is revenue.
    uint256 public constant CONVERT_BPS = 9000;

    /// @notice Backing may not fall below a quarter of declared value.
    uint256 public constant MIN_BACKING_BPS = 2500;

    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice The table rotates daily.
    uint256 public constant LISTING_DURATION = 1 days;

    IERC20 public immutable USDG;
    IERC20 public immutable AUG_TOKEN;
    RevenueSplitter public immutable SPLITTER;

    IRandomnessSource public randomnessSource;

    /// @notice $AUG paid per 1 USDG of value on a Convert payout, 1e18 fixed point.
    /// @dev Owner-settable because there is no $AUG/USD venue on this chain yet. On mainnet this
    ///      should read a Chainlink Data Feed — those ARE live on Robinhood Chain.
    uint256 public augPerUsdg = 1e18;

    mapping(uint256 listingId => Listing) public listings;
    mapping(uint256 rollId => Roll) public rolls;
    uint256 public nextListingId = 1;
    uint256 public nextRollId = 1;

    event Listed(
        uint256 indexed listingId,
        address indexed depositor,
        ItemKind kind,
        uint256 declaredValue,
        uint256 backing,
        uint256 winProbabilityBps
    );
    event ListingWithdrawn(uint256 indexed listingId);
    event Rolled(uint256 indexed rollId, uint256 indexed listingId, address indexed roller, uint256 entry);
    event Resolved(uint256 indexed rollId, bool won, uint256 draw, uint256 threshold);
    event Claimed(uint256 indexed rollId, Payout payout, uint256 amount);
    event RollRefunded(uint256 indexed rollId, uint256 amount);
    event RandomnessSourceUpdated(address indexed source);

    error NotDepositor();
    error NotRoller();
    error ListingClosed();
    error ListingStillOpen();
    error BackingBelowFloor(uint256 backing, uint256 floor);
    error ZeroValue();
    error RollNotCommitted();
    error RollNotReady();
    error RollNotWon();
    error NotExpired();
    error ZeroAddress();
    error UnsupportedKind();

    constructor(address usdg, address aug, address splitter, address randomness) Ownable(msg.sender) {
        if (usdg == address(0) || aug == address(0) || splitter == address(0) || randomness == address(0))
        {
            revert ZeroAddress();
        }
        USDG = IERC20(usdg);
        AUG_TOKEN = IERC20(aug);
        SPLITTER = RevenueSplitter(payable(splitter));
        randomnessSource = IRandomnessSource(randomness);
    }

    /*//////////////////////////////////////////////////////////////
                                THE TABLE
    //////////////////////////////////////////////////////////////*/

    /// @notice Win probability for a listing, in basis points. p = V / (V + B).
    function winProbabilityBps(uint256 declaredValue, uint256 backing) public pure returns (uint256) {
        if (declaredValue == 0) return 0;
        return (declaredValue * BPS_DENOMINATOR) / (declaredValue + backing);
    }

    /// @notice What a roll costs: expected value plus 30%.
    function entryCost(uint256 declaredValue, uint256 backing) public pure returns (uint256) {
        uint256 p = winProbabilityBps(declaredValue, backing);
        uint256 expectedValue = (declaredValue * p) / BPS_DENOMINATOR;
        return (expectedValue * ENTRY_MARKUP_BPS) / BPS_DENOMINATOR;
    }

    function listingEntryCost(uint256 listingId) public view returns (uint256) {
        Listing storage l = listings[listingId];
        return entryCost(l.declaredValue, l.backing);
    }

    /// @notice Put an item on the table, backed by USDG.
    /// @param declaredValue The item's value in USDG. Sets both the odds and the entry price.
    /// @param backing USDG risked. Lower backing means better odds for rollers.
    function list(
        ItemKind kind,
        address token,
        uint256 tokenId,
        uint256 declaredValue,
        uint256 backing
    ) external nonReentrant returns (uint256 listingId) {
        if (declaredValue == 0) revert ZeroValue();

        uint256 floor = (declaredValue * MIN_BACKING_BPS) / BPS_DENOMINATOR;
        if (backing < floor) revert BackingBelowFloor(backing, floor);

        listingId = nextListingId++;
        listings[listingId] = Listing({
            depositor: msg.sender,
            kind: kind,
            token: token,
            tokenId: tokenId,
            declaredValue: declaredValue,
            backing: backing,
            expiresAt: block.timestamp + LISTING_DURATION,
            open: true,
            settled: false
        });

        _pullItem(kind, token, tokenId, msg.sender);
        USDG.safeTransferFrom(msg.sender, address(this), backing);

        emit Listed(
            listingId, msg.sender, kind, declaredValue, backing, winProbabilityBps(declaredValue, backing)
        );
    }

    /// @notice Reclaim an unrolled listing once the table rotates.
    function withdrawListing(uint256 listingId) external nonReentrant {
        Listing storage l = listings[listingId];
        if (l.depositor != msg.sender) revert NotDepositor();
        if (!l.open || l.settled) revert ListingClosed();
        if (block.timestamp < l.expiresAt) revert ListingStillOpen();

        l.open = false;
        l.settled = true;
        _pushItem(l.kind, l.token, l.tokenId, msg.sender);
        USDG.safeTransfer(msg.sender, l.backing);
        emit ListingWithdrawn(listingId);
    }

    /*//////////////////////////////////////////////////////////////
                                THE ROLL
    //////////////////////////////////////////////////////////////*/

    /// @notice Pay the entry and commit a roll. Settle it later with `resolve`.
    function roll(uint256 listingId) external nonReentrant returns (uint256 rollId) {
        Listing storage l = listings[listingId];
        if (!l.open || l.settled || block.timestamp >= l.expiresAt) revert ListingClosed();

        uint256 entry = listingEntryCost(listingId);
        USDG.safeTransferFrom(msg.sender, address(this), entry);

        // Close the listing for the duration of the roll so two people can't play for one item.
        l.open = false;

        rollId = nextRollId++;
        uint256 requestId = randomnessSource.requestRandomness(
            keccak256(abi.encode(msg.sender, listingId, rollId, block.timestamp))
        );

        rolls[rollId] = Roll({
            listingId: listingId,
            roller: msg.sender,
            entryPaid: entry,
            requestId: requestId,
            source: randomnessSource,
            state: RollState.Committed
        });

        emit Rolled(rollId, listingId, msg.sender, entry);
    }

    /// @notice Settle a committed roll. Permissionless, so a keeper can drive it.
    function resolve(uint256 rollId) external nonReentrant returns (bool won) {
        Roll storage r = rolls[rollId];
        if (r.state != RollState.Committed) revert RollNotCommitted();
        if (!r.source.isReady(r.requestId)) revert RollNotReady();

        Listing storage l = listings[r.listingId];
        uint256 threshold = winProbabilityBps(l.declaredValue, l.backing);
        uint256 draw = r.source.randomness(r.requestId) % BPS_DENOMINATOR;
        won = draw < threshold;

        // 10% of the entry is revenue either way.
        uint256 revenue = (r.entryPaid * ENTRY_REVENUE_BPS) / BPS_DENOMINATOR;
        _routeRevenue(revenue);

        if (won) {
            r.state = RollState.Won;
            // The remaining 90% of the entry goes to the depositor — they are losing the item.
            USDG.safeTransfer(l.depositor, r.entryPaid - revenue);
        } else {
            r.state = RollState.Lost;
            l.open = block.timestamp < l.expiresAt; // back on the table if the day isn't done
            // Depositor keeps the item and takes the rest of the entry.
            USDG.safeTransfer(l.depositor, r.entryPaid - revenue);
        }

        emit Resolved(rollId, won, draw, threshold);
    }

    /// @notice Claim a won roll, choosing how to take it.
    function claim(uint256 rollId, Payout payout) external nonReentrant returns (uint256 amount) {
        Roll storage r = rolls[rollId];
        if (r.state != RollState.Won) revert RollNotWon();
        Listing storage l = listings[r.listingId];

        r.state = RollState.Refunded; // consumed
        l.settled = true;
        l.open = false;

        if (payout == Payout.TakeItem) {
            _pushItem(l.kind, l.token, l.tokenId, r.roller);
            USDG.safeTransfer(l.depositor, l.backing); // backing goes home
            amount = 0;
        } else if (payout == Payout.CashOut) {
            amount = (l.backing * CASHOUT_BPS) / BPS_DENOMINATOR;
            _routeRevenue(l.backing - amount);
            USDG.safeTransfer(r.roller, amount);
            _pushItem(l.kind, l.token, l.tokenId, l.depositor); // depositor keeps the item
        } else {
            // Convert — 90% of declared value, paid in $AUG.
            uint256 usdgWorth = (l.declaredValue * CONVERT_BPS) / BPS_DENOMINATOR;
            amount = (usdgWorth * augPerUsdg) / 1e18;
            AUG_TOKEN.safeTransfer(r.roller, amount);
            USDG.safeTransfer(l.depositor, l.backing);
            _pushItem(l.kind, l.token, l.tokenId, l.depositor);
        }

        emit Claimed(rollId, payout, amount);
    }

    /// @notice Refund a roll whose randomness window closed before anyone resolved it.
    /// @dev The ~25 second window on this chain makes this a real case, not a theoretical one.
    function refundExpiredRoll(uint256 rollId) external nonReentrant {
        Roll storage r = rolls[rollId];
        if (r.state != RollState.Committed) revert RollNotCommitted();
        if (!r.source.isExpired(r.requestId)) revert NotExpired();

        r.state = RollState.Refunded;
        Listing storage l = listings[r.listingId];
        l.open = block.timestamp < l.expiresAt;

        USDG.safeTransfer(r.roller, r.entryPaid);
        emit RollRefunded(rollId, r.entryPaid);
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _routeRevenue(uint256 amount) private {
        if (amount == 0) return;
        USDG.forceApprove(address(SPLITTER), amount);
        SPLITTER.deposit(address(USDG), amount);
    }

    function _pullItem(ItemKind kind, address token, uint256 tokenId, address from) private {
        if (kind == ItemKind.Runner) {
            IERC721(token).safeTransferFrom(from, address(this), tokenId);
        } else if (kind == ItemKind.Augment) {
            IERC1155(token).safeTransferFrom(from, address(this), tokenId, 1, "");
        } else {
            revert UnsupportedKind();
        }
    }

    function _pushItem(ItemKind kind, address token, uint256 tokenId, address to) private {
        if (kind == ItemKind.Runner) {
            IERC721(token).safeTransferFrom(address(this), to, tokenId);
        } else {
            IERC1155(token).safeTransferFrom(address(this), to, tokenId, 1, "");
        }
    }

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Swap the entropy source. This is the VRF migration path.
    /// @dev Only affects rolls committed after this call — each roll pins the source it used, so a
    ///      swap can never strand one mid-flight.
    function setRandomnessSource(address source) external onlyOwner {
        if (source == address(0)) revert ZeroAddress();
        randomnessSource = IRandomnessSource(source);
        emit RandomnessSourceUpdated(source);
    }

    /// @notice Set the $AUG per USDG rate used by Convert payouts.
    function setAugPerUsdg(uint256 rate) external onlyOwner {
        if (rate == 0) revert ZeroValue();
        augPerUsdg = rate;
    }
}
