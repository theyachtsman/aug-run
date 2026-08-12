// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {RevenueSplitter} from "../market/RevenueSplitter.sol";

/// @title The Terminal — a wall-mounted kiosk on Runners Row, no vendor, no negotiation
/// @notice Stake $AUG for a cut of protocol revenue, or provide $AUG liquidity for the same. The
///         20%/20% staker and LP shares of every fee split are claimed here.
/// @dev Deliberately unstaffed: no owner action is needed for revenue to reach stakers.
///      `pullRewards()` is permissionless — anyone can push accrued fees out of the splitter and
///      into the two streams. Staking isn't a transaction with anyone, so it gets a machine.
///
///      **Two pools, one contract.** Pool A takes $AUG and earns the Stakers bucket; pool B takes an
///      LP token and earns the LPs bucket. The LP token address is settable because no DEX exists on
///      this chain yet — see `setLpToken`.
///
///      **Rewards stream over one cycle rather than landing in a lump.** Revenue reaches the
///      splitter continuously but is claimed in discrete chunks, so paying a chunk out instantly
///      would let someone stake immediately before the claim, take a share of the whole amount, and
///      unstake straight after. Streaming makes that worthless: you earn only for the seconds you
///      were actually staked. Staking, unstaking and claiming all stay available at any time — the
///      stream governs accrual rate, never access to funds.
contract Terminal is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Rewards pay out across one cycle, matching the Drop's weekly clock.
    uint256 public constant REWARD_DURATION = 7 days;

    /// @notice Staked in pool A.
    IERC20 public immutable AUG_TOKEN;

    /// @notice The asset rewards are paid in. Every Black Market fee is denominated in $RUN.
    IERC20 public immutable REWARD_TOKEN;

    RevenueSplitter public immutable SPLITTER;

    /// @notice Staked in pool B. Zero until a real $AUG liquidity pair exists.
    IERC20 public lpToken;

    struct Pool {
        uint256 totalStaked;
        uint256 rewardRate; // reward tokens per second
        uint256 periodFinish; // when the current stream ends
        uint256 lastUpdateTime;
        uint256 rewardPerTokenStored; // 1e18 fixed point
        uint256 queued; // revenue that arrived while nothing was staked
        uint256 lifetimeRewards;
        mapping(address account => uint256) balanceOf;
        mapping(address account => uint256) userRewardPerTokenPaid;
        mapping(address account => uint256) rewards;
    }

    Pool private _augPool;
    Pool private _lpPool;

    event Staked(address indexed account, bool indexed isLp, uint256 amount);
    event Withdrawn(address indexed account, bool indexed isLp, uint256 amount);
    event RewardPaid(address indexed account, bool indexed isLp, uint256 amount);
    event RewardStreamStarted(bool indexed isLp, uint256 amount, uint256 rate, uint256 periodFinish);
    event RewardQueued(bool indexed isLp, uint256 amount, uint256 totalQueued);
    event LpTokenUpdated(address indexed lpToken);

    error ZeroAmount();
    error InsufficientStake();
    error LpTokenNotSet();
    error ZeroAddress();
    error NothingPulled();

    constructor(address aug, address rewardToken, address splitter) Ownable(msg.sender) {
        if (aug == address(0) || rewardToken == address(0) || splitter == address(0)) {
            revert ZeroAddress();
        }
        AUG_TOKEN = IERC20(aug);
        REWARD_TOKEN = IERC20(rewardToken);
        SPLITTER = RevenueSplitter(payable(splitter));
    }

    function _pool(bool isLp) private view returns (Pool storage) {
        return isLp ? _lpPool : _augPool;
    }

    /*//////////////////////////////////////////////////////////////
                             REWARD MATH
    //////////////////////////////////////////////////////////////*/

    function _lastTimeRewardApplicable(Pool storage p) private view returns (uint256) {
        return block.timestamp < p.periodFinish ? block.timestamp : p.periodFinish;
    }

    function _rewardPerToken(Pool storage p) private view returns (uint256) {
        if (p.totalStaked == 0) return p.rewardPerTokenStored;
        uint256 elapsed = _lastTimeRewardApplicable(p) - p.lastUpdateTime;
        return p.rewardPerTokenStored + ((elapsed * p.rewardRate * 1e18) / p.totalStaked);
    }

    function _earned(Pool storage p, address account) private view returns (uint256) {
        uint256 delta = _rewardPerToken(p) - p.userRewardPerTokenPaid[account];
        return p.rewards[account] + ((p.balanceOf[account] * delta) / 1e18);
    }

    /// @dev Settle accrual up to now before any balance or rate change.
    function _updateReward(Pool storage p, address account) private {
        p.rewardPerTokenStored = _rewardPerToken(p);
        p.lastUpdateTime = _lastTimeRewardApplicable(p);
        if (account != address(0)) {
            p.rewards[account] = _earned(p, account);
            p.userRewardPerTokenPaid[account] = p.rewardPerTokenStored;
        }
    }

    /*//////////////////////////////////////////////////////////////
                                STAKING
    //////////////////////////////////////////////////////////////*/

    /// @notice Stake $AUG (isLp false) or LP tokens (isLp true). No lock — withdraw any time.
    function stake(bool isLp, uint256 amount) external nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Pool storage p = _pool(isLp);
        IERC20 token = _stakeToken(isLp);

        // Sweep before the stake lands, so anything that arrived while the pool was empty is
        // already queued and the _flushQueued below starts it against this very stake.
        _sweepSplitter();
        _updateReward(p, msg.sender);

        token.safeTransferFrom(msg.sender, address(this), amount);
        p.totalStaked += amount;
        p.balanceOf[msg.sender] += amount;

        // Revenue that arrived while the pool was empty starts streaming now that it isn't.
        _flushQueued(p, isLp);

        emit Staked(msg.sender, isLp, amount);
    }

    /// @notice Withdraw staked tokens at any time. Accrued rewards are left claimable.
    function withdraw(bool isLp, uint256 amount) public nonReentrant {
        if (amount == 0) revert ZeroAmount();
        Pool storage p = _pool(isLp);
        if (p.balanceOf[msg.sender] < amount) revert InsufficientStake();

        _sweepSplitter();
        _updateReward(p, msg.sender);

        p.totalStaked -= amount;
        p.balanceOf[msg.sender] -= amount;
        _stakeToken(isLp).safeTransfer(msg.sender, amount);

        emit Withdrawn(msg.sender, isLp, amount);
    }

    /// @notice Claim accrued rewards at any time, without touching the stake.
    function claim(bool isLp) public nonReentrant returns (uint256 reward) {
        Pool storage p = _pool(isLp);

        _sweepSplitter();
        _updateReward(p, msg.sender);

        reward = p.rewards[msg.sender];
        if (reward == 0) return 0;

        p.rewards[msg.sender] = 0;
        REWARD_TOKEN.safeTransfer(msg.sender, reward);
        emit RewardPaid(msg.sender, isLp, reward);
    }

    /// @notice Withdraw the entire stake and claim everything owed, in one transaction.
    function exit(bool isLp) external {
        uint256 balance = _pool(isLp).balanceOf[msg.sender];
        if (balance > 0) withdraw(isLp, balance);
        claim(isLp);
    }

    function _stakeToken(bool isLp) private view returns (IERC20) {
        if (!isLp) return AUG_TOKEN;
        if (address(lpToken) == address(0)) revert LpTokenNotSet();
        return lpToken;
    }

    /*//////////////////////////////////////////////////////////////
                          REVENUE INTAKE
    //////////////////////////////////////////////////////////////*/

    /// @notice Pull whatever the splitter owes this contract and start streaming it.
    /// @dev Kept external for keepers and monitoring, but no operator is expected to call it: every
    ///      staking entrypoint sweeps first, so revenue reaches the streams as a side effect of
    ///      ordinary use. Reverts when there is nothing to move so a keeper gets a clear signal;
    ///      the internal sweep is silent for the same case.
    function pullRewards() external nonReentrant returns (uint256 stakerAmount, uint256 lpAmount) {
        (stakerAmount, lpAmount) = _sweepSplitter();
        if (stakerAmount == 0 && lpAmount == 0) revert NothingPulled();
    }

    /// @dev Moves both earmarked buckets out of the splitter and into the streams. Silent when
    ///      there is nothing waiting, so it can sit at the top of every entrypoint without turning
    ///      an ordinary stake into a revert. Claiming from the splitter only ever moves value to
    ///      the address it was already earmarked for, so there is nothing to authorise.
    function _sweepSplitter() private returns (uint256 stakerAmount, uint256 lpAmount) {
        address asset = address(REWARD_TOKEN);

        if (SPLITTER.accrued(asset, RevenueSplitter.Bucket.Stakers) > 0) {
            stakerAmount = SPLITTER.claim(asset, RevenueSplitter.Bucket.Stakers);
            _notify(_augPool, false, stakerAmount);
        }
        if (SPLITTER.accrued(asset, RevenueSplitter.Bucket.Lps) > 0) {
            lpAmount = SPLITTER.claim(asset, RevenueSplitter.Bucket.Lps);
            _notify(_lpPool, true, lpAmount);
        }
    }

    /// @dev Starts or extends a stream. If nothing is staked the amount is held aside rather than
    ///      streamed into an empty pool, where it would be irrecoverable.
    function _notify(Pool storage p, bool isLp, uint256 amount) private {
        if (amount == 0) return;
        p.lifetimeRewards += amount;

        if (p.totalStaked == 0) {
            p.queued += amount;
            emit RewardQueued(isLp, amount, p.queued);
            return;
        }

        _updateReward(p, address(0));

        if (block.timestamp >= p.periodFinish) {
            p.rewardRate = amount / REWARD_DURATION;
        } else {
            // Roll whatever is left of the current stream into the new one.
            uint256 leftover = (p.periodFinish - block.timestamp) * p.rewardRate;
            p.rewardRate = (amount + leftover) / REWARD_DURATION;
        }

        p.lastUpdateTime = block.timestamp;
        p.periodFinish = block.timestamp + REWARD_DURATION;
        emit RewardStreamStarted(isLp, amount, p.rewardRate, p.periodFinish);
    }

    function _flushQueued(Pool storage p, bool isLp) private {
        uint256 q = p.queued;
        if (q == 0 || p.totalStaked == 0) return;
        p.queued = 0;
        p.lifetimeRewards -= q; // _notify re-adds it
        _notify(p, isLp, q);
    }

    /*//////////////////////////////////////////////////////////////
                                 VIEWS
    //////////////////////////////////////////////////////////////*/

    function earned(address account, bool isLp) external view returns (uint256) {
        return _earned(_pool(isLp), account);
    }

    function stakedBalance(address account, bool isLp) external view returns (uint256) {
        return _pool(isLp).balanceOf[account];
    }

    function totalStaked(bool isLp) external view returns (uint256) {
        return _pool(isLp).totalStaked;
    }

    function rewardRate(bool isLp) external view returns (uint256) {
        return _pool(isLp).rewardRate;
    }

    function periodFinish(bool isLp) external view returns (uint256) {
        return _pool(isLp).periodFinish;
    }

    function queuedRewards(bool isLp) external view returns (uint256) {
        return _pool(isLp).queued;
    }

    function lifetimeRewards(bool isLp) external view returns (uint256) {
        return _pool(isLp).lifetimeRewards;
    }

    /// @notice Reward tokens still to be paid out in the current stream.
    function remainingRewards(bool isLp) external view returns (uint256) {
        Pool storage p = _pool(isLp);
        if (block.timestamp >= p.periodFinish) return 0;
        return (p.periodFinish - block.timestamp) * p.rewardRate;
    }

    /// @notice Everything the UI needs for one pool, in a single call.
    function poolInfo(bool isLp, address account)
        external
        view
        returns (
            uint256 staked,
            uint256 total,
            uint256 pending,
            uint256 rate,
            uint256 finish,
            uint256 queued
        )
    {
        Pool storage p = _pool(isLp);
        return (
            p.balanceOf[account],
            p.totalStaked,
            _earned(p, account),
            p.rewardRate,
            p.periodFinish,
            p.queued
        );
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Point pool B at the real $AUG liquidity token.
    /// @dev Robinhood Chain has no DEX yet, so this starts unset. It expects a **fungible ERC-20**
    ///      LP token — a Uniswap-V2-style pair, which is what launchpads typically mint. A Uniswap
    ///      V3 position is an ERC-721 with a price range and is NOT stakeable here; that would need
    ///      a separate staker that values each position individually.
    ///
    ///      Only settable while pool B is empty, so nobody's stake can be stranded behind a swap.
    function setLpToken(address lpToken_) external onlyOwner {
        if (lpToken_ == address(0)) revert ZeroAddress();
        if (_lpPool.totalStaked != 0) revert InsufficientStake();
        lpToken = IERC20(lpToken_);
        emit LpTokenUpdated(lpToken_);
    }
}
