// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";

/// @title ProtocolReserve — the $AUG the protocol keeps behind the counter
/// @notice Funds the Fixer's $AUG loans and, in phase 7, Chop Shop redemptions. Half of every
///         Ripperdoc payment flows in here; the other half burns.
/// @dev Replaces the plain EOA that held the reserve up to phase 5. Kept lean deliberately — early
///      borrowing is expected to be minimal and the balance grows over time as Augment sales feed
///      it. Also accepts ERC-1155s so Iced Augment collateral has somewhere to land.
contract ProtocolReserve is Ownable, ERC1155Holder {
    using SafeERC20 for IERC20;

    IERC20 public immutable AUG_TOKEN;

    /// @notice The Fixer. The only address permitted to draw down the reserve.
    address public fixer;

    uint256 public totalLent;
    uint256 public totalRepaid;

    event FixerUpdated(address indexed fixer);
    event Lent(address indexed to, uint256 amount);
    event Repaid(address indexed from, uint256 amount);
    event Swept(address indexed token, address indexed to, uint256 amount);

    error NotFixer();
    error ZeroAddress();
    error InsufficientReserve(uint256 requested, uint256 available);

    constructor(address aug) Ownable(msg.sender) {
        if (aug == address(0)) revert ZeroAddress();
        AUG_TOKEN = IERC20(aug);
    }

    modifier onlyFixer() {
        if (msg.sender != fixer) revert NotFixer();
        _;
    }

    /// @notice Wire the Fixer. Re-pointable by the owner so later phases can replace it.
    function setFixer(address fixer_) external onlyOwner {
        if (fixer_ == address(0)) revert ZeroAddress();
        fixer = fixer_;
        emit FixerUpdated(fixer_);
    }

    /// @notice Draw $AUG out to fund a loan.
    function lend(address to, uint256 amount) external onlyFixer {
        uint256 available = AUG_TOKEN.balanceOf(address(this));
        if (amount > available) revert InsufficientReserve(amount, available);
        totalLent += amount;
        AUG_TOKEN.safeTransfer(to, amount);
        emit Lent(to, amount);
    }

    /// @notice Return borrowed principal. Permissionless — paying the reserve back is never harmful.
    /// @dev Only principal comes back here. Interest is burned rather than banked, per spec.
    function repay(uint256 amount) external {
        AUG_TOKEN.safeTransferFrom(msg.sender, address(this), amount);
        totalRepaid += amount;
        emit Repaid(msg.sender, amount);
    }

    function balance() external view returns (uint256) {
        return AUG_TOKEN.balanceOf(address(this));
    }

    /// @notice Outstanding principal currently lent out.
    function outstanding() external view returns (uint256) {
        return totalLent > totalRepaid ? totalLent - totalRepaid : 0;
    }

    /// @notice Recover assets other than the reserve's own $AUG (e.g. seized collateral to dispose).
    function sweep(address token, address to, uint256 amount) external onlyOwner {
        if (to == address(0)) revert ZeroAddress();
        IERC20(token).safeTransfer(to, amount);
        emit Swept(token, to, amount);
    }
}
