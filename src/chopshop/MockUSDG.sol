// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MockUSDG — stand-in for the Global Dollar
/// @notice The Chop Shop denominates backing and entry in USDG. USDG is not deployed on Robinhood
///         Chain testnet (probed and absent), so this exists to make the table exercisable.
/// @dev
///      ████  T E S T N E T   O N L Y  ████
///
///      Mints freely to anyone and represents nothing.
///
///      TO SHIP TO MAINNET: do not deploy this. Pass the real USDG address to the ChopShop
///      constructor instead. Note real USDG has **6 decimals**, not 18 — this mock matches that so
///      the arithmetic is exercised the way production will see it.
contract MockUSDG is ERC20 {
    constructor() ERC20("Mock Global Dollar", "mUSDG") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    /// @notice Mint yourself test USDG. Testnet scaffolding — see the contract notice.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
