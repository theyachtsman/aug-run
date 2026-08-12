// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title ExpansionModules — ERC-1155, the addon that expands what a unit can carry
/// @notice The Module is the item you buy; a bay is the slot it opens. 500 $AUG each, maximum two
///         per unit, giving every unit the same three-bay ceiling.
/// @dev A single token ID, since every Module is identical. Loose Modules are transferable;
///      installing one burns it and opens a bay on the target unit.
contract ExpansionModules is ERC1155, Ownable {
    /// @notice The only token ID this contract issues.
    uint256 public constant MODULE_ID = 1;

    /// @notice The Ripperdoc. The only address permitted to mint or burn.
    address public ripperdoc;

    /// @notice True only on testnet deployments. Allows the Ripperdoc to be re-pointed.
    bool public immutable TESTNET;

    event RipperdocUpdated(address indexed ripperdoc);

    error NotRipperdoc();
    error ZeroAddress();
    error RipperdocAlreadySet();

    /// @param testnet_ MUST be false for a mainnet deployment — see `setRipperdoc`.
    constructor(string memory uri_, bool testnet_) ERC1155(uri_) Ownable(msg.sender) {
        TESTNET = testnet_;
    }

    modifier onlyRipperdoc() {
        if (msg.sender != ripperdoc) revert NotRipperdoc();
        _;
    }

    /// @notice Wire up the Ripperdoc.
    /// @dev Strictly set-once on mainnet: this address can mint Modules freely. Re-pointable by the
    ///      owner on testnet only, so later phases can swap the Ripperdoc.
    function setRipperdoc(address ripperdoc_) external onlyOwner {
        if (ripperdoc_ == address(0)) revert ZeroAddress();
        if (ripperdoc != address(0) && !TESTNET) revert RipperdocAlreadySet();
        ripperdoc = ripperdoc_;
        emit RipperdocUpdated(ripperdoc_);
    }

    function mint(address to, uint256 amount) external onlyRipperdoc {
        _mint(to, MODULE_ID, amount, "");
    }

    function burn(address from, uint256 amount) external onlyRipperdoc {
        _burn(from, MODULE_ID, amount);
    }

    /// @notice Convenience balance accessor for the single module ID.
    function balanceOf(address account) external view returns (uint256) {
        return balanceOf(account, MODULE_ID);
    }
}
