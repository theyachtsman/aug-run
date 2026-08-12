// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title IRwaVenue — where the Drop turns protocol revenue into real-world assets
/// @notice The Drop buys **in aggregate, one purchase per ticker** — all NVDA exposure in a single
///         call, then divided among the bays running it. Twelve Augments means at most twelve
///         purchases per Drop regardless of collection size.
/// @dev Robinhood Chain testnet has no swap venue and no Stock Tokens, so this is an interface with
///      a mock implementation. Mainnet points it at a real venue for Robinhood Stock Tokens, priced
///      by Chainlink Data Feeds — which ARE live on Robinhood Chain.
///
///      `buy` returning zero is the "unavailable ticker" case: the spec says such a bay is skipped
///      for that cycle and its share rolls into the next pool. No substitute, no fallback holding.
interface IRwaVenue {
    /// @notice Whether this ticker can currently be bought. False means skip it this cycle.
    function isAvailable(bytes32 ticker) external view returns (bool);

    /// @notice The ERC-20 representing a ticker's exposure.
    function assetFor(bytes32 ticker) external view returns (address);

    /// @notice Spend `amountIn` of `payToken` on `ticker`. Returns the asset and amount acquired.
    /// @dev Returns (address(0), 0) if the ticker is unavailable, rather than reverting — one dead
    ///      ticker must not block the whole Drop.
    function buy(bytes32 ticker, address payToken, uint256 amountIn)
        external
        returns (address asset, uint256 amountOut);

    /// @notice Sell `amount` of `asset` back for `wantToken`. Used for the unclaimed-Drop buyback.
    function sell(address asset, uint256 amount, address wantToken)
        external
        returns (uint256 amountOut);
}
