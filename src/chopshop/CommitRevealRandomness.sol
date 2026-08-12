// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IRandomnessSource} from "./IRandomnessSource.sol";

/// @notice Arbitrum's ArbSys precompile at 0x64.
/// @dev Needed because **Solidity's `block.number` on Arbitrum returns the L1 block number**, while
///      block hashes are indexed by L2 block number. Mixing the two silently produces a target that
///      can never be hashed. Found the hard way: the first deployment stored an L1 target (11,467,756)
///      against an L2 chain head of 99,642,594, so no request could ever resolve.
interface IArbSys {
    function arbBlockNumber() external view returns (uint256);
    function arbBlockHash(uint256 blockNumber) external view returns (bytes32);
}

/// @title CommitRevealRandomness — future-blockhash entropy
/// @notice A request fixes a target block a few blocks ahead. The result mixes the caller's seed
///         with that block's hash, which nobody can know at request time.
///
/// @dev **Why not `block.prevrandao`.** On this Orbit chain prevrandao is not entropy at all — the
///      mixHash is a structured Arbitrum L1-info encoding, byte-identical across hundreds of
///      consecutive blocks. Verified directly against the RPC. Anything relying on it is
///      predictable.
///
///      **The honest limitation.** A single sequencer produces the blocks, so in principle it could
///      influence the target hash. That is a real trust assumption and the reason this contract is
///      behind a swappable interface rather than baked into the Chop Shop. It is strictly better
///      than same-transaction pseudo-randomness, which the caller can simply compute and reject.
///
///      **The window is tight.** `blockhash` reaches back 256 blocks and this chain produces a block
///      roughly every 100ms — about 25 seconds. Resolution is therefore permissionless so a keeper
///      can do it, and anything not resolved in time is explicitly expired and refundable rather
///      than silently stuck.
contract CommitRevealRandomness is IRandomnessSource {
    /// @notice Blocks to wait before a request becomes resolvable.
    /// @dev Must be at least 1 so the target hash is genuinely unknown when the request is made.
    uint256 public constant REVEAL_DELAY = 2;

    /// @notice How long a request stays resolvable. Kept under the 256-block `blockhash` limit with
    ///         margin, since blocks here are ~100ms.
    uint256 public constant REVEAL_WINDOW = 200;

    /// @notice Arbitrum's ArbSys precompile address.
    address internal constant ARB_SYS = 0x0000000000000000000000000000000000000064;

    /// @dev L2 block number on Arbitrum, plain `block.number` elsewhere (and in tests).
    function _blockNumber() internal view returns (uint256) {
        if (ARB_SYS.code.length > 0) return IArbSys(ARB_SYS).arbBlockNumber();
        return block.number;
    }

    /// @dev L2 block hash on Arbitrum, plain `blockhash` elsewhere. MUST be paired with
    ///      `_blockNumber` — mixing L1 numbers with L2 hashes is what broke the first deployment.
    function _blockHash(uint256 n) internal view returns (bytes32) {
        if (ARB_SYS.code.length > 0) return IArbSys(ARB_SYS).arbBlockHash(n);
        return blockhash(n);
    }

    struct Request {
        address requester;
        bytes32 userSeed;
        uint256 targetBlock;
        bool exists;
    }

    mapping(uint256 requestId => Request) public requests;
    uint256 public nextRequestId = 1;

    event RandomnessRequested(uint256 indexed requestId, address indexed requester, uint256 targetBlock);

    error UnknownRequest();
    error NotReady();

    /// @inheritdoc IRandomnessSource
    function requestRandomness(bytes32 userSeed) external override returns (uint256 requestId) {
        requestId = nextRequestId++;
        requests[requestId] = Request({
            requester: msg.sender,
            userSeed: userSeed,
            targetBlock: _blockNumber() + REVEAL_DELAY,
            exists: true
        });
        emit RandomnessRequested(requestId, msg.sender, _blockNumber() + REVEAL_DELAY);
    }

    /// @inheritdoc IRandomnessSource
    function isReady(uint256 requestId) public view override returns (bool) {
        Request storage r = requests[requestId];
        if (!r.exists) return false;
        uint256 bn = _blockNumber();
        if (bn <= r.targetBlock) return false;
        if (bn > r.targetBlock + REVEAL_WINDOW) return false;
        // A zero hash means the block is out of range; treat it as unresolvable rather than
        // producing a "random" value that everyone could have predicted.
        return _blockHash(r.targetBlock) != bytes32(0);
    }

    /// @inheritdoc IRandomnessSource
    function isExpired(uint256 requestId) external view override returns (bool) {
        Request storage r = requests[requestId];
        if (!r.exists) return false;
        uint256 bn = _blockNumber();
        if (bn <= r.targetBlock) return false;
        if (bn > r.targetBlock + REVEAL_WINDOW) return true;
        return _blockHash(r.targetBlock) == bytes32(0);
    }

    /// @inheritdoc IRandomnessSource
    function randomness(uint256 requestId) external view override returns (uint256) {
        Request storage r = requests[requestId];
        if (!r.exists) revert UnknownRequest();
        if (!isReady(requestId)) revert NotReady();
        return uint256(keccak256(abi.encode(r.userSeed, _blockHash(r.targetBlock), requestId, r.requester)));
    }
}
