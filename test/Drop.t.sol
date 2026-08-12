// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {RUN} from "../src/tokens/RUN.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";
import {Augments} from "../src/items/Augments.sol";
import {ExpansionModules} from "../src/items/ExpansionModules.sol";
import {Ripperdoc} from "../src/items/Ripperdoc.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {Drop} from "../src/drop/Drop.sol";
import {MockRwaVenue, MockRwaToken} from "../src/drop/MockRwaVenue.sol";
import {ERC6551RegistryFixture} from "./helpers/ERC6551RegistryFixture.sol";

contract DropTest is Test {
    RUN internal runToken;
    AUG internal aug;
    StockRunner internal runner;
    Augments internal augments;
    ExpansionModules internal modules;
    Ripperdoc internal doc;
    RevenueSplitter internal splitter;
    MockRwaVenue internal venue;
    Drop internal drop;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant T1_SPY = 1;
    uint256 constant T3_NVDA = 2;

    function setUp() public {
        vm.warp(1786147200);

        address registry = ERC6551RegistryFixture.install();
        ERC6551Account impl = new ERC6551Account();

        runToken = new RUN(address(this), true);
        aug = new AUG(address(this), address(this), address(this), true);
        splitter = new RevenueSplitter();

        runner = new StockRunner(address(runToken), registry, address(impl), address(this), true);
        augments = new Augments("uri", true);
        modules = new ExpansionModules("uri", true);
        doc = new Ripperdoc(address(aug), address(runner), address(augments), address(modules), address(this));
        runner.setRipperdoc(address(doc));
        runner.openMinting();
        augments.setRipperdoc(address(doc));
        modules.setRipperdoc(address(doc));
        augments.addAugment("SPY", 1);
        augments.addAugment("NVDA", 3);

        venue = new MockRwaVenue();
        venue.listTicker(keccak256("SPY"), "Mock SPY", "mSPY", 1e18);
        venue.listTicker(keccak256("NVDA"), "Mock NVDA", "mNVDA", 2e18);

        drop = new Drop(
            address(runToken), address(runner), address(doc), address(augments),
            address(splitter), address(venue)
        );
        splitter.setRecipient(RevenueSplitter.Bucket.Drop, address(drop));

        _fund(alice);
        _fund(bob);
    }

    function _fund(address who) internal {
        runToken.transfer(who, 20_000_000e18);
        aug.transfer(who, 1_000_000e18);
        vm.startPrank(who);
        runToken.approve(address(runner), type(uint256).max);
        aug.approve(address(doc), type(uint256).max);
        vm.stopPrank();
    }

    function _unitWithBay(address who, uint256 augmentId) internal returns (uint256 id) {
        vm.startPrank(who);
        id = runner.mint();
        doc.buyAndSeatAugment(id, 0, augmentId);
        vm.stopPrank();
    }

    /// @dev Revenue reaches the Drop bucket the way Black Market fees do.
    function _deliverRevenue(uint256 amount) internal {
        runToken.transfer(address(splitter), amount);
        splitter.sync(address(runToken));
    }

    function _runDrop() internal returns (uint256 dropId) {
        dropId = drop.openDrop();
        while (!drop.accumulate(dropId, 50)) {}
        drop.finalize(dropId);
    }

    /*//////////////////////////////////////////////////////////////
                             POOL & OPENING
    //////////////////////////////////////////////////////////////*/

    function test_openDrop_pullsTheSixtyPercentBucket() public {
        _unitWithBay(alice, T1_SPY);
        _deliverRevenue(1000e18);

        uint256 dropId = drop.openDrop();
        (, uint256 pool,,,,,) = drop.rounds(dropId);
        assertEq(pool, 600e18, "60% of revenue funds the Drop");
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 0, "bucket drained");
    }

    function test_openDrop_revertsWithNothingToDrop() public {
        vm.expectRevert(Drop.NothingToDrop.selector);
        drop.openDrop();
    }

    /// @dev "The pool is whatever the protocol actually earned. Small revenue means small Drops."
    function test_tinyRevenueStillProducesAValidDrop() public {
        _unitWithBay(alice, T1_SPY);
        runner.advanceCycles(1);
        _deliverRevenue(1000);

        uint256 dropId = _runDrop();
        (,, uint256 totalWeight,,,,) = drop.rounds(dropId);
        assertGt(totalWeight, 0, "still allocates");
    }

    /*//////////////////////////////////////////////////////////////
                        WEIGHT-BASED ALLOCATION
    //////////////////////////////////////////////////////////////*/

    /// @dev The pool splits by weight, not evenly and not per unit.
    function test_allocationIsByWeightNotPerUnit() public {
        uint256 a = _unitWithBay(alice, T1_SPY); // tier 1 => 1.0x
        uint256 b = _unitWithBay(bob, T3_NVDA); // tier 3 => 1.5x
        runner.advanceCycles(1); // both become eligible

        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        // Weights 1.0 and 1.5 => ticker slices 40% / 60% of the pool.
        assertEq(drop.tickerWeight(dropId, T1_SPY), 1e18);
        assertEq(drop.tickerWeight(dropId, T3_NVDA), 1.5e18);
        (,, uint256 totalWeight,,,,) = drop.rounds(dropId);
        assertEq(totalWeight, 2.5e18);

        (, uint256[3] memory aAmt) = drop.claimable(dropId, a);
        (, uint256[3] memory bAmt) = drop.claimable(dropId, b);
        assertGt(bAmt[0], aAmt[0], "the heavier bay earns more");
    }

    /// @dev Seasoning: an Augment seated mid-cycle earns nothing until the next full one.
    function test_bayIsIneligibleTheCycleItWasSeated() public {
        _unitWithBay(alice, T1_SPY); // seated this cycle
        _deliverRevenue(1000e18);

        uint256 dropId = _runDrop();
        (,, uint256 totalWeight,,,,) = drop.rounds(dropId);
        assertEq(totalWeight, 0, "no eligible bays yet");
    }

    function test_emptyBaysEarnNothing() public {
        vm.prank(alice);
        runner.mint(); // no Augment seated
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);

        uint256 dropId = _runDrop();
        (,, uint256 totalWeight,,,,) = drop.rounds(dropId);
        assertEq(totalWeight, 0);
    }

    /// @dev Tenure raises a bay's share without the operator doing anything.
    function test_tenureIncreasesShare() public {
        uint256 a = _unitWithBay(alice, T1_SPY);
        uint256 b = _unitWithBay(bob, T1_SPY);
        runner.advanceCycles(1);

        _deliverRevenue(1000e18);
        uint256 d1 = _runDrop();
        (, uint256[3] memory early) = drop.claimable(d1, a);

        // Let both tenure up, then run another Drop.
        runner.advanceCycles(9);
        _deliverRevenue(1000e18);
        uint256 d2 = _runDrop();
        (, uint256[3] memory late) = drop.claimable(d2, a);

        assertGt(drop.tickerWeight(d2, T1_SPY), drop.tickerWeight(d1, T1_SPY), "weights grew");
        assertEq(early.length, late.length);
        assertEq(b, b);
    }

    /*//////////////////////////////////////////////////////////////
                       BATCHED ACCUMULATION
    //////////////////////////////////////////////////////////////*/

    function test_accumulationIsBatchedAndResumable() public {
        for (uint256 i = 0; i < 5; i++) _unitWithBay(alice, T1_SPY);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);

        uint256 dropId = drop.openDrop();
        assertFalse(drop.accumulate(dropId, 2), "partial");
        (uint256 cursor,) = drop.accumulationProgress(dropId);
        assertEq(cursor, 3);

        assertFalse(drop.accumulate(dropId, 2));
        assertTrue(drop.accumulate(dropId, 2), "completes");

        (,, uint256 totalWeight,,,,) = drop.rounds(dropId);
        assertEq(totalWeight, 5e18, "five 1.0x bays");
    }

    function test_cannotFinalizeBeforeAccumulationCompletes() public {
        for (uint256 i = 0; i < 3; i++) _unitWithBay(alice, T1_SPY);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);

        uint256 dropId = drop.openDrop();
        drop.accumulate(dropId, 1);
        vm.expectRevert(Drop.AccumulationIncomplete.selector);
        drop.finalize(dropId);
    }

    /*//////////////////////////////////////////////////////////////
                        AGGREGATE PURCHASING
    //////////////////////////////////////////////////////////////*/

    /// @dev One purchase per ticker, however many bays run it.
    function test_onePurchasePerTickerRegardlessOfBayCount() public {
        for (uint256 i = 0; i < 4; i++) _unitWithBay(alice, T1_SPY);
        _unitWithBay(bob, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);

        uint256 dropId = drop.openDrop();
        while (!drop.accumulate(dropId, 50)) {}

        vm.recordLogs();
        drop.finalize(dropId);

        // Two tickers seated => exactly two purchases, not five.
        assertGt(drop.rwaBought(dropId, T1_SPY), 0);
        assertGt(drop.rwaBought(dropId, T3_NVDA), 0);
        assertTrue(drop.rwaAsset(dropId, T1_SPY) != drop.rwaAsset(dropId, T3_NVDA));
    }

    /// @dev An unavailable ticker is skipped and its share rolls into the next pool. No substitute.
    function test_unavailableTickerIsSkippedAndRollsForward() public {
        _unitWithBay(alice, T1_SPY);
        _unitWithBay(bob, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);

        venue.setAvailable(keccak256("NVDA"), false); // delisted

        uint256 dropId = _runDrop();
        assertEq(drop.rwaBought(dropId, T3_NVDA), 0, "nothing bought for the dead ticker");
        assertGt(drop.rwaBought(dropId, T1_SPY), 0, "the live one still bought");
        assertGt(drop.skippedPool(dropId), 0, "its share rolled forward");

        // The rolled amount lands in the next Drop's pool.
        uint256 rolled = drop.skippedPool(dropId);
        _deliverRevenue(1000e18);
        uint256 d2 = drop.openDrop();
        (, uint256 pool2,,,,,) = drop.rounds(d2);
        assertEq(pool2, 600e18 + rolled, "carried into the next pool");
    }

    /*//////////////////////////////////////////////////////////////
                           PULL-BASED CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @dev Assets land in the unit's ERC-6551 wallet, not the operator's own address.
    function test_claimDeliversIntoTheTokenBoundAccount() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        (address[3] memory assets, uint256[3] memory amounts) = drop.claimable(dropId, id);
        assertGt(amounts[0], 0);

        address tba = runner.tokenBoundAccount(id);
        vm.prank(alice);
        drop.claim(dropId, id);

        assertEq(IERC20(assets[0]).balanceOf(tba), amounts[0], "delivered to the unit's wallet");
        assertEq(IERC20(assets[0]).balanceOf(alice), 0, "not to the operator");
    }

    function test_claim_onlyUnitOwner() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        vm.prank(bob);
        vm.expectRevert(Drop.NotUnitOwner.selector);
        drop.claim(dropId, id);
    }

    function test_cannotClaimTwice() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        vm.startPrank(alice);
        drop.claim(dropId, id);
        vm.expectRevert(Drop.AlreadyClaimed.selector);
        drop.claim(dropId, id);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          THE CLAIM WINDOW
    //////////////////////////////////////////////////////////////*/

    /// @dev Claimable until one hour before the next Drop — just under seven days.
    function test_claimWindowClosesAnHourBeforeTheNextDrop() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        (,,,,, uint256 deadline,) = drop.rounds(dropId);
        assertEq(deadline, runner.nextCycleBoundary() - 1 hours);

        vm.warp(deadline + 1);
        vm.prank(alice);
        vm.expectRevert(Drop.ClaimWindowClosed.selector);
        drop.claim(dropId, id);
    }

    /// @dev "A unit whose operator doesn't show up funds the operators who did."
    function test_unclaimedIsSoldAndFundsTheBuyback() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        (,,,,, uint256 deadline,) = drop.rounds(dropId);
        vm.warp(deadline + 1);

        assertEq(drop.buybackPool(), 0);
        drop.sweepUnclaimed(dropId, 1, id);
        assertGt(drop.buybackPool(), 0, "unclaimed value became buyback fuel");
    }

    function test_cannotSweepWhileTheWindowIsOpen() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        vm.expectRevert(Drop.ClaimWindowOpen.selector);
        drop.sweepUnclaimed(dropId, 1, id);
    }

    function test_sweepSkipsWhatWasAlreadyClaimed() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        vm.prank(alice);
        drop.claim(dropId, id);

        (,,,,, uint256 deadline,) = drop.rounds(dropId);
        vm.warp(deadline + 1);
        drop.sweepUnclaimed(dropId, 1, id);
        assertEq(drop.buybackPool(), 0, "nothing left to sell");
    }

    function test_executeBuyback() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000e18);
        uint256 dropId = _runDrop();

        (,,,,, uint256 deadline,) = drop.rounds(dropId);
        vm.warp(deadline + 1);
        drop.sweepUnclaimed(dropId, 1, id);

        uint256 amount = drop.buybackPool();
        address sink = makeAddr("blackMarketPool");
        drop.executeBuyback(sink);

        assertEq(runToken.balanceOf(sink), amount, "proceeds deepen the $RUN market");
        assertEq(drop.buybackPool(), 0);
        assertEq(drop.totalBoughtBack(), amount);
    }

    /*//////////////////////////////////////////////////////////////
                             THE DUST FLOOR
    //////////////////////////////////////////////////////////////*/

    /// @dev Measured against live gas, not a fixed figure, so it tracks conditions.
    function test_dustFloorTracksLiveGasPrice() public {
        vm.txGasPrice(1 gwei);
        assertEq(drop.dustFloor(), 1 gwei * 150_000);
        vm.txGasPrice(0.01 gwei);
        assertEq(drop.dustFloor(), 0.01 gwei * 150_000, "cheap gas => a tiny floor");
    }

    /// @dev Below the floor nothing is delivered — it is held and compounds until worth collecting.
    function test_belowFloorAmountsAreHeldNotDelivered() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000); // a trivial pool
        uint256 dropId = _runDrop();

        (address[3] memory assets, uint256[3] memory amounts) = drop.claimable(dropId, id);
        vm.txGasPrice(1000 gwei); // force everything under the floor

        address tba = runner.tokenBoundAccount(id);
        vm.prank(alice);
        drop.claim(dropId, id);

        assertEq(IERC20(assets[0]).balanceOf(tba), 0, "not delivered");
        assertEq(drop.dustCredit(id, assets[0]), amounts[0], "held instead");
    }

    function test_dustCanBeClaimedOnceWorthIt() public {
        uint256 id = _unitWithBay(alice, T3_NVDA);
        runner.advanceCycles(1);
        _deliverRevenue(1000);
        uint256 dropId = _runDrop();

        (address[3] memory assets,) = drop.claimable(dropId, id);
        vm.txGasPrice(1000 gwei);
        vm.prank(alice);
        drop.claim(dropId, id);

        uint256 held = drop.dustCredit(id, assets[0]);
        assertGt(held, 0);

        vm.prank(alice);
        drop.claimDust(id, assets[0]);
        assertEq(IERC20(assets[0]).balanceOf(runner.tokenBoundAccount(id)), held);
        assertEq(drop.dustCredit(id, assets[0]), 0);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function test_venueIsSwappable() public {
        MockRwaVenue other = new MockRwaVenue();
        drop.setVenue(address(other));
        assertEq(address(drop.venue()), address(other));
    }

    function test_setVenue_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        drop.setVenue(address(venue));
    }
}
