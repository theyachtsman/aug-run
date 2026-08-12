// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/// @title $AUG — the street economy's currency
/// @notice Burned at the Ripperdoc for Augments and Expansion Modules, staked at the Terminal.
///         Half of every Ripperdoc payment burns permanently; half funds the protocol reserve.
/// @dev Supply is minted once, in the constructor, and can only ever go DOWN from there:
///      - no mint function after construction, no owner, no roles, no upgrade path
///      - `burn`/`burnFrom` (ERC20Burnable) are the only supply-changing paths, and they are
///        one-way. Phase 3 leans on this heavily.
///      Launch split follows the spec: 80% circulating / 15% protocol reserve / 5% launch seed.
///
///      Note: the protocol is AUG//RUN and the ERC-721 wallet currency is $RUN, so `AUG_TOKEN`
///      (this currency) and `AUGMENTS` (the ERC-1155 items) are deliberately distinct names
///      wherever both appear.
contract AUG is ERC20, ERC20Burnable {
    /// @notice The supply minted at construction. Burning drives `totalSupply()` below this.
    uint256 public constant INITIAL_SUPPLY = 100_000_000e18;

    /// @notice 80% — Augment purchases, staking, organic trading.
    uint256 public constant CIRCULATING_ALLOCATION = 80_000_000e18;
    /// @notice 15% — backs Chop Shop redemptions and Fixer $AUG loans. Grows via Augment sales.
    uint256 public constant RESERVE_ALLOCATION = 15_000_000e18;
    /// @notice 5% — bootstraps staking rewards and Black Market $AUG liquidity.
    uint256 public constant SEED_ALLOCATION = 5_000_000e18;

    /*//////////////////////////////////////////////////////////////////////////

        ████  T E S T N E T   F A U C E T  ████

        EVERYTHING IN THIS BLOCK IS TESTNET-ONLY SCAFFOLDING.

        Identical gating to $RUN. `TESTNET` is an immutable set once, in the
        constructor. When it is false — what a mainnet deployment MUST pass —
        `faucet()` reverts unconditionally and NO faucet reserve is carved
        out, so the 80/15/5 split lands exactly as the spec describes.

        The faucet does NOT mint. On a testnet deploy the constructor takes
        FAUCET_ALLOCATION out of the CIRCULATING slice (not out of thin air,
        and not out of the protocol reserve) and parks it in this contract's
        own balance. `faucet()` only ever transfers from that pot.

        TO SHIP TO MAINNET: deploy with testnet_ = false. That is the whole
        procedure.

    //////////////////////////////////////////////////////////////////////////*/

    /// @notice True only on testnet deployments. Gates `faucet()`. Set once, in the constructor.
    bool public immutable TESTNET;

    /// @notice Carved out of the circulating slice at construction to back the faucet (testnet only).
    uint256 public constant FAUCET_ALLOCATION = 10_000_000e18;

    /// @notice Handed out per claim. Twenty tier-3 Augments' worth (500 $AUG each).
    uint256 public constant FAUCET_DRIP = 10_000e18;

    /// @notice Per-address cooldown between claims.
    uint256 public constant FAUCET_COOLDOWN = 1 hours;

    /// @notice Timestamp of each address's last successful claim. Zero means never claimed.
    mapping(address account => uint256 timestamp) public lastFaucetClaim;

    event FaucetClaimed(address indexed to, uint256 amount);

    /// @dev Thrown by `faucet()` on a non-testnet deployment.
    error FaucetDisabled();
    /// @dev Thrown when the caller claims again before their cooldown elapses.
    error FaucetCooldownActive(uint256 availableAt);
    /// @dev Thrown when the faucet reserve is exhausted.
    error FaucetDrained();
    /// @dev Thrown when any constructor recipient is the zero address.
    error ZeroRecipient();

    /// @param circulating     Receives the 80% circulating slice (minus the faucet reserve on testnet).
    /// @param protocolReserve Receives the 15% protocol reserve slice.
    /// @param launchSeed      Receives the 5% launch seed slice.
    /// @param testnet_        MUST be false for a mainnet deployment. See the banner above.
    constructor(address circulating, address protocolReserve, address launchSeed, bool testnet_)
        ERC20("AUG", "AUG")
    {
        if (circulating == address(0) || protocolReserve == address(0) || launchSeed == address(0)) {
            revert ZeroRecipient();
        }
        TESTNET = testnet_;

        if (testnet_) {
            _mint(address(this), FAUCET_ALLOCATION);
            _mint(circulating, CIRCULATING_ALLOCATION - FAUCET_ALLOCATION);
        } else {
            _mint(circulating, CIRCULATING_ALLOCATION);
        }
        _mint(protocolReserve, RESERVE_ALLOCATION);
        _mint(launchSeed, SEED_ALLOCATION);
    }

    /// @notice Pull a fixed test allocation. Testnet only — reverts otherwise.
    function faucet() external {
        if (!TESTNET) revert FaucetDisabled();

        uint256 last = lastFaucetClaim[msg.sender];
        if (last != 0) {
            uint256 availableAt = last + FAUCET_COOLDOWN;
            if (block.timestamp < availableAt) revert FaucetCooldownActive(availableAt);
        }
        if (balanceOf(address(this)) < FAUCET_DRIP) revert FaucetDrained();

        lastFaucetClaim[msg.sender] = block.timestamp;
        _transfer(address(this), msg.sender, FAUCET_DRIP);
        emit FaucetClaimed(msg.sender, FAUCET_DRIP);
    }

    /// @notice How much the faucet has left to give out.
    function faucetRemaining() external view returns (uint256) {
        return balanceOf(address(this));
    }

    /// @notice Timestamp at which `account` may claim again. Zero if claimable now.
    function faucetAvailableAt(address account) external view returns (uint256) {
        uint256 last = lastFaucetClaim[account];
        if (last == 0) return 0;
        uint256 availableAt = last + FAUCET_COOLDOWN;
        return block.timestamp >= availableAt ? 0 : availableAt;
    }
}
