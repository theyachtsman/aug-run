// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title $RUN — AUG//RUN's fixed-supply exchange currency
/// @notice The old company's internal currency, baked into every unit's firmware. The fixed unit of
///         exchange at the Black Market: 1,000,000 $RUN activates a Stock//Runner.
/// @dev Supply is minted once, in the constructor, and is immutable thereafter:
///      - no mint function, public or internal-reachable, after construction
///      - no owner, no roles, no access control of any kind
///      - no burn (unlike $AUG) — total supply is pinned at MAX_SUPPLY forever
///      - no proxy, no upgrade path, no initializer
contract RUN is ERC20 {
    /// @notice The entire supply. Minted in the constructor; never changes.
    uint256 public constant MAX_SUPPLY = 1_000_000_000e18;

    /*//////////////////////////////////////////////////////////////////////////

        ████  T E S T N E T   F A U C E T  ████

        EVERYTHING IN THIS BLOCK IS TESTNET-ONLY SCAFFOLDING.

        `TESTNET` is an immutable set once, in the constructor. When it is
        false — which is what a mainnet deployment MUST pass — `faucet()`
        reverts unconditionally and NO faucet reserve is ever allocated, so
        the full MAX_SUPPLY goes to the treasury and this block is inert.

        The faucet does NOT mint. It cannot: there is no mint path after
        construction. On a testnet deploy the constructor carves
        FAUCET_ALLOCATION out of MAX_SUPPLY and parks it in this contract's
        own balance; `faucet()` only ever transfers from that pre-funded pot.
        Fixed supply holds on testnet and mainnet alike.

        TO SHIP TO MAINNET: deploy with testnet_ = false. That is the whole
        procedure. Do not delete this block — a mainnet deploy with the flag
        false is already correct and identical bytecode is easier to verify.

    //////////////////////////////////////////////////////////////////////////*/

    /// @notice True only on testnet deployments. Gates `faucet()`. Set once, in the constructor.
    bool public immutable TESTNET;

    /// @notice Amount parked in this contract at construction to back the faucet (testnet only).
    uint256 public constant FAUCET_ALLOCATION = 100_000_000e18;

    /// @notice Handed out per claim. Five genesis mints' worth (1,000,000 $RUN each).
    uint256 public constant FAUCET_DRIP = 5_000_000e18;

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
    /// @dev Thrown when the treasury address is the zero address.
    error ZeroTreasury();

    /// @param treasury Receives the full supply (minus the faucet reserve on testnet).
    /// @param testnet_ MUST be false for a mainnet deployment. See the banner above.
    constructor(address treasury, bool testnet_) ERC20("AUG//RUN", "RUN") {
        if (treasury == address(0)) revert ZeroTreasury();
        TESTNET = testnet_;

        if (testnet_) {
            _mint(address(this), FAUCET_ALLOCATION);
            _mint(treasury, MAX_SUPPLY - FAUCET_ALLOCATION);
        } else {
            _mint(treasury, MAX_SUPPLY);
        }
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
