// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Cycles} from "../src/runner/Cycles.sol";

/// @notice The cycle clock governs rebinding, seasoning, tenure accrual and the claim window, so
///         boundary behaviour has to be exact. These tests pin Monday 00:00 UTC on both sides.
contract CyclesTest is Test {
    /// @dev Independently verified: `date -u -d @1767571200` -> Mon Jan  5 00:00:00 UTC 2026.
    uint256 constant GENESIS = 1767571200;
    uint256 constant WEEK = 7 days;

    function test_genesisConstant_isTheAnchorWeExpect() public pure {
        assertEq(Cycles.GENESIS, GENESIS);
        assertEq(Cycles.CYCLE_LENGTH, WEEK);
    }

    /*//////////////////////////////////////////////////////////////
                          BOUNDARY, EITHER SIDE
    //////////////////////////////////////////////////////////////*/

    function test_exactlyAtGenesis_isCycleZero() public pure {
        assertEq(Cycles.cycleAt(GENESIS), 0);
    }

    function test_oneSecondBeforeFirstBoundary_isStillCycleZero() public pure {
        assertEq(Cycles.cycleAt(GENESIS + WEEK - 1), 0);
    }

    function test_exactlyAtFirstBoundary_isCycleOne() public pure {
        assertEq(Cycles.cycleAt(GENESIS + WEEK), 1);
    }

    function test_oneSecondAfterFirstBoundary_isCycleOne() public pure {
        assertEq(Cycles.cycleAt(GENESIS + WEEK + 1), 1);
    }

    /// @dev The load-bearing assertion: the transition happens AT the boundary, not around it.
    function test_boundaryTransition_isExact() public pure {
        for (uint256 n = 1; n <= 12; n++) {
            uint256 boundary = GENESIS + (n * WEEK);
            assertEq(Cycles.cycleAt(boundary - 1), n - 1, "one second before boundary");
            assertEq(Cycles.cycleAt(boundary), n, "exactly at boundary");
            assertEq(Cycles.cycleAt(boundary + 1), n, "one second after boundary");
        }
    }

    function test_preGenesis_clampsToZero() public pure {
        assertEq(Cycles.cycleAt(0), 0);
        assertEq(Cycles.cycleAt(1), 0);
        assertEq(Cycles.cycleAt(GENESIS - 1), 0);
    }

    /*//////////////////////////////////////////////////////////////
                        EVERY BOUNDARY IS A MONDAY
    //////////////////////////////////////////////////////////////*/

    /// @dev 1767571200 is a Monday and the cycle length is exactly 7 days, so every boundary lands
    ///      on Monday 00:00 UTC. Days-since-Unix-epoch mod 7 == 4 identifies a Monday
    ///      (1970-01-01 was a Thursday).
    function test_everyBoundaryIsMondayMidnightUTC() public pure {
        for (uint256 n = 0; n < 120; n++) {
            uint256 start = Cycles.cycleStart(n);
            assertEq(start % 1 days, 0, "not midnight");
            assertEq((start / 1 days) % 7, 4, "not a Monday");
        }
    }

    /*//////////////////////////////////////////////////////////////
                          START / END / NEXT
    //////////////////////////////////////////////////////////////*/

    function test_cycleStartAndEnd_areConsistent() public pure {
        for (uint256 n = 0; n < 60; n++) {
            assertEq(Cycles.cycleStart(n), GENESIS + n * WEEK);
            assertEq(Cycles.cycleEnd(n), Cycles.cycleStart(n + 1));
            assertEq(Cycles.cycleAt(Cycles.cycleStart(n)), n);
            assertEq(Cycles.cycleAt(Cycles.cycleEnd(n) - 1), n);
        }
    }

    function test_nextBoundary_atExactBoundary_returnsTheFollowingOne() public pure {
        uint256 boundary = GENESIS + (5 * WEEK);
        assertEq(Cycles.nextBoundary(boundary), boundary + WEEK, "must be strictly after");
    }

    function test_nextBoundary_midCycle() public pure {
        uint256 t = GENESIS + (5 * WEEK) + 3 days;
        assertEq(Cycles.nextBoundary(t), GENESIS + (6 * WEEK));
    }

    function test_nextBoundary_preGenesis_isGenesis() public pure {
        assertEq(Cycles.nextBoundary(GENESIS - 1000), GENESIS);
    }

    function test_timeUntilNextBoundary() public pure {
        uint256 t = GENESIS + (5 * WEEK) + 3 days;
        assertEq(Cycles.timeUntilNextBoundary(t), 4 days);

        // One second into a cycle leaves a full week minus a second.
        assertEq(Cycles.timeUntilNextBoundary(GENESIS + 1), WEEK - 1);
    }

    /*//////////////////////////////////////////////////////////////
                                 FUZZ
    //////////////////////////////////////////////////////////////*/

    function testFuzz_cycleAt_isMonotonic(uint256 a, uint256 b) public pure {
        a = bound(a, GENESIS, GENESIS + 5200 * WEEK);
        b = bound(b, a, GENESIS + 5200 * WEEK);
        assertLe(Cycles.cycleAt(a), Cycles.cycleAt(b));
    }

    function testFuzz_timestampAlwaysFallsWithinItsOwnCycle(uint256 t) public pure {
        t = bound(t, GENESIS, GENESIS + 5200 * WEEK);
        uint256 c = Cycles.cycleAt(t);
        assertLe(Cycles.cycleStart(c), t);
        assertGt(Cycles.cycleEnd(c), t);
    }

    function testFuzz_nextBoundaryIsStrictlyAfterAndAtMostAWeekAway(uint256 t) public pure {
        t = bound(t, GENESIS, GENESIS + 5200 * WEEK);
        uint256 nb = Cycles.nextBoundary(t);
        assertGt(nb, t);
        assertLe(nb - t, WEEK);
        assertEq((nb / 1 days) % 7, 4, "boundary must be a Monday");
    }
}
