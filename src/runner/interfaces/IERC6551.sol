// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @notice The canonical ERC-6551 registry interface (v0.3.1).
/// @dev Deployed at 0x000000006551c19487814612e58FE06813775758 on every chain that has it —
///      confirmed live on Robinhood Chain testnet. We point at it; we never deploy one.
interface IERC6551Registry {
    /// @dev Emitted when a token-bound account is created.
    event ERC6551AccountCreated(
        address account,
        address indexed implementation,
        bytes32 salt,
        uint256 chainId,
        address indexed tokenContract,
        uint256 indexed tokenId
    );

    error AccountCreationFailed();

    /// @notice Deploys the token-bound account for a token, or returns it if already deployed.
    function createAccount(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external returns (address account);

    /// @notice Computes the token-bound account address for a token. Does not deploy.
    function account(
        address implementation,
        bytes32 salt,
        uint256 chainId,
        address tokenContract,
        uint256 tokenId
    ) external view returns (address account);
}

/// @notice ERC-6551 account interface.
interface IERC6551Account {
    receive() external payable;

    /// @notice Returns the identifier of the non-fungible token bound to this account.
    function token() external view returns (uint256 chainId, address tokenContract, uint256 tokenId);

    /// @notice Returns a value that changes each time the account state changes.
    function state() external view returns (uint256);

    /// @notice Returns magic value 0x523e3260 if `signer` is valid for this account.
    function isValidSigner(address signer, bytes calldata context) external view returns (bytes4 magicValue);
}

/// @notice ERC-6551 executable account interface.
interface IERC6551Executable {
    /// @notice Executes a low-level operation from this account. `operation` 0 is CALL.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        returns (bytes memory);
}
