// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRunPriceOracle} from "./IRunPriceOracle.sol";

/// @title TestnetRunPriceOracle — an owner-settable $RUN/ETH price
/// @notice Lets the dev panel push the price across the 0.1 ETH and 1 ETH thresholds so all three
///         Black Market sell fee tiers are exercisable in minutes.
/// @dev
///      ████  T E S T N E T   O N L Y  ████
///
///      This contract has an owner who can set the price to anything. That is fine for a harness
///      and completely unacceptable in production, where the sell fee would be trivially
///      manipulable. It exists because Robinhood Chain testnet has no DEX and no price feed.
///
///      TO SHIP TO MAINNET: deploy a real implementation of IRunPriceOracle — a $RUN/ETH pool TWAP
///      or an external feed — and point the Black Market at it with `setPriceOracle`. Nothing in
///      the Black Market needs to change; it only ever reads through the interface.
contract TestnetRunPriceOracle is IRunPriceOracle, Ownable {
    /// @inheritdoc IRunPriceOracle
    uint256 public ethPerRun;

    /// @inheritdoc IRunPriceOracle
    uint256 public lastUpdated;

    event PriceUpdated(uint256 ethPerRun, uint256 at);

    error ZeroPrice();

    /// @param initialEthPerRun Wei of ETH per whole $RUN.
    constructor(uint256 initialEthPerRun) Ownable(msg.sender) {
        if (initialEthPerRun == 0) revert ZeroPrice();
        ethPerRun = initialEthPerRun;
        lastUpdated = block.timestamp;
        emit PriceUpdated(initialEthPerRun, block.timestamp);
    }

    /// @notice Set the $RUN/ETH price. Testnet harness only — see the contract notice.
    function setEthPerRun(uint256 newEthPerRun) external onlyOwner {
        if (newEthPerRun == 0) revert ZeroPrice();
        ethPerRun = newEthPerRun;
        lastUpdated = block.timestamp;
        emit PriceUpdated(newEthPerRun, block.timestamp);
    }

    /// @notice Value of `runAmount` (18dp $RUN) in wei, for convenience in the UI.
    function valueInWei(uint256 runAmount) external view returns (uint256) {
        return (runAmount * ethPerRun) / 1e18;
    }
}
