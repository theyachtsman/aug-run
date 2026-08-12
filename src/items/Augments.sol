// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ERC1155} from "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Augments — ERC-1155 items, each bound to one real-world asset ticker
/// @notice Twelve at launch, one ticker each, across three tiers. A bay holds exactly one.
/// @dev **The catalog is designed to expand.** `addAugment` appends new entries at runtime, so
///      listing more RWAs on Robinhood Chain never requires redeploying this contract or touching
///      weight math — weight is a function of tier alone (see Weights.sol), and the bay ceiling and
///      Drop allocation are both catalog-size agnostic.
///
///      Only the Ripperdoc may mint or burn. Loose Augments (bought, never seated) are ordinary
///      transferable ERC-1155 balances. Seating BURNS the token — which is what makes binding
///      absolute, since a seated Augment no longer exists as a movable asset.
contract Augments is ERC1155, Ownable {
    struct AugmentDef {
        string ticker;
        uint8 tier; // 1, 2 or 3
        bool exists;
    }

    mapping(uint256 id => AugmentDef) private _defs;

    /// @notice Number of Augments in the catalog. IDs run 1..augmentCount.
    uint256 public augmentCount;

    /// @notice The Ripperdoc. The only address permitted to mint or burn.
    address public ripperdoc;

    /// @notice True only on testnet deployments. Allows the Ripperdoc to be re-pointed.
    bool public immutable TESTNET;

    event AugmentAdded(uint256 indexed id, string ticker, uint8 tier);
    event RipperdocUpdated(address indexed ripperdoc);

    error NotRipperdoc();
    error UnknownAugment(uint256 id);
    error InvalidTier();
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

    /// @notice Append an Augment to the catalog. Extensible by design — see the contract notice.
    function addAugment(string calldata ticker, uint8 tier) external onlyOwner returns (uint256 id) {
        if (tier == 0 || tier > 3) revert InvalidTier();
        id = ++augmentCount;
        _defs[id] = AugmentDef({ticker: ticker, tier: tier, exists: true});
        emit AugmentAdded(id, ticker, tier);
    }

    /// @notice Wire up the Ripperdoc.
    /// @dev Strictly set-once on mainnet: this address can mint Augments freely. Re-pointable by the
    ///      owner on testnet only, so later phases can swap the Ripperdoc without a fresh catalog.
    function setRipperdoc(address ripperdoc_) external onlyOwner {
        if (ripperdoc_ == address(0)) revert ZeroAddress();
        if (ripperdoc != address(0) && !TESTNET) revert RipperdocAlreadySet();
        ripperdoc = ripperdoc_;
        emit RipperdocUpdated(ripperdoc_);
    }

    function mint(address to, uint256 id, uint256 amount) external onlyRipperdoc {
        if (!_defs[id].exists) revert UnknownAugment(id);
        _mint(to, id, amount, "");
    }

    function burn(address from, uint256 id, uint256 amount) external onlyRipperdoc {
        _burn(from, id, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function tierOf(uint256 id) external view returns (uint8) {
        AugmentDef storage d = _defs[id];
        if (!d.exists) revert UnknownAugment(id);
        return d.tier;
    }

    function tickerOf(uint256 id) external view returns (string memory) {
        AugmentDef storage d = _defs[id];
        if (!d.exists) revert UnknownAugment(id);
        return d.ticker;
    }

    function getAugment(uint256 id) external view returns (AugmentDef memory) {
        AugmentDef storage d = _defs[id];
        if (!d.exists) revert UnknownAugment(id);
        return d;
    }

    function exists(uint256 id) external view returns (bool) {
        return _defs[id].exists;
    }

    /// @notice The whole catalog, for the UI shopfront.
    function catalog() external view returns (AugmentDef[] memory defs) {
        uint256 n = augmentCount;
        defs = new AugmentDef[](n);
        for (uint256 i = 0; i < n; i++) {
            defs[i] = _defs[i + 1];
        }
    }
}
