// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {AUG} from "../tokens/AUG.sol";
import {StockRunner} from "../runner/StockRunner.sol";
import {Augments} from "./Augments.sol";
import {ExpansionModules} from "./ExpansionModules.sol";
import {Weights} from "./Weights.sol";

/// @title The Ripperdoc — buy Augments and Expansion Modules, seat them, swap them, sell them back
/// @notice Half of every $AUG payment burns permanently; half funds the protocol reserve, which
///         backs the Fixer's loans and Chop Shop redemptions.
/// @dev **Binding is enforced structurally, not by a check.** Seating BURNS the ERC-1155 token and
///      records the Augment as bay state on the Stock//Runner. A seated Augment therefore has no
///      token to move — there is no function anywhere that can transfer it to another unit, not even
///      one the same operator owns. That is what keeps tenure honest.
contract Ripperdoc is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    AUG public immutable AUG_TOKEN;
    StockRunner public immutable RUNNER;
    Augments public immutable AUGMENTS;
    ExpansionModules public immutable MODULES;

    /// @notice Receives the non-burned half of every payment.
    address public protocolReserve;

    /// @notice 500 $AUG — the same price as a tier-3 Augment. A deliberate fork: capacity or density.
    uint256 public constant MODULE_PRICE = 500e18;

    /// @notice 5 $AUG per unit per day at the Ripperdoc.
    uint256 public constant CALIBRATION_PRICE = 5e18;

    /// @notice Resale returns half of what was paid.
    uint256 public constant RESALE_NUMERATOR = 1;
    uint256 public constant RESALE_DENOMINATOR = 2;

    /// @notice $AUG-denominated credit from selling Augments back. Spent on future purchases.
    /// @dev The spec credits resale value "against the new one's cost" rather than paying it out,
    ///      so this is a ledger, not a transfer. It also keeps the protocol reserve from having to
    ///      fund buybacks out of a balance that phase 6 lends against.
    mapping(address operator => uint256 amount) public augCredit;

    /// @notice Lifetime totals, for the UI and for sanity-checking the split.
    uint256 public totalBurned;
    uint256 public totalToReserve;

    event AugmentPurchased(address indexed buyer, uint256 indexed augmentId, uint256 amount, uint256 paid);
    event AugmentSeated(
        uint256 indexed tokenId, uint8 indexed bayIndex, uint256 indexed augmentId, uint8 tier
    );
    event AugmentSoldBack(uint256 indexed tokenId, uint8 indexed bayIndex, uint256 augmentId, uint256 credit);
    event AugmentSwapped(
        uint256 indexed tokenId,
        uint8 indexed bayIndex,
        uint256 oldAugmentId,
        uint256 newAugmentId,
        uint256 netCost
    );
    event ModulePurchased(address indexed buyer, uint256 amount, uint256 paid);
    event ModuleInstalled(uint256 indexed tokenId, uint8 newBayCount);
    event UnitCalibrated(uint256 indexed tokenId, uint32 totalCalibrations);
    event PaymentSplit(uint256 paid, uint256 burned, uint256 toReserve);
    event CreditAdded(address indexed operator, uint256 amount, uint256 balance);
    event ProtocolReserveUpdated(address indexed reserve);

    error NotUnitOwner();
    error BayNotEmpty();
    error BayEmpty();
    error BayIndexOutOfRange();
    error ZeroAddress();
    error ZeroAmount();

    constructor(
        address aug_,
        address runner_,
        address augments_,
        address modules_,
        address protocolReserve_
    ) Ownable(msg.sender) {
        if (
            aug_ == address(0) || runner_ == address(0) || augments_ == address(0)
                || modules_ == address(0) || protocolReserve_ == address(0)
        ) revert ZeroAddress();

        AUG_TOKEN = AUG(aug_);
        RUNNER = StockRunner(runner_);
        AUGMENTS = Augments(augments_);
        MODULES = ExpansionModules(modules_);
        protocolReserve = protocolReserve_;
    }

    modifier onlyUnitOwner(uint256 tokenId) {
        if (RUNNER.ownerOf(tokenId) != msg.sender) revert NotUnitOwner();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              PAYMENT SPLIT
    //////////////////////////////////////////////////////////////*/

    /// @dev Collects `cost`, drawing from the caller's resale credit first and pulling the remainder
    ///      as $AUG. Exactly half of the $AUG ACTUALLY TRANSFERRED IN is burned and the rest
    ///      goes to the protocol reserve.
    ///
    ///      The split deliberately applies to real inflow, not to the credit portion: credit
    ///      represents value that was already split when the original Augment was bought. Splitting
    ///      it twice would demand more $AUG out than came in.
    ///
    ///      Odd amounts (only reachable via partial credit) round the burn down, so the odd wei
    ///      lands in the reserve rather than being destroyed.
    function _collect(address from, uint256 cost) internal returns (uint256 cashPaid) {
        if (cost == 0) return 0;

        uint256 credit = augCredit[from];
        uint256 fromCredit = credit >= cost ? cost : credit;
        if (fromCredit > 0) {
            augCredit[from] = credit - fromCredit;
        }

        cashPaid = cost - fromCredit;
        if (cashPaid > 0) {
            IERC20(address(AUG_TOKEN)).safeTransferFrom(from, address(this), cashPaid);

            uint256 burnAmount = cashPaid / 2;
            uint256 reserveAmount = cashPaid - burnAmount;

            AUG_TOKEN.burn(burnAmount);
            IERC20(address(AUG_TOKEN)).safeTransfer(protocolReserve, reserveAmount);

            totalBurned += burnAmount;
            totalToReserve += reserveAmount;
            emit PaymentSplit(cashPaid, burnAmount, reserveAmount);
        }
    }

    function _addCredit(address to, uint256 amount) internal {
        if (amount == 0) return;
        uint256 balance = augCredit[to] + amount;
        augCredit[to] = balance;
        emit CreditAdded(to, amount, balance);
    }

    /*//////////////////////////////////////////////////////////////
                            BUYING (LOOSE)
    //////////////////////////////////////////////////////////////*/

    /// @notice Buy Augments without seating them. They stay loose and transferable.
    /// @dev Rule 7: purchased-but-never-seated Augments remain ordinary ERC-1155 balances. These are
    ///      what the Fixer will accept as $AUG collateral in phase 6.
    function buyAugment(uint256 augmentId, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 cost = augmentPrice(augmentId) * amount;
        _collect(msg.sender, cost);
        AUGMENTS.mint(msg.sender, augmentId, amount);
        emit AugmentPurchased(msg.sender, augmentId, amount, cost);
    }

    /// @notice Buy Expansion Modules without installing them.
    function buyModule(uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        uint256 cost = MODULE_PRICE * amount;
        _collect(msg.sender, cost);
        MODULES.mint(msg.sender, amount);
        emit ModulePurchased(msg.sender, amount, cost);
    }

    /*//////////////////////////////////////////////////////////////
                                SEATING
    //////////////////////////////////////////////////////////////*/

    /// @notice Seat a loose Augment you already hold into an open bay on a unit you own.
    /// @dev Burns the ERC-1155. From this point the Augment exists only as bay state — permanently
    ///      bound to this unit, with no path to any other.
    function seatAugment(uint256 tokenId, uint8 bayIndex, uint256 augmentId)
        external
        nonReentrant
        onlyUnitOwner(tokenId)
    {
        _requireEmptyBay(tokenId, bayIndex);
        uint8 tier = AUGMENTS.tierOf(augmentId);

        AUGMENTS.burn(msg.sender, augmentId, 1);
        RUNNER.setBay(tokenId, bayIndex, augmentId, tier);

        emit AugmentSeated(tokenId, bayIndex, augmentId, tier);
    }

    /// @notice Buy an Augment and seat it in one transaction.
    function buyAndSeatAugment(uint256 tokenId, uint8 bayIndex, uint256 augmentId)
        external
        nonReentrant
        onlyUnitOwner(tokenId)
    {
        _requireEmptyBay(tokenId, bayIndex);
        uint8 tier = AUGMENTS.tierOf(augmentId);

        _collect(msg.sender, Weights.tierPrice(tier));
        RUNNER.setBay(tokenId, bayIndex, augmentId, tier);

        emit AugmentPurchased(msg.sender, augmentId, 1, Weights.tierPrice(tier));
        emit AugmentSeated(tokenId, bayIndex, augmentId, tier);
    }

    /// @notice Sell a seated Augment back to the Ripperdoc for half its purchase price as credit.
    /// @dev Empties the bay. Tenure resets — the bay must reseason from scratch if refilled.
    function sellBackAugment(uint256 tokenId, uint8 bayIndex)
        external
        nonReentrant
        onlyUnitOwner(tokenId)
    {
        StockRunner.Bay memory bay = _requireOccupiedBay(tokenId, bayIndex);

        uint256 credit = resaleValueOfTier(bay.tier);
        RUNNER.setBay(tokenId, bayIndex, 0, 0);
        _addCredit(msg.sender, credit);

        emit AugmentSoldBack(tokenId, bayIndex, bay.augmentId, credit);
    }

    /// @notice Swap the Augment in a bay: sell the old, buy the new, pay only the difference.
    /// @dev Selling a 100 tier-1 and buying a 250 tier-2 costs 200 $AUG net.
    ///
    ///      This performs exactly ONE bay change, so it consumes exactly one rebind against the
    ///      one-per-bay-per-cycle limit — a swap is a single decision, not a sell plus a buy.
    ///      Doing it as two separate calls in one cycle would (correctly) revert on the second.
    function swapAugment(uint256 tokenId, uint8 bayIndex, uint256 newAugmentId)
        external
        nonReentrant
        onlyUnitOwner(tokenId)
    {
        StockRunner.Bay memory bay = _requireOccupiedBay(tokenId, bayIndex);

        uint8 newTier = AUGMENTS.tierOf(newAugmentId);
        uint256 newPrice = Weights.tierPrice(newTier);
        uint256 credit = resaleValueOfTier(bay.tier);

        uint256 netCost;
        if (newPrice > credit) {
            netCost = newPrice - credit;
            _collect(msg.sender, netCost);
        } else {
            // Downgrading: the surplus resale value becomes spendable credit.
            _addCredit(msg.sender, credit - newPrice);
        }

        RUNNER.setBay(tokenId, bayIndex, newAugmentId, newTier);

        emit AugmentSwapped(tokenId, bayIndex, bay.augmentId, newAugmentId, netCost);
        emit AugmentSeated(tokenId, bayIndex, newAugmentId, newTier);
    }

    /*//////////////////////////////////////////////////////////////
                          EXPANSION MODULES
    //////////////////////////////////////////////////////////////*/

    /// @notice Install a Module you already hold, opening one more bay. Max two per unit.
    function installModule(uint256 tokenId) external nonReentrant onlyUnitOwner(tokenId) {
        MODULES.burn(msg.sender, 1);
        RUNNER.addBay(tokenId);
        emit ModuleInstalled(tokenId, RUNNER.bayCountOf(tokenId));
    }

    /// @notice Buy a Module and install it in one transaction.
    function buyAndInstallModule(uint256 tokenId) external nonReentrant onlyUnitOwner(tokenId) {
        _collect(msg.sender, MODULE_PRICE);
        RUNNER.addBay(tokenId);
        emit ModulePurchased(msg.sender, 1, MODULE_PRICE);
        emit ModuleInstalled(tokenId, RUNNER.bayCountOf(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                             CALIBRATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Calibrate a unit at the Ripperdoc. 5 $AUG, one per unit per day, +0.003x tenure.
    /// @dev Calibration is hardware maintenance, so it happens across the Ripperdoc's counter rather
    ///      than at the unstaffed Terminal kiosk — you bring the unit to someone who works on it.
    /// @dev Never adds yield directly and skipping never costs anything — tenure advances at its
    ///      normal rate regardless. Calibration only accelerates the climb to the same 1.5x ceiling.
    function calibrate(uint256 tokenId) external nonReentrant onlyUnitOwner(tokenId) {
        _collect(msg.sender, CALIBRATION_PRICE);
        RUNNER.recordCalibration(tokenId);
        emit UnitCalibrated(tokenId, RUNNER.calibrationCountOf(tokenId));
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function augmentPrice(uint256 augmentId) public view returns (uint256) {
        return Weights.tierPrice(AUGMENTS.tierOf(augmentId));
    }

    function resaleValueOfTier(uint8 tier) public pure returns (uint256) {
        return (Weights.tierPrice(tier) * RESALE_NUMERATOR) / RESALE_DENOMINATOR;
    }

    /// @notice What selling this bay's Augment back would credit.
    function resaleValue(uint256 tokenId, uint8 bayIndex) external view returns (uint256) {
        StockRunner.Bay memory bay = RUNNER.getBay(tokenId, bayIndex);
        if (bay.augmentId == 0) return 0;
        return resaleValueOfTier(bay.tier);
    }

    /// @notice Net $AUG a swap would cost. Zero if resale credit covers it entirely.
    function swapCost(uint256 tokenId, uint8 bayIndex, uint256 newAugmentId)
        external
        view
        returns (uint256)
    {
        StockRunner.Bay memory bay = RUNNER.getBay(tokenId, bayIndex);
        if (bay.augmentId == 0) revert BayEmpty();
        uint256 newPrice = Weights.tierPrice(AUGMENTS.tierOf(newAugmentId));
        uint256 credit = resaleValueOfTier(bay.tier);
        return newPrice > credit ? newPrice - credit : 0;
    }

    /// @notice Weight of a single bay, 1e18 fixed point. Zero if empty.
    function bayWeight(uint256 tokenId, uint8 bayIndex) public view returns (uint256) {
        StockRunner.Bay memory bay = RUNNER.getBay(tokenId, bayIndex);
        if (bay.augmentId == 0) return 0;
        return Weights.bayWeight(
            bay.tier, RUNNER.tenureCycles(tokenId, bayIndex), RUNNER.calibrationCountOf(tokenId)
        );
    }

    /// @notice Sum of all seated bay weights on a unit, 1e18 fixed point.
    function unitWeight(uint256 tokenId) external view returns (uint256 total) {
        uint8 bays = RUNNER.bayCountOf(tokenId);
        for (uint8 i = 0; i < bays; i++) {
            total += bayWeight(tokenId, i);
        }
    }

    /// @notice Sum of only those bay weights eligible to earn this cycle (seasoning applied).
    /// @dev This is the figure the phase-8 Drop will allocate against.
    function unitEligibleWeight(uint256 tokenId) external view returns (uint256 total) {
        uint8 bays = RUNNER.bayCountOf(tokenId);
        for (uint8 i = 0; i < bays; i++) {
            if (RUNNER.isBayEligible(tokenId, i)) total += bayWeight(tokenId, i);
        }
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    function _requireEmptyBay(uint256 tokenId, uint8 bayIndex) internal view {
        if (bayIndex >= RUNNER.bayCountOf(tokenId)) revert BayIndexOutOfRange();
        if (RUNNER.getBay(tokenId, bayIndex).augmentId != 0) revert BayNotEmpty();
    }

    function _requireOccupiedBay(uint256 tokenId, uint8 bayIndex)
        internal
        view
        returns (StockRunner.Bay memory bay)
    {
        if (bayIndex >= RUNNER.bayCountOf(tokenId)) revert BayIndexOutOfRange();
        bay = RUNNER.getBay(tokenId, bayIndex);
        if (bay.augmentId == 0) revert BayEmpty();
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function setProtocolReserve(address reserve) external onlyOwner {
        if (reserve == address(0)) revert ZeroAddress();
        protocolReserve = reserve;
        emit ProtocolReserveUpdated(reserve);
    }
}
