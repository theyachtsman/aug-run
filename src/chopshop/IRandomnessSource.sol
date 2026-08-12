// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IRandomnessSource — the Chop Shop's roll entropy, behind a swappable interface
/// @notice Two-step by necessity: a request is made now and the value only becomes knowable later.
///         Anything resolvable in a single transaction is predictable by the caller, and the Chop
///         Shop has real value riding on each roll.
/// @dev **Chainlink VRF v2.5 does not support Robinhood Chain** — verified against Chainlink's
///      supported-networks list (Arbitrum, Avalanche, BASE, BNB, Ethereum, OP, Polygon, Ronin,
///      Soneium) and by probing for LINK and a VRF coordinator on-chain, neither of which exist
///      here. CCIP, Data Feeds and Data Streams are live; VRF is not.
///
///      So this is an interface with a commit-reveal implementation today. When VRF lands, write an
///      adapter and call `ChopShop.setRandomnessSource` — nothing in the Chop Shop changes.
interface IRandomnessSource {
    /// @notice Request a random value. Not knowable until `isReady` returns true.
    /// @param userSeed Caller-supplied entropy mixed into the result.
    function requestRandomness(bytes32 userSeed) external returns (uint256 requestId);

    /// @notice Whether `requestId` can be resolved right now.
    function isReady(uint256 requestId) external view returns (bool);

    /// @notice Whether the window to resolve `requestId` has closed. Expired requests must refund.
    function isExpired(uint256 requestId) external view returns (bool);

    /// @notice The random value. Reverts unless `isReady`.
    function randomness(uint256 requestId) external view returns (uint256);
}
