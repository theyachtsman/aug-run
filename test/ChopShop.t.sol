// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {ChopShop} from "../src/chopshop/ChopShop.sol";
import {MockUSDG} from "../src/chopshop/MockUSDG.sol";
import {CommitRevealRandomness} from "../src/chopshop/CommitRevealRandomness.sol";
import {MockRandomness} from "./helpers/MockRandomness.sol";
import {MockArbSys} from "./helpers/MockArbSys.sol";
import {Augments} from "../src/items/Augments.sol";

contract ChopShopTest is Test {
    MockUSDG internal usdg;
    AUG internal aug;
    RevenueSplitter internal splitter;
    MockRandomness internal rng;
    ChopShop internal shop;
    Augments internal augments;

    address internal scrapper = makeAddr("depositor");
    address internal roller = makeAddr("roller");
    address internal keeper = makeAddr("keeper");

    uint256 constant V = 1000e6; // 1,000 USDG declared value
    uint256 constant AUGMENT_ID = 1;

    function setUp() public {
        vm.warp(1786147200);

        usdg = new MockUSDG();
        aug = new AUG(address(this), address(this), address(this), true);
        splitter = new RevenueSplitter();
        rng = new MockRandomness();
        shop = new ChopShop(address(usdg), address(aug), address(splitter), address(rng));

        augments = new Augments("uri", true);
        augments.setRipperdoc(address(this));
        augments.addAugment("SPY", 1);

        // Fund the shop with $AUG so Convert payouts can settle.
        aug.transfer(address(shop), 1_000_000e18);

        usdg.mint(scrapper, 1_000_000e6);
        usdg.mint(roller, 1_000_000e6);
        augments.mint(scrapper, AUGMENT_ID, 10);

        vm.startPrank(scrapper);
        usdg.approve(address(shop), type(uint256).max);
        augments.setApprovalForAll(address(shop), true);
        vm.stopPrank();

        vm.prank(roller);
        usdg.approve(address(shop), type(uint256).max);
    }

    function _list(uint256 backing) internal returns (uint256 id) {
        vm.prank(scrapper);
        id = shop.list(ChopShop.ItemKind.Augment, address(augments), AUGMENT_ID, V, backing);
    }

    /*//////////////////////////////////////////////////////////////
                             THE ODDS CURVE
    //////////////////////////////////////////////////////////////*/

    /// @dev "The less you back it with, the better everyone's odds on a roll."
    function test_lessBackingMeansBetterOdds() public view {
        assertEq(shop.winProbabilityBps(V, 0), 10_000, "no backing => certain win");
        assertEq(shop.winProbabilityBps(V, V), 5000, "backing == value => coin flip");
        assertEq(shop.winProbabilityBps(V, 3 * V), 2500, "3x backing => 25%");
        assertEq(shop.winProbabilityBps(V, 9 * V), 1000, "9x backing => 10%");
    }

    function test_oddsAreMonotonicallyDecreasingInBacking() public view {
        uint256 prev = 10_001;
        for (uint256 b = 0; b <= 10 * V; b += V / 2) {
            uint256 p = shop.winProbabilityBps(V, b);
            assertLt(p, prev, "must strictly decrease");
            prev = p;
        }
    }

    /// @dev A backing floor stops a heavily-built unit being listed at trivial backing.
    function test_backingFloorIsEnforced() public {
        uint256 floor = (V * 2500) / 10_000;
        vm.prank(scrapper);
        vm.expectRevert(abi.encodeWithSelector(ChopShop.BackingBelowFloor.selector, floor - 1, floor));
        shop.list(ChopShop.ItemKind.Augment, address(augments), AUGMENT_ID, V, floor - 1);

        vm.prank(scrapper);
        shop.list(ChopShop.ItemKind.Augment, address(augments), AUGMENT_ID, V, floor);
    }

    /// @dev Entry costs the expected value of the roll plus 30%.
    function test_entryIsExpectedValuePlusThirtyPercent() public view {
        uint256 backing = V; // p = 50%
        uint256 expectedValue = V / 2;
        assertEq(shop.entryCost(V, backing), (expectedValue * 13_000) / 10_000);
        assertEq(shop.entryCost(V, backing), 650e6, "EV 500 + 30%");
    }

    /*//////////////////////////////////////////////////////////////
                              LISTING
    //////////////////////////////////////////////////////////////*/

    function test_list_escrowsItemAndBacking() public {
        uint256 id = _list(V);
        assertEq(augments.balanceOf(address(shop), AUGMENT_ID), 1, "item escrowed");
        assertEq(usdg.balanceOf(address(shop)), V, "backing escrowed");
        (address depositor,,,, uint256 declared, uint256 backing,,,) = shop.listings(id);
        assertEq(depositor, scrapper);
        assertEq(declared, V);
        assertEq(backing, V);
    }

    /// @dev The table rotates daily.
    function test_withdrawOnlyAfterTheTableRotates() public {
        uint256 id = _list(V);
        vm.prank(scrapper);
        vm.expectRevert(ChopShop.ListingStillOpen.selector);
        shop.withdrawListing(id);

        vm.warp(block.timestamp + 1 days);
        vm.prank(scrapper);
        shop.withdrawListing(id);
        assertEq(augments.balanceOf(scrapper, AUGMENT_ID), 10, "item back");
        assertEq(usdg.balanceOf(scrapper), 1_000_000e6, "backing back");
    }

    function test_cannotRollAnExpiredListing() public {
        uint256 id = _list(V);
        vm.warp(block.timestamp + 1 days);
        vm.prank(roller);
        vm.expectRevert(ChopShop.ListingClosed.selector);
        shop.roll(id);
    }

    /*//////////////////////////////////////////////////////////////
                               THE ROLL
    //////////////////////////////////////////////////////////////*/

    function test_roll_chargesEntryAndCommits() public {
        uint256 id = _list(V);
        uint256 entry = shop.listingEntryCost(id);
        uint256 before = usdg.balanceOf(roller);

        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        assertEq(before - usdg.balanceOf(roller), entry, "paid the entry");
        (,, uint256 paid,,, ChopShop.RollState state) = shop.rolls(rollId);
        assertEq(paid, entry);
        assertEq(uint256(state), uint256(ChopShop.RollState.Committed));
    }

    /// @dev Two people must not be able to play for the same item at once.
    function test_listingClosesWhileARollIsOutstanding() public {
        uint256 id = _list(V);
        vm.prank(roller);
        shop.roll(id);

        vm.prank(roller);
        vm.expectRevert(ChopShop.ListingClosed.selector);
        shop.roll(id);
    }

    function test_cannotResolveBeforeReady() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        rng.setReady(false);
        vm.expectRevert(ChopShop.RollNotReady.selector);
        shop.resolve(rollId);
    }

    /// @dev Resolution is permissionless so a keeper can drive it inside the tight window.
    function test_resolve_isPermissionless() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        rng.setValue(1); // below threshold => win
        vm.prank(keeper);
        bool won = shop.resolve(rollId);
        assertTrue(won);
    }

    function test_resolve_winAndLossFollowTheThreshold() public {
        uint256 id = _list(V); // p = 5000 bps
        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        rng.setValue(4999); // just under
        shop.resolve(rollId);
        (,,,,, ChopShop.RollState state) = shop.rolls(rollId);
        assertEq(uint256(state), uint256(ChopShop.RollState.Won));

        uint256 id2 = _list(V);
        vm.prank(roller);
        uint256 rollId2 = shop.roll(id2);
        rng.setValue(5000); // exactly at threshold => loss
        shop.resolve(rollId2);
        (,,,,, ChopShop.RollState state2) = shop.rolls(rollId2);
        assertEq(uint256(state2), uint256(ChopShop.RollState.Lost));
    }

    /// @dev 10% of every entry payment is taken as revenue, win or lose.
    function test_tenPercentOfEntryIsRevenue() public {
        uint256 id = _list(V);
        uint256 entry = shop.listingEntryCost(id);

        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        rng.setValue(1);
        shop.resolve(rollId);

        uint256 revenue = (entry * 1000) / 10_000;
        assertEq(usdg.balanceOf(address(splitter)), revenue);
        // `deposit` splits on receipt, so the buckets are already populated — no sync needed.
        assertEq(splitter.accrued(address(usdg), RevenueSplitter.Bucket.Drop), (revenue * 6000) / 10_000);
        assertEq(
            splitter.accrued(address(usdg), RevenueSplitter.Bucket.Stakers), (revenue * 2000) / 10_000
        );
    }

    function test_loss_depositorKeepsItemAndTakesTheEntry() public {
        uint256 id = _list(V);
        uint256 entry = shop.listingEntryCost(id);
        uint256 before = usdg.balanceOf(scrapper);

        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        rng.setValue(9999); // loss
        shop.resolve(rollId);

        uint256 revenue = (entry * 1000) / 10_000;
        assertEq(usdg.balanceOf(scrapper) - before, entry - revenue, "depositor takes the entry");
        assertEq(augments.balanceOf(address(shop), AUGMENT_ID), 1, "item stays on the table");
    }

    /// @dev A losing roll puts the item back on the table for the rest of the day.
    function test_lossReopensTheListing() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        rng.setValue(9999);
        shop.resolve(rollId);

        vm.prank(roller);
        shop.roll(id); // rollable again
    }

    /*//////////////////////////////////////////////////////////////
                             PAYOUT MODES
    //////////////////////////////////////////////////////////////*/

    function _winningRoll() internal returns (uint256 rollId, uint256 listingId) {
        listingId = _list(V);
        vm.prank(roller);
        rollId = shop.roll(listingId);
        rng.setValue(1);
        shop.resolve(rollId);
    }

    function test_payout_takeItem() public {
        (uint256 rollId,) = _winningRoll();
        uint256 depositorBefore = usdg.balanceOf(scrapper);

        vm.prank(roller);
        shop.claim(rollId, ChopShop.Payout.TakeItem);

        assertEq(augments.balanceOf(roller, AUGMENT_ID), 1, "roller takes the item");
        assertEq(usdg.balanceOf(scrapper) - depositorBefore, V, "backing goes home");
    }

    function test_payout_cashOutPaysEightyFivePercentOfBacking() public {
        (uint256 rollId,) = _winningRoll();
        uint256 before = usdg.balanceOf(roller);
        uint256 splitterBefore = usdg.balanceOf(address(splitter));

        vm.prank(roller);
        uint256 amount = shop.claim(rollId, ChopShop.Payout.CashOut);

        assertEq(amount, (V * 8500) / 10_000);
        assertEq(usdg.balanceOf(roller) - before, amount);
        assertEq(usdg.balanceOf(address(splitter)) - splitterBefore, V - amount, "remainder is revenue");
        assertEq(augments.balanceOf(scrapper, AUGMENT_ID), 10, "depositor keeps the item");
    }

    function test_payout_convertPaysNinetyPercentInAug() public {
        (uint256 rollId,) = _winningRoll();
        uint256 before = aug.balanceOf(roller);

        vm.prank(roller);
        uint256 amount = shop.claim(rollId, ChopShop.Payout.Convert);

        // 90% of 1,000 USDG at 1:1 => 900, scaled 6dp -> 18dp by the rate.
        assertEq(amount, ((V * 9000) / 10_000) * 1e18 / 1e18);
        assertEq(aug.balanceOf(roller) - before, amount);
        assertEq(augments.balanceOf(scrapper, AUGMENT_ID), 10, "depositor keeps the item");
    }

    function test_cannotClaimALoss() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        rng.setValue(9999);
        shop.resolve(rollId);

        vm.prank(roller);
        vm.expectRevert(ChopShop.RollNotWon.selector);
        shop.claim(rollId, ChopShop.Payout.TakeItem);
    }

    function test_cannotClaimTwice() public {
        (uint256 rollId,) = _winningRoll();
        vm.prank(roller);
        shop.claim(rollId, ChopShop.Payout.TakeItem);
        vm.prank(roller);
        vm.expectRevert(ChopShop.RollNotWon.selector);
        shop.claim(rollId, ChopShop.Payout.CashOut);
    }

    /*//////////////////////////////////////////////////////////////
                          EXPIRY / REFUND
    //////////////////////////////////////////////////////////////*/

    /// @dev The blockhash window is ~25 seconds on this chain, so a missed resolve is a real case.
    ///      It must refund rather than strand the entry.
    function test_expiredRollRefundsTheEntry() public {
        uint256 id = _list(V);
        uint256 entry = shop.listingEntryCost(id);
        uint256 before = usdg.balanceOf(roller);

        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        assertEq(before - usdg.balanceOf(roller), entry);

        rng.setExpired(true);
        shop.refundExpiredRoll(rollId);

        assertEq(usdg.balanceOf(roller), before, "entry returned in full");
    }

    function test_cannotRefundALiveRoll() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        vm.expectRevert(ChopShop.NotExpired.selector);
        shop.refundExpiredRoll(rollId);
    }

    function test_refundReopensTheListing() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);
        rng.setExpired(true);
        shop.refundExpiredRoll(rollId);

        rng.setExpired(false);
        rng.setReady(true);
        vm.prank(roller);
        shop.roll(id);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @dev The VRF migration path: swap the source, Chop Shop unchanged.
    function test_randomnessSourceIsSwappable() public {
        MockRandomness other = new MockRandomness();
        shop.setRandomnessSource(address(other));
        assertEq(address(shop.randomnessSource()), address(other));
    }

    /// @dev Swapping the source must never strand a roll that is already in flight. The first
    ///      live swap did exactly that: the new source knew nothing of the old request id, so the
    ///      roll could neither resolve nor expire and the listing stayed closed behind it.
    function test_swappingSourceDoesNotStrandAnInFlightRoll() public {
        uint256 id = _list(V);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        shop.setRandomnessSource(address(new MockRandomness()));

        rng.setValue(1); // the ORIGINAL source still governs this roll
        bool won = shop.resolve(rollId);
        assertTrue(won, "resolves against the source it committed to");
    }

    function test_swappingSourceStillAllowsRefund() public {
        uint256 id = _list(V);
        uint256 before = usdg.balanceOf(roller);
        vm.prank(roller);
        uint256 rollId = shop.roll(id);

        shop.setRandomnessSource(address(new MockRandomness()));

        rng.setExpired(true);
        shop.refundExpiredRoll(rollId);
        assertEq(usdg.balanceOf(roller), before, "refundable despite the swap");
    }

    function test_setRandomnessSource_onlyOwner() public {
        vm.prank(roller);
        vm.expectRevert();
        shop.setRandomnessSource(address(rng));
    }
}

/// @notice The real commit-reveal source, exercised on its own.
contract CommitRevealRandomnessTest is Test {
    CommitRevealRandomness internal rng;

    function setUp() public {
        rng = new CommitRevealRandomness();
        vm.roll(1000);
    }

    /// @dev The whole point: the value cannot be read in the transaction that requests it.
    function test_notReadyInTheRequestingBlock() public {
        uint256 id = rng.requestRandomness(keccak256("seed"));
        assertFalse(rng.isReady(id));
        vm.expectRevert(CommitRevealRandomness.NotReady.selector);
        rng.randomness(id);
    }

    function test_notReadyUntilPastTheTargetBlock() public {
        uint256 id = rng.requestRandomness(keccak256("seed"));
        vm.roll(block.number + 1);
        assertFalse(rng.isReady(id), "target not yet mined");
        vm.roll(block.number + 2);
        assertTrue(rng.isReady(id));
    }

    function test_readyThenResolvable() public {
        uint256 id = rng.requestRandomness(keccak256("seed"));
        vm.roll(block.number + 3);
        assertTrue(rng.isReady(id));
        assertGt(rng.randomness(id), 0);
    }

    function test_differentSeedsGiveDifferentValues() public {
        uint256 a = rng.requestRandomness(keccak256("a"));
        uint256 b = rng.requestRandomness(keccak256("b"));
        vm.roll(block.number + 3);
        assertTrue(rng.randomness(a) != rng.randomness(b));
    }

    function test_expiresAfterTheWindow() public {
        uint256 id = rng.requestRandomness(keccak256("seed"));
        vm.roll(block.number + 3);
        assertFalse(rng.isExpired(id));

        vm.roll(block.number + rng.REVEAL_WINDOW() + 5);
        assertTrue(rng.isExpired(id), "window closed");
        assertFalse(rng.isReady(id));
    }

    /// @dev The Arbitrum path. `block.number` there is the L1 number while hashes are indexed by
    ///      L2 number; conflating them produced a target that could never be hashed, and it reached a
    ///      live deployment because the plain-EVM fallback hides the difference. This etches an
    ///      ArbSys whose block number is deliberately offset so the two can never be confused.
    function test_worksOnArbitrumWhereBlockNumberIsL1() public {
        MockArbSys arbSys = new MockArbSys();
        vm.etch(0x0000000000000000000000000000000000000064, address(arbSys).code);

        CommitRevealRandomness arbRng = new CommitRevealRandomness();
        uint256 id = arbRng.requestRandomness(keccak256("seed"));

        // Target must be recorded against the L2 clock, not the L1 one.
        (,, uint256 targetBlock,) = arbRng.requests(id);
        assertGt(targetBlock, 88_000_000, "target must be an L2 block number");

        assertFalse(arbRng.isReady(id));
        vm.roll(block.number + 3);
        assertTrue(arbRng.isReady(id), "must resolve on the Arbitrum path");
        assertGt(arbRng.randomness(id), 0);

        vm.etch(0x0000000000000000000000000000000000000064, "");
    }

    function test_valueIsStableOnceReady() public {
        uint256 id = rng.requestRandomness(keccak256("seed"));
        vm.roll(block.number + 3);
        uint256 first = rng.randomness(id);
        vm.roll(block.number + 5);
        assertEq(rng.randomness(id), first, "pinned to the target block");
    }
}
