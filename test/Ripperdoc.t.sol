// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC1155Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {RUN} from "../src/tokens/RUN.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";
import {Augments} from "../src/items/Augments.sol";
import {ExpansionModules} from "../src/items/ExpansionModules.sol";
import {Ripperdoc} from "../src/items/Ripperdoc.sol";
import {Weights} from "../src/items/Weights.sol";
import {ERC6551RegistryFixture} from "./helpers/ERC6551RegistryFixture.sol";

contract RipperdocTest is Test {
    RUN internal runToken;
    AUG internal aug;
    StockRunner internal runner;
    Augments internal augments;
    ExpansionModules internal modules;
    Ripperdoc internal doc;

    address internal treasury = makeAddr("treasury");
    address internal reserve = makeAddr("protocolReserve");
    address internal seed = makeAddr("launchSeed");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    // Catalog IDs seeded in setUp. Tickers are PLACEHOLDERS — the real twelve depend on what is
    // genuinely tokenized and liquid as Stock Tokens on Robinhood Chain at launch.
    uint256 constant T1_SPY = 1;
    uint256 constant T1_JNJ = 2;
    uint256 constant T2_QQQ = 5;
    uint256 constant T2_AAPL = 6;
    uint256 constant T3_NVDA = 9;
    uint256 constant T3_MSFT = 10;

    uint256 constant MINT_PRICE = 1_000_000e18;

    function setUp() public {
        vm.warp(1786147200); // Sat 2026-08-08

        address registry = ERC6551RegistryFixture.install();
        ERC6551Account accountImpl = new ERC6551Account();

        runToken = new RUN(address(this), true);
        aug = new AUG(address(this), reserve, seed, true);

        runner = new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        augments = new Augments("https://augrun.test/augment/{id}.json", true);
        modules = new ExpansionModules("https://augrun.test/module/{id}.json", true);
        doc = new Ripperdoc(address(aug), address(runner), address(augments), address(modules), reserve);

        runner.setRipperdoc(address(doc));
        runner.openMinting();
        augments.setRipperdoc(address(doc));
        modules.setRipperdoc(address(doc));

        // Twelve at launch, four per tier, tier and risk deliberately independent.
        augments.addAugment("SPY", 1); // 1  broad index
        augments.addAugment("JNJ", 1); // 2  defensive
        augments.addAugment("BRKB", 1); // 3 value
        augments.addAugment("TSLA", 1); // 4 high-beta
        augments.addAugment("QQQ", 2); // 5  broad tech
        augments.addAugment("AAPL", 2); // 6 mega-cap
        augments.addAugment("KO", 2); // 7   defensive
        augments.addAugment("COIN", 2); // 8 volatile
        augments.addAugment("NVDA", 3); // 9 mega-cap momentum
        augments.addAugment("MSFT", 3); // 10 stable mega
        augments.addAugment("AMD", 3); // 11 volatile
        augments.addAugment("GLD", 3); // 12 alternative

        _fund(alice);
        _fund(bob);
    }

    function _fund(address who) internal {
        runToken.transfer(who, 10_000_000e18);
        aug.transfer(who, 1_000_000e18);
        vm.startPrank(who);
        runToken.approve(address(runner), type(uint256).max);
        aug.approve(address(doc), type(uint256).max);
        vm.stopPrank();
    }

    function _mintUnit(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = runner.mint();
    }

    function _unitWithBays(address who, uint8 bays) internal returns (uint256 id) {
        id = _mintUnit(who);
        vm.startPrank(who);
        for (uint8 i = 1; i < bays; i++) {
            doc.buyAndInstallModule(id);
        }
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              THE CATALOG
    //////////////////////////////////////////////////////////////*/

    function test_catalog_hasTwelveAtLaunch() public view {
        assertEq(augments.augmentCount(), 12);
    }

    function test_catalog_fourPerTier() public view {
        uint8[4] memory counts;
        for (uint256 i = 1; i <= 12; i++) {
            counts[augments.tierOf(i)]++;
        }
        assertEq(counts[1], 4);
        assertEq(counts[2], 4);
        assertEq(counts[3], 4);
    }

    /// @dev Extensibility is a hard requirement: adding Augments later must not require redeploying
    ///      or touching weight math.
    function test_catalog_isExtensibleWithoutRedeploy() public {
        uint256 id = augments.addAugment("ARKK", 2);
        assertEq(id, 13);
        assertEq(augments.augmentCount(), 13);
        assertEq(augments.tierOf(13), 2);
        assertEq(doc.augmentPrice(13), 250e18);

        // And the new entry is immediately usable end to end.
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, 13);
        assertEq(runner.getBay(unit, 0).augmentId, 13);
    }

    function test_catalog_pricesFollowTier() public view {
        assertEq(doc.augmentPrice(T1_SPY), 100e18);
        assertEq(doc.augmentPrice(T2_QQQ), 250e18);
        assertEq(doc.augmentPrice(T3_NVDA), 500e18);
    }

    /*//////////////////////////////////////////////////////////////
                    BURN / RESERVE SPLIT — HALF EACH
    //////////////////////////////////////////////////////////////*/

    /// @dev Half of every purchase burns, and total supply must drop by exactly that.
    function test_purchase_burnsExactlyHalf() public {
        uint256 supplyBefore = aug.totalSupply();
        uint256 reserveBefore = aug.balanceOf(reserve);

        vm.prank(alice);
        doc.buyAugment(T1_SPY, 1);

        assertEq(aug.totalSupply(), supplyBefore - 50e18, "supply must drop by exactly half");
        assertEq(aug.balanceOf(reserve), reserveBefore + 50e18, "other half to reserve");
        assertEq(doc.totalBurned(), 50e18);
        assertEq(doc.totalToReserve(), 50e18);
    }

    function test_split_appliesToModulesToo() public {
        uint256 supplyBefore = aug.totalSupply();
        uint256 reserveBefore = aug.balanceOf(reserve);

        vm.prank(alice);
        doc.buyModule(1);

        assertEq(aug.totalSupply(), supplyBefore - 250e18);
        assertEq(aug.balanceOf(reserve), reserveBefore + 250e18);
    }

    function test_split_appliesToCalibration() public {
        uint256 unit = _mintUnit(alice);
        uint256 supplyBefore = aug.totalSupply();

        vm.prank(alice);
        doc.calibrate(unit);

        assertEq(aug.totalSupply(), supplyBefore - 2.5e18);
    }

    function testFuzz_split_alwaysHalfOfCashPaid(uint8 tierPick, uint8 qty) public {
        uint256 id = bound(tierPick, 0, 11) + 1;
        uint256 amount = bound(qty, 1, 20);
        uint256 cost = doc.augmentPrice(id) * amount;

        uint256 supplyBefore = aug.totalSupply();
        uint256 reserveBefore = aug.balanceOf(reserve);

        vm.prank(alice);
        doc.buyAugment(id, amount);

        assertEq(aug.totalSupply(), supplyBefore - cost / 2);
        assertEq(aug.balanceOf(reserve), reserveBefore + cost / 2);
    }

    /// @dev The Ripperdoc must never sit on $AUG — every payment is fully split on receipt.
    function test_ripperdocHoldsNoAug() public {
        vm.startPrank(alice);
        doc.buyAugment(T3_NVDA, 3);
        doc.buyModule(2);
        vm.stopPrank();
        assertEq(aug.balanceOf(address(doc)), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        BINDING — THE CORE RULE
    //////////////////////////////////////////////////////////////*/

    /// @dev **Moving a seated Augment between two units the same wallet owns must revert.**
    ///      Called out explicitly because it is what makes tenure meaningful: if Augments could
    ///      shuttle between units, an operator with five Runners could farm tenure on a spare and
    ///      transplant it into whichever unit they were about to sell.
    ///
    ///      Enforced structurally — seating BURNS the ERC-1155, so there is no token left to move.
    function test_seatedAugmentCannotMoveBetweenUnitsTheSameWalletOwns() public {
        uint256 unitA = _mintUnit(alice);
        uint256 unitB = _mintUnit(alice);
        assertEq(runner.ownerOf(unitA), alice);
        assertEq(runner.ownerOf(unitB), alice, "same wallet owns both");

        vm.startPrank(alice);
        doc.buyAugment(T3_NVDA, 1);
        assertEq(augments.balanceOf(alice, T3_NVDA), 1, "loose before seating");

        doc.seatAugment(unitA, 0, T3_NVDA);
        assertEq(augments.balanceOf(alice, T3_NVDA), 0, "seating burns the token");
        assertEq(runner.getBay(unitA, 0).augmentId, T3_NVDA);

        // There is no transfer path, and re-seating it on unit B has nothing to burn.
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC1155Errors.ERC1155InsufficientBalance.selector, alice, 0, 1, T3_NVDA
            )
        );
        doc.seatAugment(unitB, 0, T3_NVDA);
        vm.stopPrank();

        assertEq(runner.getBay(unitB, 0).augmentId, 0, "unit B stays empty");
        assertEq(runner.getBay(unitA, 0).augmentId, T3_NVDA, "unit A keeps it");
    }

    /// @dev Rule 7: purchased-but-never-seated Augments stay loose and transferable.
    function test_looseAugmentsRemainTransferable() public {
        vm.startPrank(alice);
        doc.buyAugment(T2_QQQ, 2);
        augments.safeTransferFrom(alice, bob, T2_QQQ, 1, "");
        vm.stopPrank();

        assertEq(augments.balanceOf(alice, T2_QQQ), 1);
        assertEq(augments.balanceOf(bob, T2_QQQ), 1);
    }

    function test_cannotSeatIntoAUnitYouDoNotOwn() public {
        uint256 unit = _mintUnit(bob);
        vm.startPrank(alice);
        doc.buyAugment(T1_SPY, 1);
        vm.expectRevert(Ripperdoc.NotUnitOwner.selector);
        doc.seatAugment(unit, 0, T1_SPY);
        vm.stopPrank();
    }

    function test_cannotSeatIntoAnOccupiedBay() public {
        uint256 unit = _mintUnit(alice);
        vm.startPrank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);
        doc.buyAugment(T2_QQQ, 1);
        vm.expectRevert(Ripperdoc.BayNotEmpty.selector);
        doc.seatAugment(unit, 0, T2_QQQ);
        vm.stopPrank();
    }

    function test_cannotSeatIntoAnUnopenedBay() public {
        uint256 unit = _mintUnit(alice); // ships with one bay
        vm.startPrank(alice);
        doc.buyAugment(T1_SPY, 1);
        vm.expectRevert(Ripperdoc.BayIndexOutOfRange.selector);
        doc.seatAugment(unit, 1, T1_SPY);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          DUPLICATE TICKERS
    //////////////////////////////////////////////////////////////*/

    /// @dev Duplicates across bays are explicitly allowed — a maxi build. Identical expected value
    ///      at triple the variance, which is a real bet made deliberately.
    function test_duplicateAugmentsAcrossThreeBaysSucceeds() public {
        uint256 unit = _unitWithBays(alice, 3);
        assertEq(runner.bayCountOf(unit), 3);

        vm.startPrank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        doc.buyAndSeatAugment(unit, 1, T3_NVDA);
        doc.buyAndSeatAugment(unit, 2, T3_NVDA);
        vm.stopPrank();

        for (uint8 i = 0; i < 3; i++) {
            assertEq(runner.getBay(unit, i).augmentId, T3_NVDA, "same ticker in every bay");
            assertEq(runner.getBay(unit, i).tier, 3);
        }
        assertEq(doc.unitWeight(unit), 3 * 1.5e18, "three fresh tier-3 bays");
    }

    /*//////////////////////////////////////////////////////////////
                   ONE REBIND PER BAY PER CYCLE
    //////////////////////////////////////////////////////////////*/

    function test_twoRebindsOnSameBayInOneCycleReverts() public {
        uint256 unit = _mintUnit(alice);

        vm.startPrank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);

        // Swapping in the same cycle the bay was seated is a second change.
        vm.expectRevert(StockRunner.BayLockedThisCycle.selector);
        doc.swapAugment(unit, 0, T2_QQQ);
        vm.stopPrank();
    }

    function test_sellBackThenReseatInSameCycleReverts() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);

        runner.advanceCycles(1);

        vm.startPrank(alice);
        doc.sellBackAugment(unit, 0); // change one
        vm.expectRevert(StockRunner.BayLockedThisCycle.selector);
        doc.buyAndSeatAugment(unit, 0, T2_QQQ); // change two, same cycle
        vm.stopPrank();
    }

    function test_rebindAllowedNextCycle() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);

        runner.advanceCycles(1);

        vm.prank(alice);
        doc.swapAugment(unit, 0, T2_QQQ);
        assertEq(runner.getBay(unit, 0).augmentId, T2_QQQ);
    }

    /// @dev A swap is ONE decision, so it consumes exactly one rebind — not two.
    function test_swapConsumesExactlyOneRebind() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);
        runner.advanceCycles(1);

        vm.prank(alice);
        doc.swapAugment(unit, 0, T2_QQQ); // succeeds: one change this cycle

        runner.advanceCycles(1);
        vm.prank(alice);
        doc.swapAugment(unit, 0, T3_NVDA); // succeeds next cycle
        assertEq(runner.getBay(unit, 0).augmentId, T3_NVDA);
    }

    /*//////////////////////////////////////////////////////////////
                            SWAP ECONOMICS
    //////////////////////////////////////////////////////////////*/

    /// @dev Spec worked example: sell a 100 tier-1, buy a 250 tier-2, net 200 $AUG.
    function test_swapCostsTheDifference() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);
        runner.advanceCycles(1);

        assertEq(doc.swapCost(unit, 0, T2_QQQ), 200e18, "250 - 50 credit");

        uint256 balBefore = aug.balanceOf(alice);
        vm.prank(alice);
        doc.swapAugment(unit, 0, T2_QQQ);

        assertEq(balBefore - aug.balanceOf(alice), 200e18, "paid exactly the difference");
    }

    function test_swapToSameTier_costsHalf() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T2_QQQ);
        runner.advanceCycles(1);

        // 250 new, 125 credit => 125 net.
        assertEq(doc.swapCost(unit, 0, T2_AAPL), 125e18);

        uint256 balBefore = aug.balanceOf(alice);
        vm.prank(alice);
        doc.swapAugment(unit, 0, T2_AAPL);
        assertEq(balBefore - aug.balanceOf(alice), 125e18);
    }

    /// @dev Downgrading: tier-3 resale (250) exceeds a tier-1 price (100), so the surplus becomes
    ///      spendable credit rather than a payment.
    function test_downgradeSwap_costsNothingAndLeavesCredit() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        runner.advanceCycles(1);

        assertEq(doc.swapCost(unit, 0, T1_SPY), 0);

        uint256 balBefore = aug.balanceOf(alice);
        vm.prank(alice);
        doc.swapAugment(unit, 0, T1_SPY);

        assertEq(aug.balanceOf(alice), balBefore, "no cash moved");
        assertEq(doc.augCredit(alice), 150e18, "250 resale - 100 new price");
    }

    function test_sellBack_returnsHalfAsCredit() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        runner.advanceCycles(1);

        assertEq(doc.resaleValue(unit, 0), 250e18);

        vm.prank(alice);
        doc.sellBackAugment(unit, 0);

        assertEq(doc.augCredit(alice), 250e18);
        assertEq(runner.getBay(unit, 0).augmentId, 0, "bay emptied");
    }

    /// @dev Credit is spendable, and spending it must not double-split value that was already split.
    function test_creditIsSpendableAndNotResplit() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA); // pays 500
        runner.advanceCycles(1);
        vm.prank(alice);
        doc.sellBackAugment(unit, 0); // +250 credit
        assertEq(doc.augCredit(alice), 250e18);

        uint256 balBefore = aug.balanceOf(alice);
        uint256 supplyBefore = aug.totalSupply();

        vm.prank(alice);
        doc.buyAugment(T1_SPY, 1); // costs 100, fully covered by credit

        assertEq(aug.balanceOf(alice), balBefore, "no cash needed");
        assertEq(doc.augCredit(alice), 150e18, "credit drawn down");
        assertEq(aug.totalSupply(), supplyBefore, "nothing burned: no new cash came in");
    }

    /*//////////////////////////////////////////////////////////////
                       EXPANSION MODULES / CEILING
    //////////////////////////////////////////////////////////////*/

    function test_modulePriceIs500() public view {
        assertEq(doc.MODULE_PRICE(), 500e18);
    }

    function test_maxTwoModulesPerUnit() public {
        uint256 unit = _mintUnit(alice);
        vm.startPrank(alice);
        doc.buyAndInstallModule(unit);
        assertEq(runner.bayCountOf(unit), 2);
        doc.buyAndInstallModule(unit);
        assertEq(runner.bayCountOf(unit), 3);

        vm.expectRevert(StockRunner.BayCeilingReached.selector);
        doc.buyAndInstallModule(unit);
        vm.stopPrank();
    }

    function test_looseModuleCanBeBoughtThenInstalled() public {
        uint256 unit = _mintUnit(alice);
        vm.startPrank(alice);
        doc.buyModule(1);
        assertEq(modules.balanceOf(alice), 1);
        doc.installModule(unit);
        vm.stopPrank();

        assertEq(modules.balanceOf(alice), 0, "installing burns the module");
        assertEq(runner.bayCountOf(unit), 2);
    }

    /*//////////////////////////////////////////////////////////////
                         SEASONING & TENURE
    //////////////////////////////////////////////////////////////*/

    /// @dev Seated mid-cycle is ineligible that cycle and eligible the next.
    function test_seasoning_ineligibleThisCycleEligibleNext() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T2_QQQ);

        assertFalse(runner.isBayEligible(unit, 0));
        assertEq(doc.unitEligibleWeight(unit), 0, "earns nothing the cycle it was seated");
        assertEq(doc.unitWeight(unit), 1.25e18, "but its weight is still displayed");

        runner.advanceCycles(1);

        assertTrue(runner.isBayEligible(unit, 0));
        assertEq(doc.unitEligibleWeight(unit), 1.25e18, "eligible from the next full cycle");
    }

    function test_tenureCapsAt1point5xAndDoesNotExceed() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY); // tier 1, so bay weight == tenure multiplier

        runner.advanceCycles(9); // tenure = 8
        assertEq(runner.tenureCycles(unit, 0), 8);
        assertEq(doc.bayWeight(unit, 0), 1.5e18, "ceiling reached");

        runner.advanceCycles(20); // way past
        assertEq(doc.bayWeight(unit, 0), 1.5e18, "must not exceed");
    }

    function test_tenureClimbsLinearly() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);

        runner.advanceCycles(1);
        assertEq(doc.bayWeight(unit, 0), 1.0e18, "freshly seasoned");
        runner.advanceCycles(1);
        assertEq(doc.bayWeight(unit, 0), 1.0625e18);
        runner.advanceCycles(1);
        assertEq(doc.bayWeight(unit, 0), 1.125e18);
    }

    /// @dev Rebinding resets that bay's tenure to zero — the anti-churn mechanic.
    function test_rebindResetsTenureToZero() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);

        runner.advanceCycles(9);
        assertEq(doc.bayWeight(unit, 0), 2.25e18, "tier-3 at full tenure");

        vm.prank(alice);
        doc.swapAugment(unit, 0, T3_MSFT);

        assertEq(runner.tenureCycles(unit, 0), 0);
        assertEq(doc.bayWeight(unit, 0), 1.5e18, "back to fresh tier-3");
        assertEq(doc.unitEligibleWeight(unit), 0, "and must reseason");
    }

    /// @dev Tenure survives the sale; a new owner's rebind still resets it.
    function test_tenureSurvivesTransferButNewOwnerRebindStillResets() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        runner.advanceCycles(9);

        uint256 weightBefore = doc.bayWeight(unit, 0);
        assertEq(weightBefore, 2.25e18);

        vm.prank(alice);
        runner.transferFrom(alice, bob, unit);

        assertEq(doc.bayWeight(unit, 0), weightBefore, "buyer inherits earning power");
        assertGt(runner.tenureCycles(unit, 0), 0, "explicitly non-zero after transfer");

        vm.prank(bob);
        doc.swapAugment(unit, 0, T1_SPY);
        assertEq(runner.tenureCycles(unit, 0), 0, "rebinding destroys what the premium bought");
    }

    /*//////////////////////////////////////////////////////////////
                             CALIBRATION
    //////////////////////////////////////////////////////////////*/

    function test_calibration_costsFiveAndRaisesWeight() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);
        runner.advanceCycles(1);

        assertEq(doc.bayWeight(unit, 0), 1.0e18);

        uint256 balBefore = aug.balanceOf(alice);
        vm.prank(alice);
        doc.calibrate(unit);

        assertEq(balBefore - aug.balanceOf(alice), 5e18);
        assertEq(doc.bayWeight(unit, 0), 1.003e18);
    }

    function test_calibration_oncePerDay() public {
        uint256 unit = _mintUnit(alice);
        vm.startPrank(alice);
        doc.calibrate(unit);
        vm.expectRevert(StockRunner.AlreadyCalibratedToday.selector);
        doc.calibrate(unit);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        vm.prank(alice);
        doc.calibrate(unit);
        assertEq(runner.calibrationCountOf(unit), 2);
    }

    function test_calibration_liftsEveryBayOnTheUnit() public {
        uint256 unit = _unitWithBays(alice, 3);
        vm.startPrank(alice);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);
        doc.buyAndSeatAugment(unit, 1, T2_QQQ);
        doc.buyAndSeatAugment(unit, 2, T3_NVDA);
        doc.calibrate(unit);
        vm.stopPrank();

        assertEq(doc.bayWeight(unit, 0), 1.003e18);
        assertEq(doc.bayWeight(unit, 1), 1.25375e18);
        assertEq(doc.bayWeight(unit, 2), 1.5045e18);
    }

    function test_calibration_cannotPushPastCeiling() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        runner.advanceCycles(9); // already at the 1.5x tenure ceiling

        assertEq(doc.bayWeight(unit, 0), 2.25e18);
        vm.prank(alice);
        doc.calibrate(unit);
        assertEq(doc.bayWeight(unit, 0), 2.25e18, "calibration cannot exceed the ceiling");
    }

    function test_calibration_onlyUnitOwner() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(bob);
        vm.expectRevert(Ripperdoc.NotUnitOwner.selector);
        doc.calibrate(unit);
    }

    /*//////////////////////////////////////////////////////////////
                          UNIT WEIGHT TOTALS
    //////////////////////////////////////////////////////////////*/

    /// @dev A fully built, long-held unit carries 6.75x a bare one-bay unit on fresh base tier.
    function test_fullyBuiltUnitIs6point75x() public {
        uint256 built = _unitWithBays(alice, 3);
        vm.startPrank(alice);
        doc.buyAndSeatAugment(built, 0, T3_NVDA);
        doc.buyAndSeatAugment(built, 1, T3_MSFT);
        doc.buyAndSeatAugment(built, 2, T3_NVDA);
        vm.stopPrank();

        uint256 bare = _mintUnit(bob);
        vm.prank(bob);
        doc.buyAndSeatAugment(bare, 0, T1_SPY);

        runner.advanceCycles(9);

        assertEq(doc.unitWeight(built), 6.75e18, "three tier-3 bays at full tenure");

        // The spec's 6.75x is measured against a bare one-bay unit running a FRESH base Augment,
        // i.e. the 1.0x floor — not against a bare unit that has also been left to tenure.
        uint256 freshBareReference = Weights.bayWeight(1, 0, 0);
        assertEq(freshBareReference, 1.0e18);
        assertEq(doc.unitWeight(built), (675 * freshBareReference) / 100, "6.75x the floor");

        // Left alone for the same nine cycles the bare unit also reaches its own ceiling, so the
        // live gap between two units that both sat still is 4.5x, not 6.75x. Capacity and tier
        // account for that difference; tenure alone does not.
        assertEq(doc.unitWeight(bare), 1.5e18);
        assertEq((doc.unitWeight(built) * 1e18) / doc.unitWeight(bare), 4.5e18);
    }

    function test_emptyUnitHasZeroWeight() public {
        uint256 unit = _mintUnit(alice);
        assertEq(doc.unitWeight(unit), 0);
        assertEq(doc.unitEligibleWeight(unit), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_augmentsMintOnlyByRipperdoc() public {
        vm.prank(alice);
        vm.expectRevert(Augments.NotRipperdoc.selector);
        augments.mint(alice, T1_SPY, 1);
    }

    function test_modulesMintOnlyByRipperdoc() public {
        vm.prank(alice);
        vm.expectRevert(ExpansionModules.NotRipperdoc.selector);
        modules.mint(alice, 1);
    }

    function test_runnerBayStateOnlyByRipperdoc() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        vm.expectRevert(StockRunner.NotRipperdoc.selector);
        runner.setBay(unit, 0, T1_SPY, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        RIPPERDOC RE-WIRING
    //////////////////////////////////////////////////////////////*/

    /// @dev On mainnet the item contracts are strictly set-once: the Ripperdoc address can mint
    ///      Augments and Modules freely, so it must not be re-pointable in production.
    function test_itemContracts_areStrictlySetOnceOnMainnet() public {
        Augments mainnetAugments = new Augments("ipfs://x/{id}.json", false);
        ExpansionModules mainnetModules = new ExpansionModules("ipfs://y/{id}.json", false);

        mainnetAugments.setRipperdoc(address(doc));
        mainnetModules.setRipperdoc(address(doc));

        vm.expectRevert(Augments.RipperdocAlreadySet.selector);
        mainnetAugments.setRipperdoc(makeAddr("other"));

        vm.expectRevert(ExpansionModules.RipperdocAlreadySet.selector);
        mainnetModules.setRipperdoc(makeAddr("other"));
    }

    /// @dev On testnet they may be re-pointed, so a later phase can replace the Ripperdoc without
    ///      redeploying the catalog or the StockRunner and re-minting every test unit.
    function test_itemContracts_areRepointableOnTestnet() public {
        address next = makeAddr("ripperdocV2");
        augments.setRipperdoc(next);
        modules.setRipperdoc(next);
        runner.setRipperdoc(next);

        assertEq(augments.ripperdoc(), next);
        assertEq(modules.ripperdoc(), next);
        assertEq(runner.ripperdoc(), next);

        // And the old Ripperdoc immediately loses its authority: alice still owns the unit, but the
        // StockRunner no longer recognises `doc` as the Ripperdoc, so the bay write is rejected.
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        vm.expectRevert(StockRunner.NotRipperdoc.selector);
        doc.buyAndSeatAugment(unit, 0, T1_SPY);

        // Nor can it still mint items.
        vm.prank(alice);
        vm.expectRevert(Augments.NotRipperdoc.selector);
        doc.buyAugment(T1_SPY, 1);
    }

    /// @dev Re-wiring must survive existing state: units keep their bays, tenure and seating when
    ///      the Ripperdoc is swapped, because all of that lives on the StockRunner.
    function test_rewiring_preservesExistingUnitState() public {
        uint256 unit = _mintUnit(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unit, 0, T3_NVDA);
        runner.advanceCycles(9);

        uint256 weightBefore = doc.bayWeight(unit, 0);
        assertEq(weightBefore, 2.25e18);

        runner.setRipperdoc(makeAddr("ripperdocV2"));

        assertEq(runner.getBay(unit, 0).augmentId, T3_NVDA, "seating survives re-wiring");
        assertEq(runner.tenureCycles(unit, 0), 8, "tenure survives re-wiring");
        assertEq(doc.bayWeight(unit, 0), weightBefore, "weight is unchanged");
    }
}
