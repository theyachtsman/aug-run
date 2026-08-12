// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Weights} from "../src/items/Weights.sol";

contract WeightsTest is Test {
    function test_tierMultipliers() public pure {
        assertEq(Weights.tierMultiplier(1), 1.0e18);
        assertEq(Weights.tierMultiplier(2), 1.25e18);
        assertEq(Weights.tierMultiplier(3), 1.5e18);
    }

    function test_tierPrices() public pure {
        assertEq(Weights.tierPrice(1), 100e18);
        assertEq(Weights.tierPrice(2), 250e18);
        assertEq(Weights.tierPrice(3), 500e18);
    }

    function test_invalidTierReverts() public {
        vm.expectRevert(Weights.InvalidTier.selector);
        this.callTierMultiplier(0);
        vm.expectRevert(Weights.InvalidTier.selector);
        this.callTierMultiplier(4);
    }

    function callTierMultiplier(uint8 t) external pure returns (uint256) {
        return Weights.tierMultiplier(t);
    }

    /*//////////////////////////////////////////////////////////////
                          TENURE MULTIPLIER
    //////////////////////////////////////////////////////////////*/

    /// @dev Linear on purpose: an operator can look at a bay and know what next week is worth
    ///      without modelling a curve.
    function test_tenureMultiplier_isLinearAcrossEightCycles() public pure {
        assertEq(Weights.tenureMultiplier(0, 0), 1.0e18);
        assertEq(Weights.tenureMultiplier(1, 0), 1.0625e18);
        assertEq(Weights.tenureMultiplier(2, 0), 1.125e18);
        assertEq(Weights.tenureMultiplier(3, 0), 1.1875e18);
        assertEq(Weights.tenureMultiplier(4, 0), 1.25e18);
        assertEq(Weights.tenureMultiplier(5, 0), 1.3125e18);
        assertEq(Weights.tenureMultiplier(6, 0), 1.375e18);
        assertEq(Weights.tenureMultiplier(7, 0), 1.4375e18);
        assertEq(Weights.tenureMultiplier(8, 0), 1.5e18);
    }

    /// @dev Caps at 1.5x after eight cycles and never exceeds it.
    function test_tenureMultiplier_capsAtOnePointFive() public pure {
        assertEq(Weights.tenureMultiplier(8, 0), 1.5e18);
        assertEq(Weights.tenureMultiplier(9, 0), 1.5e18);
        assertEq(Weights.tenureMultiplier(100, 0), 1.5e18);
        assertEq(Weights.tenureMultiplier(type(uint256).max, 0), 1.5e18);
    }

    function testFuzz_tenureMultiplier_neverExceedsCeiling(uint256 tenure, uint256 calibrations)
        public
        pure
    {
        calibrations = bound(calibrations, 0, 100_000);
        uint256 m = Weights.tenureMultiplier(tenure, calibrations);
        assertLe(m, 1.5e18);
        assertGe(m, 1.0e18);
    }

    /*//////////////////////////////////////////////////////////////
                             CALIBRATION
    //////////////////////////////////////////////////////////////*/

    function test_calibration_addsThreeThousandthsEach() public pure {
        assertEq(Weights.tenureMultiplier(0, 1), 1.003e18);
        assertEq(Weights.tenureMultiplier(0, 7), 1.021e18);
        assertEq(Weights.tenureMultiplier(1, 7), 1.0835e18);
    }

    /// @dev Spec: seven daily calibrations add ~0.021x per cycle on top of the base 0.0625x,
    ///      bringing a consistent calibrator to the ceiling in six cycles instead of eight.
    function test_calibration_reachesCeilingInSixCyclesNotEight() public pure {
        // Base-only: still short of the ceiling at six cycles.
        assertLt(Weights.tenureMultiplier(6, 0), 1.5e18);

        // With seven calibrations a cycle for six cycles (42 total), the ceiling is reached.
        assertEq(Weights.tenureMultiplier(6, 42), 1.5e18);

        // And five cycles' worth is not yet enough, so six is genuinely the crossover.
        assertLt(Weights.tenureMultiplier(5, 35), 1.5e18);
    }

    function test_calibration_cannotExceedCeiling() public pure {
        assertEq(Weights.tenureMultiplier(8, 1000), 1.5e18);
    }

    /*//////////////////////////////////////////////////////////////
                              BAY WEIGHT
    //////////////////////////////////////////////////////////////*/

    /// @dev The full spread: a single bay runs 1.0x (tier-1 freshly seasoned) to 2.25x (tier-3 at
    ///      full tenure).
    function test_bayWeight_fullSpread() public pure {
        assertEq(Weights.bayWeight(1, 0, 0), 1.0e18, "floor");
        assertEq(Weights.bayWeight(3, 8, 0), 2.25e18, "ceiling");
    }

    function test_bayWeight_tierTimesTenure() public pure {
        assertEq(Weights.bayWeight(2, 0, 0), 1.25e18);
        assertEq(Weights.bayWeight(2, 8, 0), 1.875e18); // 1.25 * 1.5
        assertEq(Weights.bayWeight(3, 4, 0), 1.875e18); // 1.5 * 1.25
        assertEq(Weights.bayWeight(1, 4, 0), 1.25e18);
    }

    /// @dev A fully built, long-held unit carries about 6.75x a bare one-bay unit on base tier.
    function test_threeMaxedBays_areSixPointSevenFiveX() public pure {
        uint256 maxed = 3 * Weights.bayWeight(3, 8, 0);
        uint256 bare = Weights.bayWeight(1, 0, 0);
        assertEq(maxed, 6.75e18);
        assertEq(maxed / (bare / 1e18), 6.75e18);
    }

    /// @dev Two one-bay units, same capacity, different operators: 2.25x versus 1.0x.
    function test_tenuredTopTierIsWorth2point25xAFreshBaseTier() public pure {
        assertEq(Weights.bayWeight(3, 8, 0), 2.25e18);
        assertEq(Weights.bayWeight(1, 0, 0), 1.0e18);
    }
}
