// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title Cycles — the one clock everything in AUG//RUN keys off
/// @notice Weekly epochs anchored to Monday 00:00 UTC. Rebinding, seasoning, tenure accrual and the
///         claim window all read this clock, so an operator only ever tracks one deadline.
/// @dev Pure functions of `block.timestamp` against a fixed genesis constant. No storage, no owner,
///      nothing settable. 00:00 UTC lands at 8pm US Eastern during DST and 7pm outside it — UTC is
///      canonical and local time drifts.
library Cycles {
    /// @notice Monday 2026-01-05 00:00:00 UTC. Verified: `date -u -d @1767571200` → Mon Jan 5 2026.
    /// @dev Deliberately in the past, so cycle numbers are positive and meaningful from deploy and
    ///      there are no zero-or-negative edge cases live during testing.
    uint256 internal constant GENESIS = 1767571200;

    /// @notice One cycle is one week.
    uint256 internal constant CYCLE_LENGTH = 7 days;

    /// @notice The cycle number containing `timestamp`.
    /// @dev Timestamps before GENESIS clamp to cycle 0. GENESIS is in the past on every live
    ///      network, so this only bites in unit tests that forget to warp — hence the clamp rather
    ///      than a revert, which would make the clock unusable at Foundry's default timestamp of 1.
    function cycleAt(uint256 timestamp) internal pure returns (uint256) {
        if (timestamp < GENESIS) return 0;
        return (timestamp - GENESIS) / CYCLE_LENGTH;
    }

    /// @notice The timestamp at which `cycle` opens — always a Monday 00:00 UTC.
    function cycleStart(uint256 cycle) internal pure returns (uint256) {
        return GENESIS + (cycle * CYCLE_LENGTH);
    }

    /// @notice The timestamp at which `cycle` closes, i.e. the open of the next one.
    function cycleEnd(uint256 cycle) internal pure returns (uint256) {
        return GENESIS + ((cycle + 1) * CYCLE_LENGTH);
    }

    /// @notice The next Monday 00:00 UTC boundary strictly after `timestamp`.
    function nextBoundary(uint256 timestamp) internal pure returns (uint256) {
        if (timestamp < GENESIS) return GENESIS;
        return cycleEnd(cycleAt(timestamp));
    }

    /// @notice Seconds remaining until the next cycle boundary.
    function timeUntilNextBoundary(uint256 timestamp) internal pure returns (uint256) {
        return nextBoundary(timestamp) - timestamp;
    }
}
