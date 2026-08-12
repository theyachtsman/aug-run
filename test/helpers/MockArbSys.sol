// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice Stand-in for Arbitrum's ArbSys precompile, etched at 0x64 in tests.
/// @dev Exists so the ArbSys branch of CommitRevealRandomness is actually covered. Without it the
///      tests only ever exercise the plain-EVM fallback, which is exactly how the L1/L2 block-number
///      mismatch reached a live deployment unnoticed.
contract MockArbSys {
    /// @dev Offset so arbBlockNumber() is deliberately NOT equal to block.number — mirroring the
    ///      real chain, where the two differ by ~88 million. Any code that conflates them breaks here.
    uint256 public constant L2_OFFSET = 88_000_000;

    function arbBlockNumber() external view returns (uint256) {
        return block.number + L2_OFFSET;
    }

    function arbBlockHash(uint256 blockNumber) external view returns (bytes32) {
        if (blockNumber < L2_OFFSET) return bytes32(0);
        return blockhash(blockNumber - L2_OFFSET);
    }
}
