// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RUN} from "../src/tokens/RUN.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {Terminal} from "../src/terminal/Terminal.sol";
import {MockLpToken} from "../src/terminal/MockLpToken.sol";

contract TerminalTest is Test {
    RUN internal runToken;
    AUG internal aug;
    RevenueSplitter internal splitter;
    Terminal internal terminal;
    MockLpToken internal lp;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    uint256 constant WEEK = 7 days;

    function setUp() public {
        vm.warp(1786147200);

        runToken = new RUN(address(this), true);
        aug = new AUG(address(this), address(this), address(this), true);
        splitter = new RevenueSplitter();
        terminal = new Terminal(address(aug), address(runToken), address(splitter));
        lp = new MockLpToken();

        terminal.setLpToken(address(lp));
        splitter.setRecipient(RevenueSplitter.Bucket.Stakers, address(terminal));
        splitter.setRecipient(RevenueSplitter.Bucket.Lps, address(terminal));

        _fund(alice);
        _fund(bob);
        _fund(carol);
    }

    function _fund(address who) internal {
        aug.transfer(who, 1_000_000e18);
        lp.mint(who, 1_000_000e18);
        vm.startPrank(who);
        aug.approve(address(terminal), type(uint256).max);
        lp.approve(address(terminal), type(uint256).max);
        vm.stopPrank();
    }

    /// @dev Put revenue into the splitter the way the Black Market does, then push it to the Terminal.
    function _deliverRevenue(uint256 amount) internal {
        runToken.transfer(address(splitter), amount);
        splitter.sync(address(runToken));
        terminal.pullRewards();
    }

    /*//////////////////////////////////////////////////////////////
                       STAKE / UNSTAKE / CLAIM ANY TIME
    //////////////////////////////////////////////////////////////*/

    function test_stakeAndWithdrawFreely() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        assertEq(terminal.stakedBalance(alice, false), 100e18);
        assertEq(terminal.totalStaked(false), 100e18);

        vm.prank(alice);
        terminal.withdraw(false, 40e18);
        assertEq(terminal.stakedBalance(alice, false), 60e18);
        assertEq(aug.balanceOf(alice), 1_000_000e18 - 60e18);
    }

    /// @dev No lock, no unbonding: the full stake is withdrawable immediately after staking.
    function test_withdrawImmediatelyAfterStaking() public {
        vm.startPrank(alice);
        terminal.stake(false, 500e18);
        terminal.withdraw(false, 500e18);
        vm.stopPrank();
        assertEq(terminal.stakedBalance(alice, false), 0);
        assertEq(aug.balanceOf(alice), 1_000_000e18);
    }

    function test_withdraw_revertsBeyondStake() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        vm.prank(alice);
        vm.expectRevert(Terminal.InsufficientStake.selector);
        terminal.withdraw(false, 101e18);
    }

    /// @dev Rewards are claimable at any moment, mid-stream, without touching the stake.
    function test_claimMidStreamWithoutUnstaking() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + 1 days);
        uint256 pending = terminal.earned(alice, false);
        assertGt(pending, 0, "accruing already");

        vm.prank(alice);
        terminal.claim(false);

        assertEq(runToken.balanceOf(alice), pending);
        assertEq(terminal.stakedBalance(alice, false), 100e18, "stake untouched");
        assertEq(terminal.earned(alice, false), 0, "claimed out");
    }

    /// @dev Withdrawing the stake must not forfeit rewards already earned.
    function test_withdrawKeepsAccruedRewardsClaimable() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);
        vm.warp(block.timestamp + 3 days);

        uint256 pending = terminal.earned(alice, false);
        assertGt(pending, 0);

        vm.prank(alice);
        terminal.withdraw(false, 100e18);
        assertEq(terminal.earned(alice, false), pending, "still owed after unstaking");

        vm.prank(alice);
        terminal.claim(false);
        assertEq(runToken.balanceOf(alice), pending);
    }

    function test_exit_withdrawsAndClaims() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);
        vm.warp(block.timestamp + WEEK);

        vm.prank(alice);
        terminal.exit(false);

        assertEq(terminal.stakedBalance(alice, false), 0);
        assertEq(aug.balanceOf(alice), 1_000_000e18);
        assertGt(runToken.balanceOf(alice), 0);
    }

    /*//////////////////////////////////////////////////////////////
                             ACCRUAL
    //////////////////////////////////////////////////////////////*/

    function test_soloStakerEarnsTheWholeStream() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18); // 60% of 700 = 420 to stakers

        vm.warp(block.timestamp + WEEK);

        uint256 earned = terminal.earned(alice, false);
        // 20% of 700 = 140 goes to the stakers bucket.
        assertApproxEqAbs(earned, 140e18, 1e12, "solo staker takes the whole stakers stream");
    }

    function test_twoStakersSplitProRata() public {
        vm.prank(alice);
        terminal.stake(false, 300e18);
        vm.prank(bob);
        terminal.stake(false, 100e18);

        _deliverRevenue(700e18);
        vm.warp(block.timestamp + WEEK);

        uint256 a = terminal.earned(alice, false);
        uint256 b = terminal.earned(bob, false);
        assertApproxEqRel(a, b * 3, 1e14, "3:1 stake => 3:1 rewards");
        assertApproxEqAbs(a + b, 140e18, 1e12);
    }

    function test_accrualIsLinearInTime() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + 1 days);
        uint256 afterOneDay = terminal.earned(alice, false);
        vm.warp(block.timestamp + 1 days);
        uint256 afterTwoDays = terminal.earned(alice, false);

        assertApproxEqRel(afterTwoDays, afterOneDay * 2, 1e14, "linear stream");
    }

    function test_rewardsStopAtPeriodEnd() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + WEEK);
        uint256 atEnd = terminal.earned(alice, false);
        vm.warp(block.timestamp + 30 days);
        assertEq(terminal.earned(alice, false), atEnd, "stream is finite");
    }

    /*//////////////////////////////////////////////////////////////
                     JIT SNIPING DOESN'T PAY
    //////////////////////////////////////////////////////////////*/

    /// @dev The reason rewards stream rather than landing in a lump. Someone who stakes immediately
    ///      before revenue is pulled and unstakes immediately after must capture ~nothing.
    function test_jitStakerCapturesAlmostNothing() public {
        vm.prank(alice);
        terminal.stake(false, 100e18); // honest long-term staker

        // Bob front-runs the pull with an equal stake.
        vm.prank(bob);
        terminal.stake(false, 100e18);

        _deliverRevenue(700e18);

        // ...and exits in the same block.
        vm.prank(bob);
        terminal.exit(false);

        assertEq(runToken.balanceOf(bob), 0, "JIT staker captured nothing");

        // Alice, who stayed, collects the stream.
        vm.warp(block.timestamp + WEEK);
        vm.prank(alice);
        terminal.claim(false);
        assertApproxEqAbs(runToken.balanceOf(alice), 140e18, 1e12, "honest staker takes it all");
    }

    /// @dev Staking for only part of the period earns only that part.
    function test_partialPeriodEarnsProportionally() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + WEEK / 2);
        vm.prank(bob);
        terminal.stake(false, 100e18); // joins halfway

        vm.warp(block.timestamp + WEEK / 2);

        uint256 a = terminal.earned(alice, false);
        uint256 b = terminal.earned(bob, false);
        // Alice: full first half + half of second half. Bob: half of second half.
        assertApproxEqRel(a, b * 3, 1e14);
    }

    /*//////////////////////////////////////////////////////////////
                    REVENUE ARRIVING WITH NOBODY STAKED
    //////////////////////////////////////////////////////////////*/

    /// @dev Streaming into an empty pool would burn the revenue irrecoverably. It queues instead.
    function test_revenueQueuesWhenNothingStaked() public {
        assertEq(terminal.totalStaked(false), 0);
        _deliverRevenue(700e18);

        assertEq(terminal.queuedRewards(false), 140e18, "held, not streamed into nothing");
        assertEq(terminal.rewardRate(false), 0, "no stream started");
    }

    function test_queuedRevenueStreamsOnFirstStake() public {
        _deliverRevenue(700e18);
        assertEq(terminal.queuedRewards(false), 140e18);

        vm.prank(alice);
        terminal.stake(false, 100e18);

        assertEq(terminal.queuedRewards(false), 0, "flushed");
        assertGt(terminal.rewardRate(false), 0, "stream started");

        vm.warp(block.timestamp + WEEK);
        assertApproxEqAbs(terminal.earned(alice, false), 140e18, 1e12);
    }

    /*//////////////////////////////////////////////////////////////
                          STREAM EXTENSION
    //////////////////////////////////////////////////////////////*/

    /// @dev A second pull mid-stream must roll the unpaid remainder into the new rate, not drop it.
    function test_secondPullRollsLeftoverIn() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + WEEK / 2);
        _deliverRevenue(700e18);

        vm.warp(block.timestamp + WEEK);
        uint256 earned = terminal.earned(alice, false);
        assertApproxEqAbs(earned, 280e18, 1e12, "both deliveries paid out in full");
    }

    /*//////////////////////////////////////////////////////////////
                              SOLVENCY
    //////////////////////////////////////////////////////////////*/

    /// @dev The Terminal must never owe more reward token than it holds.
    function test_neverPaysOutMoreThanItReceived() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        vm.prank(bob);
        terminal.stake(false, 250e18);
        vm.prank(carol);
        terminal.stake(true, 400e18);

        _deliverRevenue(1000e18);
        vm.warp(block.timestamp + WEEK + 1 days);

        uint256 held = runToken.balanceOf(address(terminal));
        uint256 owed = terminal.earned(alice, false) + terminal.earned(bob, false)
            + terminal.earned(carol, true);
        assertLe(owed, held, "cannot owe more than it holds");

        vm.prank(alice);
        terminal.claim(false);
        vm.prank(bob);
        terminal.claim(false);
        vm.prank(carol);
        terminal.claim(true);
        // Dust from integer division may remain; nothing may be missing.
        assertLe(
            terminal.earned(alice, false) + terminal.earned(bob, false) + terminal.earned(carol, true),
            1e12
        );
    }

    /*//////////////////////////////////////////////////////////////
                          THE TWO POOLS
    //////////////////////////////////////////////////////////////*/

    function test_poolsAreIndependent() public {
        vm.prank(alice);
        terminal.stake(false, 100e18); // $AUG pool
        vm.prank(bob);
        terminal.stake(true, 100e18); // LP pool

        _deliverRevenue(1000e18);
        vm.warp(block.timestamp + WEEK);

        // Both buckets are 20%, so equal stakes in each pool earn equally.
        assertApproxEqAbs(terminal.earned(alice, false), terminal.earned(bob, true), 1e12);
        assertEq(terminal.stakedBalance(alice, true), 0, "AUG staker holds no LP position");
    }

    function test_lpStakeRevertsWhenLpTokenUnset() public {
        Terminal fresh = new Terminal(address(aug), address(runToken), address(splitter));
        vm.prank(alice);
        vm.expectRevert(Terminal.LpTokenNotSet.selector);
        fresh.stake(true, 1e18);
    }

    /// @dev Swapping the LP token while people are staked would strand their position.
    function test_setLpToken_blockedWhilePoolOccupied() public {
        vm.prank(alice);
        terminal.stake(true, 100e18);

        MockLpToken other = new MockLpToken();
        vm.expectRevert(Terminal.InsufficientStake.selector);
        terminal.setLpToken(address(other));
    }

    function test_setLpToken_allowedWhenEmpty() public {
        MockLpToken other = new MockLpToken();
        terminal.setLpToken(address(other));
        assertEq(address(terminal.lpToken()), address(other));
    }

    function test_setLpToken_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        terminal.setLpToken(address(lp));
    }

    /*//////////////////////////////////////////////////////////////
                            PULL REWARDS
    //////////////////////////////////////////////////////////////*/

    /// @dev The Terminal is unstaffed — nobody's cooperation is needed to move revenue to stakers.
    function test_pullRewards_isPermissionless() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);

        runToken.transfer(address(splitter), 700e18);
        splitter.sync(address(runToken));

        vm.prank(makeAddr("randomer"));
        terminal.pullRewards();

        assertGt(terminal.rewardRate(false), 0);
    }

    function test_pullRewards_revertsWhenNothingOwed() public {
        vm.expectRevert(Terminal.NothingPulled.selector);
        terminal.pullRewards();
    }

    function test_pullRewards_takesBothBuckets() public {
        vm.prank(alice);
        terminal.stake(false, 100e18);
        vm.prank(bob);
        terminal.stake(true, 100e18);

        runToken.transfer(address(splitter), 1000e18);
        splitter.sync(address(runToken));

        (uint256 stakerAmount, uint256 lpAmount) = terminal.pullRewards();
        assertEq(stakerAmount, 200e18, "20% stakers");
        assertEq(lpAmount, 200e18, "20% LPs");
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 600e18, "Drop untouched");
    }

    function test_stake_revertsOnZero() public {
        vm.prank(alice);
        vm.expectRevert(Terminal.ZeroAmount.selector);
        terminal.stake(false, 0);
    }
}
