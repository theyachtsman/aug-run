// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC2981} from "@openzeppelin/contracts/token/common/ERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

import {Cycles} from "./Cycles.sol";
import {IERC6551Registry} from "./interfaces/IERC6551.sol";

/// @title Stock//Runner — the bearer NFT
/// @notice 333 recovered corporate units. Every one mints blank at the same price, gets its own
///         ERC-6551 wallet, and becomes whatever its operator installs into it.
/// @dev Owns all per-unit state: model, bay count, and per-bay seating. Phase 3's Ripperdoc drives
///      that state through the `onlyRipperdoc` mutators below, but the structural invariants — bay
///      bounds, the three-bay ceiling, one-change-per-bay-per-cycle, tenure reset on rebind — are
///      enforced HERE, so a buggy or replaced Ripperdoc cannot violate them.
contract StockRunner is ERC721, ERC2981, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice A permanent maximum. Once 333 are activated there is no mechanism to create more.
    uint256 public constant MAX_SUPPLY = 333;

    /// @notice Genesis activation cost. Fixed in $RUN, not pegged to a dollar figure.
    uint256 public constant GENESIS_PRICE = 1_000_000e18;

    /// @notice Model lines. 333 = 11 x 30 + 3, so lines 0-2 carry 31 units and lines 3-10 carry 30.
    uint8 public constant MODEL_COUNT = 11;

    /// @notice A unit ships with one bay and can reach three via two Expansion Modules.
    uint8 public constant MAX_BAYS = 3;

    /// @notice Salt for the token-bound account. One account per unit, so a constant salt is correct.
    bytes32 public constant TBA_SALT = bytes32(0);

    /// @notice 5% ERC-2981 royalty on sales that happen outside the protocol, in basis points.
    /// @dev A leak patch, not a revenue grab. Black Market fees only fire on trades routed through
    ///      it, and those run 10–25%, so there is real incentive to trade elsewhere. This sits
    ///      deliberately BELOW the Black Market's own fee tier: trading on the Row should still be
    ///      cheaper, so leaving isn't free rather than being punished. Split 60/20/20 like every
    ///      other fee, via the RevenueSplitter.
    uint96 public constant ROYALTY_BPS = 500;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable RUN_TOKEN;
    IERC6551Registry public immutable REGISTRY;
    address public immutable ACCOUNT_IMPLEMENTATION;

    /// @notice Mixed into every model draw. Fixed at deploy, so the bucket walk is reproducible
    ///         off-chain for auditing but unknown before the contract exists.
    bytes32 public immutable MODEL_SEED;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @notice Receives genesis mint payment. Phase 4 replaces this with the Black Market AMM.
    address public treasury;

    /// @notice Phase 3's Ripperdoc. The only address allowed to mutate bay state.
    address public ripperdoc;

    /// @notice Genesis minting is closed until the operator opens it. **One-way.**
    /// @dev The spec sequences $RUN's launch ahead of the mint — "$RUN launches first, mint opens
    ///      after" — and the site and art are meant to be finished before either. Without this the
    ///      mint is live the instant the contract is deployed, and deployment-watching bots would
    ///      take the first units before anyone else knew the address existed. Withholding the UI is
    ///      not a control; the contract is public.
    ///
    ///      Deliberately **one-way**: it can be opened but never closed again. A closeable mint is a
    ///      lever over holders, and an operator who can halt minting at will is an operator who can
    ///      be pressured to. Once the 333 are open, they stay open.
    bool public mintingOpen;

    /// @notice Units activated so far. Token IDs run 1..333.
    uint256 public totalMinted;

    /// @dev Remaining unassigned units per model line. Drained by the bucket draw.
    uint16[MODEL_COUNT] private _modelRemaining;

    /// @dev Sum of `_modelRemaining`. Kept alongside so the draw is one modulo, not a running sum.
    uint16 private _unassignedTotal;

    /// @notice Per-unit model line. Cosmetic only — no mechanical effect anywhere in the protocol.
    mapping(uint256 tokenId => uint8 model) public modelOf;

    /// @notice Bays available on a unit. Starts at 1, capped at MAX_BAYS.
    mapping(uint256 tokenId => uint8 bays) public bayCountOf;

    /// @notice Calibrations recorded against a unit. Each adds +0.003x to its tenure multiplier.
    mapping(uint256 tokenId => uint32 count) public calibrationCountOf;

    /// @notice UTC day index of a unit's last calibration. One per unit per day.
    mapping(uint256 tokenId => uint64 day) public lastCalibrationDayOf;

    struct Bay {
        uint256 augmentId; // 0 means empty
        uint8 tier; // 0 when empty
        uint64 seatedAtCycle; // cycle the current Augment was seated in
        uint64 lastChangedCycle; // cycle this bay was last altered
        bool everChanged; // distinguishes "never touched" from "changed in cycle 0"
    }

    mapping(uint256 tokenId => mapping(uint8 bayIndex => Bay)) private _bays;

    /// @notice Testnet-only cycle fast-forward. Added to the real clock. See the banner below.
    uint256 public cycleOffset;

    /*//////////////////////////////////////////////////////////////

        ████  T E S T N E T   C Y C L E   F A S T - F O R W A R D  ████

        `TESTNET` is an immutable set once, in the constructor. When false —
        what a mainnet deployment MUST pass — `advanceCycles()` reverts
        unconditionally and `cycleOffset` can never move off zero, leaving
        `currentCycle()` a pure function of block.timestamp exactly as the
        spec requires.

        This exists so tenure and seasoning are testable in minutes instead
        of over eight real weeks. Same gating rule as the token faucets.

        TO SHIP TO MAINNET: deploy with testnet_ = false.

    //////////////////////////////////////////////////////////////*/

    /// @notice True only on testnet deployments. Gates `advanceCycles()`.
    bool public immutable TESTNET;

    /*//////////////////////////////////////////////////////////////
                            EVENTS & ERRORS
    //////////////////////////////////////////////////////////////*/

    event RunnerActivated(uint256 indexed tokenId, address indexed operator, uint8 model, address tba);
    event BayChanged(
        uint256 indexed tokenId, uint8 indexed bayIndex, uint256 augmentId, uint8 tier, uint256 cycle
    );
    event BayAdded(uint256 indexed tokenId, uint8 newBayCount);
    event Calibrated(uint256 indexed tokenId, uint32 totalCalibrations, uint64 utcDay);
    event CyclesFastForwarded(uint256 by, uint256 newOffset, uint256 effectiveCycle);
    event TreasuryUpdated(address indexed treasury);
    event RipperdocUpdated(address indexed ripperdoc);
    event RoyaltyReceiverUpdated(address indexed receiver);
    event MintingOpened(uint256 at);

    error SupplyExhausted();
    error NonexistentUnit();
    error NotRipperdoc();
    error TestnetOnly();
    error ZeroAddress();
    error BayIndexOutOfRange();
    error BayLockedThisCycle();
    error BayAlreadyEmpty();
    error BayCeilingReached();
    error AlreadyCalibratedToday();
    error InvalidTier();
    error RipperdocAlreadySet();
    error MintingNotOpen();
    error MintingAlreadyOpen();

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    constructor(address runToken, address registry, address accountImplementation, address treasury_, bool testnet_)
        ERC721("Stock//Runner", "RUNNER")
        Ownable(msg.sender)
    {
        if (runToken == address(0) || registry == address(0) || accountImplementation == address(0)) {
            revert ZeroAddress();
        }
        if (treasury_ == address(0)) revert ZeroAddress();

        RUN_TOKEN = IERC20(runToken);
        REGISTRY = IERC6551Registry(registry);
        ACCOUNT_IMPLEMENTATION = accountImplementation;
        treasury = treasury_;
        TESTNET = testnet_;

        // Defaults to the treasury so royalties are never payable to address(0); phase 4 repoints
        // this at the RevenueSplitter, which fans it out 60/20/20 like every other fee.
        _setDefaultRoyalty(treasury_, ROYALTY_BPS);

        MODEL_SEED = keccak256(
            abi.encode(blockhash(block.number - 1), block.timestamp, block.prevrandao, address(this))
        );

        // 333 = 11 x 30 + 3. The three remainder units go to the first three lines — deterministic,
        // and the only asymmetry in the collection. Equal counts are what keep supply rarity off
        // the table, so this distribution is load-bearing.
        uint16 base = uint16(MAX_SUPPLY / MODEL_COUNT); // 30
        uint16 remainder = uint16(MAX_SUPPLY % MODEL_COUNT); // 3
        for (uint8 i = 0; i < MODEL_COUNT; i++) {
            _modelRemaining[i] = i < remainder ? base + 1 : base;
        }
        _unassignedTotal = uint16(MAX_SUPPLY);
    }

    /*//////////////////////////////////////////////////////////////
                             GENESIS MINT
    //////////////////////////////////////////////////////////////*/

    /// @notice Activate a blank Stock//Runner for 1,000,000 $RUN.
    /// @dev Every mint goes through this path. No owner mint, no reserve, no allowlist, no bulk.
    ///      Caller must have approved this contract for GENESIS_PRICE beforehand.
    function mint() external nonReentrant returns (uint256 tokenId) {
        if (!mintingOpen) revert MintingNotOpen();
        if (totalMinted >= MAX_SUPPLY) revert SupplyExhausted();

        unchecked {
            tokenId = ++totalMinted;
        }

        // Payment first. Phase 4 routes this to the Black Market AMM instead of a plain treasury.
        RUN_TOKEN.safeTransferFrom(msg.sender, treasury, GENESIS_PRICE);

        uint8 model = _drawModel(tokenId);
        modelOf[tokenId] = model;
        bayCountOf[tokenId] = 1;

        _safeMint(msg.sender, tokenId);

        address tba = REGISTRY.createAccount(
            ACCOUNT_IMPLEMENTATION, TBA_SALT, block.chainid, address(this), tokenId
        );

        emit RunnerActivated(tokenId, msg.sender, model, tba);
    }

    /// @dev Exact-count bucket draw. Walks the remaining-per-line buckets and decrements the one it
    ///      lands in, so final counts are exactly 31/31/31/30x8 no matter the draw sequence.
    ///
    ///      Binding `msg.sender` into the hash is what makes this non-gameable: a caller cannot
    ///      reroll by resubmitting, because their own address is an input. The only lever available
    ///      is to revert on an unwanted result, which costs gas and yields nothing — the bucket
    ///      state is unchanged, so the next caller simply draws instead.
    function _drawModel(uint256 tokenId) private returns (uint8) {
        uint256 remaining = _unassignedTotal;
        uint256 draw = uint256(
            keccak256(abi.encode(MODEL_SEED, tokenId, block.prevrandao, msg.sender))
        ) % remaining;

        for (uint8 i = 0; i < MODEL_COUNT; i++) {
            uint16 inLine = _modelRemaining[i];
            if (draw < inLine) {
                _modelRemaining[i] = inLine - 1;
                _unassignedTotal = uint16(remaining - 1);
                return i;
            }
            unchecked {
                draw -= inLine;
            }
        }
        revert SupplyExhausted(); // unreachable while _unassignedTotal is consistent
    }

    /*//////////////////////////////////////////////////////////////
                          TOKEN-BOUND ACCOUNTS
    //////////////////////////////////////////////////////////////*/

    /// @notice The ERC-6551 wallet address for a unit.
    /// @dev Deterministic — returns the same address whether or not it has been deployed yet.
    function tokenBoundAccount(uint256 tokenId) public view returns (address) {
        return REGISTRY.account(ACCOUNT_IMPLEMENTATION, TBA_SALT, block.chainid, address(this), tokenId);
    }

    /*//////////////////////////////////////////////////////////////
                                CYCLES
    //////////////////////////////////////////////////////////////*/

    /// @notice The current cycle. The one clock rebinding, seasoning and tenure all read.
    /// @dev On mainnet `cycleOffset` is permanently zero, making this a pure function of time.
    function currentCycle() public view returns (uint256) {
        return Cycles.cycleAt(block.timestamp) + cycleOffset;
    }

    /// @notice Seconds until the next Monday 00:00 UTC boundary.
    function timeUntilNextCycle() external view returns (uint256) {
        return Cycles.timeUntilNextBoundary(block.timestamp);
    }

    /// @notice Timestamp of the next cycle boundary.
    function nextCycleBoundary() external view returns (uint256) {
        return Cycles.nextBoundary(block.timestamp);
    }

    /// @notice Fast-forward the effective cycle. **Testnet only** — see the banner above.
    /// @dev Permissionless on testnet, matching the faucets, so any wallet driving the harness can
    ///      exercise tenure and seasoning without needing the deployer key.
    function advanceCycles(uint256 count) external {
        if (!TESTNET) revert TestnetOnly();
        cycleOffset += count;
        emit CyclesFastForwarded(count, cycleOffset, currentCycle());
    }

    /*//////////////////////////////////////////////////////////////
                          BAY STATE (RIPPERDOC)
    //////////////////////////////////////////////////////////////*/

    modifier onlyRipperdoc() {
        if (msg.sender != ripperdoc) revert NotRipperdoc();
        _;
    }

    /// @notice Seat, swap, or clear a bay. Pass `augmentId == 0` to empty it.
    /// @dev The single entry point for bay changes, so the one-change-per-cycle lock is checked
    ///      exactly once even for a swap (which is logically a sell plus a buy). Tenure resets to
    ///      zero on every change — including when a new owner rebinds after buying the unit. That
    ///      reset is what makes a tenured unit worth its premium only *as configured*.
    function setBay(uint256 tokenId, uint8 bayIndex, uint256 augmentId, uint8 tier)
        external
        onlyRipperdoc
    {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentUnit();
        if (bayIndex >= bayCountOf[tokenId]) revert BayIndexOutOfRange();
        if (augmentId != 0 && (tier == 0 || tier > 3)) revert InvalidTier();

        Bay storage bay = _bays[tokenId][bayIndex];
        uint256 cycle = currentCycle();

        if (bay.everChanged && bay.lastChangedCycle == cycle) revert BayLockedThisCycle();
        if (augmentId == 0 && bay.augmentId == 0) revert BayAlreadyEmpty();

        bay.augmentId = augmentId;
        bay.tier = augmentId == 0 ? 0 : tier;
        bay.seatedAtCycle = uint64(cycle);
        bay.lastChangedCycle = uint64(cycle);
        bay.everChanged = true;

        emit BayChanged(tokenId, bayIndex, augmentId, bay.tier, cycle);
    }

    /// @notice Install an Expansion Module — opens one additional bay, max two per unit.
    function addBay(uint256 tokenId) external onlyRipperdoc {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentUnit();
        uint8 count = bayCountOf[tokenId];
        if (count >= MAX_BAYS) revert BayCeilingReached();
        bayCountOf[tokenId] = ++count;
        emit BayAdded(tokenId, count);
    }

    /// @notice Record a Calibration against a unit. One per unit per UTC day.
    function recordCalibration(uint256 tokenId) external onlyRipperdoc {
        if (_ownerOf(tokenId) == address(0)) revert NonexistentUnit();
        uint64 today = uint64(block.timestamp / 1 days);
        if (lastCalibrationDayOf[tokenId] == today) revert AlreadyCalibratedToday();

        lastCalibrationDayOf[tokenId] = today;
        uint32 total = ++calibrationCountOf[tokenId];
        emit Calibrated(tokenId, total, today);
    }

    /*//////////////////////////////////////////////////////////////
                              BAY VIEWS
    //////////////////////////////////////////////////////////////*/

    function getBay(uint256 tokenId, uint8 bayIndex) external view returns (Bay memory) {
        if (bayIndex >= MAX_BAYS) revert BayIndexOutOfRange();
        return _bays[tokenId][bayIndex];
    }

    /// @notice Full cycles this bay's Augment has served.
    /// @dev An Augment seated during cycle N is present at the open of N+1 and has completed no
    ///      full cycle yet — it is "freshly seasoned" at N+1, which the spec pins at 1.0x. Its
    ///      first completed cycle lands at N+2. Hence `cycle - seatedAtCycle - 1`.
    function tenureCycles(uint256 tokenId, uint8 bayIndex) public view returns (uint256) {
        Bay storage bay = _bays[tokenId][bayIndex];
        if (bay.augmentId == 0) return 0;
        uint256 cycle = currentCycle();
        if (cycle <= bay.seatedAtCycle + 1) return 0;
        return cycle - bay.seatedAtCycle - 1;
    }

    /// @notice Whether a bay is eligible to earn this cycle.
    /// @dev Seasoning: an Augment counts only if seated at both the open and the close of the cycle.
    ///      Seated mid-cycle earns nothing until the next full one.
    function isBayEligible(uint256 tokenId, uint8 bayIndex) public view returns (bool) {
        Bay storage bay = _bays[tokenId][bayIndex];
        if (bay.augmentId == 0) return false;
        return currentCycle() > bay.seatedAtCycle;
    }

    /// @notice Whether a bay may be changed in the current cycle.
    function isBayUnlocked(uint256 tokenId, uint8 bayIndex) external view returns (bool) {
        Bay storage bay = _bays[tokenId][bayIndex];
        if (!bay.everChanged) return true;
        return bay.lastChangedCycle != currentCycle();
    }

    /// @notice Remaining unassigned units per model line. Sums to `MAX_SUPPLY - totalMinted`.
    function modelRemaining() external view returns (uint16[MODEL_COUNT] memory) {
        return _modelRemaining;
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Wire up phase 3's Ripperdoc.
    /// @dev **On mainnet this is strictly set-once** — bay state must not be re-pointable, because
    ///      whoever holds this address can rewrite every unit's seating and tenure.
    ///
    ///      On a testnet deployment the owner may re-point it. Later phases (the Black Market, the
    ///      Terminal, the Fixer) replace the Ripperdoc, and under strict set-once every one of those
    ///      would force a fresh StockRunner and a re-mint of every test unit. Same gating rule as
    ///      the faucets and `advanceCycles` — TESTNET is immutable and false in production.
    function setRipperdoc(address ripperdoc_) external onlyOwner {
        if (ripperdoc_ == address(0)) revert ZeroAddress();
        if (ripperdoc != address(0) && !TESTNET) revert RipperdocAlreadySet();
        ripperdoc = ripperdoc_;
        emit RipperdocUpdated(ripperdoc_);
    }

    /// @notice Repoint genesis mint proceeds. Phase 4 sets this to the Black Market AMM.
    function setTreasury(address treasury_) external onlyOwner {
        if (treasury_ == address(0)) revert ZeroAddress();
        treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    /// @notice Open genesis minting. Irreversible — there is no matching close.
    /// @dev Call this only when $RUN is tradeable and the site is live. From that moment the 333 are
    ///      mintable by anyone, forever, and no one (including the owner) can stop it.
    function openMinting() external onlyOwner {
        if (mintingOpen) revert MintingAlreadyOpen();
        mintingOpen = true;
        emit MintingOpened(block.timestamp);
    }

    /// @notice Repoint the ERC-2981 royalty receiver. Phase 4 sets this to the RevenueSplitter.
    /// @dev The rate itself is fixed at ROYALTY_BPS and cannot be raised — only the destination
    ///      moves, so a unit's resale cost is knowable and can't be changed out from under a holder.
    function setRoyaltyReceiver(address receiver) external onlyOwner {
        if (receiver == address(0)) revert ZeroAddress();
        _setDefaultRoyalty(receiver, ROYALTY_BPS);
        emit RoyaltyReceiverUpdated(receiver);
    }

    /// @dev ERC721 and ERC2981 both declare it; resolve explicitly so marketplaces detect both.
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC2981)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
