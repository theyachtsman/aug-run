// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import {IERC6551Account, IERC6551Executable} from "./interfaces/IERC6551.sol";

/// @title ERC6551Account — the ERC-6551 reference account implementation
/// @notice Every Stock//Runner gets one of these as its own onchain wallet. It holds the unit's
///         tokenized equities; whoever owns the NFT controls the wallet.
/// @dev This is the reference implementation from EIP-6551, reproduced verbatim in behaviour. It is
///      deliberately NOT a custom TBA — the spec calls for the standard reference account, and the
///      canonical registry at 0x000000006551c19487814612e58FE06813775758 (already live on Robinhood
///      Chain testnet) deploys ERC-1167 proxies pointing here.
///
///      Ownership is derived, not stored: `token()` reads the bound NFT out of the proxy's own
///      bytecode footer, and `owner()` resolves to that NFT's current holder. Selling the
///      Stock//Runner therefore transfers the wallet and everything in it, with no migration step.
contract ERC6551Account is IERC165, IERC1271, IERC6551Account, IERC6551Executable {
    /// @notice Increments on every state-changing operation, per ERC-6551.
    uint256 public state;

    error InvalidSigner();
    error UnsupportedOperation();

    receive() external payable override {}

    /// @notice Execute a call from this account. Only the bound NFT's owner may call.
    /// @param operation Must be 0 (CALL). DELEGATECALL/CREATE/CREATE2 are intentionally unsupported.
    function execute(address to, uint256 value, bytes calldata data, uint8 operation)
        external
        payable
        virtual
        override
        returns (bytes memory result)
    {
        if (!_isValidSigner(msg.sender)) revert InvalidSigner();
        if (operation != 0) revert UnsupportedOperation();

        ++state;

        bool success;
        (success, result) = to.call{value: value}(data);
        if (!success) {
            assembly {
                revert(add(result, 32), mload(result))
            }
        }
    }

    /// @notice Returns the ERC-6551 magic value if `signer` controls this account.
    function isValidSigner(address signer, bytes calldata) external view virtual override returns (bytes4) {
        if (_isValidSigner(signer)) return IERC6551Account.isValidSigner.selector;
        return bytes4(0);
    }

    /// @notice ERC-1271 signature validation against the bound NFT's owner.
    function isValidSignature(bytes32 hash, bytes memory signature)
        external
        view
        virtual
        override
        returns (bytes4)
    {
        if (SignatureChecker.isValidSignatureNow(owner(), hash, signature)) {
            return IERC1271.isValidSignature.selector;
        }
        return bytes4(0);
    }

    function supportsInterface(bytes4 interfaceId) external pure virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId || interfaceId == type(IERC6551Account).interfaceId
            || interfaceId == type(IERC6551Executable).interfaceId;
    }

    /// @notice The NFT this account is bound to.
    /// @dev Read out of the ERC-1167 proxy's appended footer at offset 0x4d, per ERC-6551.
    function token() public view virtual override returns (uint256, address, uint256) {
        bytes memory footer = new bytes(0x60);
        assembly {
            extcodecopy(address(), add(footer, 0x20), 0x4d, 0x60)
        }
        return abi.decode(footer, (uint256, address, uint256));
    }

    /// @notice The current owner of the bound NFT — i.e. whoever controls this wallet right now.
    function owner() public view virtual returns (address) {
        (uint256 chainId, address tokenContract, uint256 tokenId) = token();
        if (chainId != block.chainid) return address(0);
        return IERC721(tokenContract).ownerOf(tokenId);
    }

    function _isValidSigner(address signer) internal view virtual returns (bool) {
        return signer == owner();
    }
}
