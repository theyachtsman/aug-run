// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Weights — allocation weight math, fixed-point at 1e18
/// @notice Tier buys weight, tenure earns it. A bay ranges from 1.0x (tier-1, freshly seasoned) to
///         2.25x (tier-3 at full tenure); a fully built, long-held unit carries about 6.75x the
///         weight of a bare one-bay unit on base tier.
/// @dev Deliberately catalog-size agnostic — adding Augments to the Ripperdoc never touches this
///      file, because weight is a function of TIER, never of which Augment or ticker is seated.
library Weights {
    uint256 internal constant ONE = 1e18;

    /// @notice +0.0625x per cycle seated.
    uint256 internal constant TENURE_STEP = 0.0625e18;

    /// @notice Tenure stops accruing after eight cycles — about two months of continuous service.
    uint256 internal constant MAX_TENURE_CYCLES = 8;

    /// @notice Each Calibration adds +0.003x. Seven a week adds ~0.021x per cycle.
    uint256 internal constant CALIBRATION_STEP = 0.003e18;

    /// @notice The tenure multiplier ceiling. Calibration only accelerates the climb to it.
    uint256 internal constant MAX_TENURE_MULTIPLIER = 1.5e18;

    error InvalidTier();

    /// @notice Tier multiplier: 1.0x / 1.25x / 1.5x.
    /// @dev Deliberately modest and deliberately worse per dollar — bay slots are the scarce
    ///      resource, so paying a premium for weight per slot is correct only once bays run out.
    function tierMultiplier(uint8 tier) internal pure returns (uint256) {
        if (tier == 1) return 1e18;
        if (tier == 2) return 1.25e18;
        if (tier == 3) return 1.5e18;
        revert InvalidTier();
    }

    /// @notice $AUG price by tier: 100 / 250 / 500.
    function tierPrice(uint8 tier) internal pure returns (uint256) {
        if (tier == 1) return 100e18;
        if (tier == 2) return 250e18;
        if (tier == 3) return 500e18;
        revert InvalidTier();
    }

    /// @notice 1.0 + 0.0625 * min(tenureCycles, 8) + 0.003 * calibrations, capped at 1.5x.
    /// @dev Calibration folds into the same multiplier and the same ceiling, which is why a
    ///      consistent calibrator reaches 1.5x in six cycles instead of eight rather than exceeding
    ///      it. Skipping never penalises — it only forgoes the acceleration.
    function tenureMultiplier(uint256 tenureCycles, uint256 calibrations) internal pure returns (uint256) {
        uint256 capped = tenureCycles > MAX_TENURE_CYCLES ? MAX_TENURE_CYCLES : tenureCycles;
        uint256 m = ONE + (TENURE_STEP * capped) + (CALIBRATION_STEP * calibrations);
        return m > MAX_TENURE_MULTIPLIER ? MAX_TENURE_MULTIPLIER : m;
    }

    /// @notice bayWeight = tierMultiplier * tenureMultiplier.
    function bayWeight(uint8 tier, uint256 tenureCycles, uint256 calibrations)
        internal
        pure
        returns (uint256)
    {
        return (tierMultiplier(tier) * tenureMultiplier(tenureCycles, calibrations)) / ONE;
    }
}
