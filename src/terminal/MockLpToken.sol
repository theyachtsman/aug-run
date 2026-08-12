// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockLpToken — a stand-in for a real $AUG liquidity pair token
/// @notice Lets the Terminal's LP pool be exercised end to end before a DEX exists on this chain.
/// @dev
///      ████  T E S T N E T   O N L Y  ████
///
///      Anyone can mint this, freely and without limit. It represents nothing. It exists solely so
///      the LP staking path is testable rather than shipping unexercised.
///
///      TO SHIP TO MAINNET: do not deploy this. Call `Terminal.setLpToken` with the real pair token
///      instead — a Uniswap-V2-style ERC-20 LP token, which is what a launchpad mints. A Uniswap V3
///      position is an ERC-721 and will NOT work with the Terminal's LP pool.
contract MockLpToken is ERC20 {
    constructor() ERC20("AUG//RUN Mock LP", "mAUG-LP") {}

    /// @notice Mint yourself test LP tokens. Testnet scaffolding — see the contract notice.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
