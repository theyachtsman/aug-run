// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

/// @title RevenueSplitter — the 60/20/20 that every protocol fee lands in
/// @notice 60% funds the Drop, 20% goes to $AUG stakers, 20% to $AUG liquidity providers. Applies
///         identically to Black Market fees and to external ERC-2981 royalties.
/// @dev Two intake paths, because royalties arrive differently from fees:
///
///      - `deposit()` — the Black Market calls this and the amount is split immediately.
///      - `sync()` — external marketplaces paying an ERC-2981 royalty just *transfer* tokens or ETH
///        to the receiver address; they never call a function. So anything that shows up
///        unaccounted is swept into the split by `sync()`, which anyone may call.
///
///      Balances accrue per (asset, bucket) and are claimed by the phase-5 Terminal and phase-8 Drop
///      once those exist. Nothing is lost in the meantime — it accrues here and stays claimable.
contract RevenueSplitter is Ownable {
    using SafeERC20 for IERC20;

    enum Bucket {
        Drop, // 60% — becomes real-world assets in Stock//Runner wallets
        Stakers, // 20% — $AUG staked at the Terminal
        Lps // 20% — $AUG liquidity providers

    }

    uint256 public constant DROP_BPS = 6000;
    uint256 public constant STAKERS_BPS = 2000;
    uint256 public constant LPS_BPS = 2000;
    uint256 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Sentinel asset id for native ETH.
    address public constant ETH = address(0);

    /// @notice Claimable balance per asset per bucket.
    mapping(address asset => mapping(Bucket bucket => uint256 amount)) public accrued;

    /// @notice Sum of unclaimed `accrued` per asset. Anything held beyond this is unaccounted.
    mapping(address asset => uint256 amount) public pending;

    /// @notice Lifetime total split per asset, for reporting.
    mapping(address asset => uint256 amount) public lifetimeReceived;

    /// @notice Who may claim each bucket. Wired as phases 5 and 8 land.
    mapping(Bucket bucket => address recipient) public recipientOf;

    event Split(address indexed asset, uint256 amount, uint256 toDrop, uint256 toStakers, uint256 toLps);
    event Claimed(address indexed asset, Bucket indexed bucket, address indexed to, uint256 amount);
    event RecipientUpdated(Bucket indexed bucket, address indexed recipient);

    error NothingToSync();
    error NothingToClaim();
    error NoRecipient();
    error NotRecipient();
    error ZeroAddress();

    constructor() Ownable(msg.sender) {}

    /// @dev Accepts royalty payments made in native ETH. Left unaccounted until `sync(ETH)` runs, so
    ///      a marketplace's transfer can never fail on gas here.
    receive() external payable {}

    /*//////////////////////////////////////////////////////////////
                                 INTAKE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pull `amount` of `asset` from the caller and split it. Used by the Black Market.
    function deposit(address asset, uint256 amount) external {
        if (amount == 0) revert NothingToSync();
        IERC20(asset).safeTransferFrom(msg.sender, address(this), amount);
        _split(asset, amount);
    }

    /// @notice Split anything sitting here that hasn't been accounted yet.
    /// @dev This is how ERC-2981 royalties get picked up: marketplaces transfer to this address
    ///      without calling anything. Permissionless — sweeping only ever moves value into the
    ///      buckets it was always destined for.
    function sync(address asset) external returns (uint256 amount) {
        amount = unaccounted(asset);
        if (amount == 0) revert NothingToSync();
        _split(asset, amount);
    }

    /// @notice Balance held but not yet split into buckets.
    function unaccounted(address asset) public view returns (uint256) {
        uint256 balance = asset == ETH ? address(this).balance : IERC20(asset).balanceOf(address(this));
        uint256 owed = pending[asset];
        return balance > owed ? balance - owed : 0;
    }

    /// @dev 60/20/20, with the rounding remainder going to LPs so the split is exact and lossless.
    function _split(address asset, uint256 amount) internal {
        uint256 toDrop = (amount * DROP_BPS) / BPS_DENOMINATOR;
        uint256 toStakers = (amount * STAKERS_BPS) / BPS_DENOMINATOR;
        uint256 toLps = amount - toDrop - toStakers;

        accrued[asset][Bucket.Drop] += toDrop;
        accrued[asset][Bucket.Stakers] += toStakers;
        accrued[asset][Bucket.Lps] += toLps;
        pending[asset] += amount;
        lifetimeReceived[asset] += amount;

        emit Split(asset, amount, toDrop, toStakers, toLps);
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    /// @notice Claim a bucket's accrued balance. Callable only by that bucket's wired recipient.
    function claim(address asset, Bucket bucket) external returns (uint256 amount) {
        address to = recipientOf[bucket];
        if (to == address(0)) revert NoRecipient();
        if (msg.sender != to) revert NotRecipient();

        amount = accrued[asset][bucket];
        if (amount == 0) revert NothingToClaim();

        accrued[asset][bucket] = 0;
        pending[asset] -= amount;

        if (asset == ETH) {
            Address.sendValue(payable(to), amount);
        } else {
            IERC20(asset).safeTransfer(to, amount);
        }

        emit Claimed(asset, bucket, to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Wire a bucket's recipient. The Terminal (phase 5) and the Drop (phase 8) claim here.
    function setRecipient(Bucket bucket, address recipient) external onlyOwner {
        if (recipient == address(0)) revert ZeroAddress();
        recipientOf[bucket] = recipient;
        emit RecipientUpdated(bucket, recipient);
    }

    /// @notice All three buckets for an asset, for the UI.
    function balances(address asset)
        external
        view
        returns (uint256 drop, uint256 stakers, uint256 lps, uint256 unsplit)
    {
        return (
            accrued[asset][Bucket.Drop],
            accrued[asset][Bucket.Stakers],
            accrued[asset][Bucket.Lps],
            unaccounted(asset)
        );
    }
}
