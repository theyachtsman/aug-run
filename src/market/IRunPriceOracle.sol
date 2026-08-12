// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IRunPriceOracle — the $RUN/ETH reference the Black Market's sell fee tiers key off
/// @notice The Black Market's sell fee is tiered by the ETH value of a unit (25% below 0.1 ETH,
///         15% between 0.1 and 1 ETH, 10% above 1 ETH), so it needs a $RUN price denominated in ETH.
/// @dev Robinhood Chain testnet has **no DEX, no WETH and no price feed** — verified by probing the
///      canonical Uniswap V2/V3 factory and WETH addresses, none of which are deployed. So this is
///      an interface with a swappable implementation rather than a direct pool read.
///
///      Phase 6's Fixer needs the same reference ("pay an upfront rate in ETH pegged to the Black
///      Market's current sell fee"), so this interface is deliberately standalone and not buried
///      inside the Black Market.
interface IRunPriceOracle {
    /// @notice Wei of ETH per 1e18 $RUN (i.e. per one whole $RUN), scaled to 1e18-style fixed point.
    /// @dev Value of `runAmount` in wei = `runAmount * ethPerRun() / 1e18`.
    function ethPerRun() external view returns (uint256);

    /// @notice Timestamp of the last price update, so consumers can reject a stale reading.
    function lastUpdated() external view returns (uint256);
}
