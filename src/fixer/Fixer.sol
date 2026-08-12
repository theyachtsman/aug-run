// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {ERC1155Holder} from "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {AUG} from "../tokens/AUG.sol";
import {StockRunner} from "../runner/StockRunner.sol";
import {Augments} from "../items/Augments.sol";
import {Weights} from "../items/Weights.sol";
import {BlackMarket} from "../market/BlackMarket.sol";
import {RevenueSplitter} from "../market/RevenueSplitter.sol";
import {ProtocolReserve} from "./ProtocolReserve.sol";

/// @title The Fixer — borrow against what you own
/// @notice Two products. Deposit a Stock//Runner and borrow $RUN from the Black Market pool, paying
///         an upfront rate in ETH pegged to the pool's current sell fee. Or deposit an unused
///         Augment and draw half its $AUG value at a fixed 25% APR from the protocol reserve.
///         Fall to 70% loan-to-value and you're **Iced**.
///
/// @dev His shop is where operators take on risk; the Terminal is where they step out of it.
///
///      **$RUN loans** draw from and repay into the Black Market's own pool rather than a separate
///      reserve, which keeps $RUN supply genuinely fixed and couples borrowing to the pool's price.
///      There is no accruing interest — the ETH rate is paid upfront and that is the whole cost.
///      LTV still drifts, because the pool's quote moves as units are bought and sold.
///
///      **$AUG loans** are funded from the protocol reserve. Interest accrues linearly at 25% APR
///      and is **burned** on repayment rather than banked — the reserve only ever gets its principal
///      back, so borrowing shrinks $AUG supply over time.
///
///      **Icing seizes control, not ownership.** An Iced position keeps its debt frozen and stays
///      redeemable by the borrower until the Fixer explicitly disposes of the collateral. That is
///      also the natural handoff to the Chop Shop in phase 7.
contract Fixer is Ownable, ReentrancyGuard, IERC721Receiver, ERC1155Holder {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Opening loan-to-value for both products: you draw half the collateral's value.
    uint256 public constant OPENING_LTV_BPS = 5000;

    /// @notice Fall to this loan-to-value and the position is Iced.
    uint256 public constant ICE_LTV_BPS = 7000;

    /// @notice Fixed 25% APR on $AUG loans. Simple (linear) interest, not compounding — an operator
    ///         should be able to read a position and know next week's number without a model.
    uint256 public constant AUG_APR_BPS = 2500;

    uint256 public constant BPS_DENOMINATOR = 10_000;
    uint256 public constant YEAR = 365 days;

    /// @notice Bounds on the term a borrower may set, in cycles.
    uint256 public constant MIN_TERM_CYCLES = 1;
    uint256 public constant MAX_TERM_CYCLES = 52;
    uint256 public constant CYCLE_LENGTH = 7 days;

    /*//////////////////////////////////////////////////////////////
                              IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 public immutable RUN_TOKEN;
    AUG public immutable AUG_TOKEN;
    StockRunner public immutable RUNNER;
    Augments public immutable AUGMENTS;
    BlackMarket public immutable MARKET;
    ProtocolReserve public immutable RESERVE;
    RevenueSplitter public immutable SPLITTER;

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    enum Status {
        None,
        Active,
        Iced,
        Closed
    }

    struct RunnerLoan {
        address borrower;
        uint256 tokenId;
        uint256 principal; // $RUN owed
        uint256 openedAt;
        uint256 dueAt;
        Status status;
    }

    struct AugmentLoan {
        address borrower;
        uint256 augmentId;
        uint256 collateralValue; // $AUG value of the Augment (its tier price)
        uint256 principal; // $AUG drawn
        uint256 openedAt;
        uint256 icedAt; // interest stops accruing here
        Status status;
    }

    mapping(uint256 loanId => RunnerLoan) public runnerLoans;
    mapping(uint256 loanId => AugmentLoan) public augmentLoans;

    uint256 public nextRunnerLoanId = 1;
    uint256 public nextAugmentLoanId = 1;

    uint256 public totalInterestBurned;

    event RunnerLoanOpened(
        uint256 indexed loanId,
        address indexed borrower,
        uint256 indexed tokenId,
        uint256 principal,
        uint256 ethFee,
        uint256 dueAt
    );
    event RunnerLoanRepaid(uint256 indexed loanId, address indexed borrower, uint256 principal);
    event AugmentLoanOpened(
        uint256 indexed loanId, address indexed borrower, uint256 indexed augmentId, uint256 principal
    );
    event AugmentLoanRepaid(
        uint256 indexed loanId, address indexed borrower, uint256 principal, uint256 interestBurned
    );
    event Iced(bool indexed isRunnerLoan, uint256 indexed loanId, uint256 ltvBps);
    event CollateralDisposed(bool indexed isRunnerLoan, uint256 indexed loanId, address to);

    error NotBorrower();
    error LoanNotActive();
    error LoanNotIced();
    error NotIceable(uint256 ltvBps);
    error BadTerm();
    error InsufficientEthFee(uint256 required, uint256 sent);
    error AugmentNotInCatalog();
    error ZeroAddress();
    error NothingToBorrow();

    constructor(
        address runToken,
        address augToken,
        address runner_,
        address augments_,
        address market_,
        address reserve_,
        address splitter_
    ) Ownable(msg.sender) {
        if (
            runToken == address(0) || augToken == address(0) || runner_ == address(0)
                || augments_ == address(0) || market_ == address(0) || reserve_ == address(0)
                || splitter_ == address(0)
        ) revert ZeroAddress();

        RUN_TOKEN = IERC20(runToken);
        AUG_TOKEN = AUG(augToken);
        RUNNER = StockRunner(runner_);
        AUGMENTS = Augments(augments_);
        MARKET = BlackMarket(market_);
        RESERVE = ProtocolReserve(reserve_);
        SPLITTER = RevenueSplitter(payable(splitter_));
    }

    /*//////////////////////////////////////////////////////////////
                    $RUN LOANS AGAINST A STOCK//RUNNER
    //////////////////////////////////////////////////////////////*/

    /// @notice What a Runner loan would look like right now.
    /// @return principal $RUN lent, `ethFee` the upfront rate in wei, `collateralValue` the pool quote.
    function quoteRunnerLoan()
        public
        view
        returns (uint256 principal, uint256 ethFee, uint256 collateralValue)
    {
        collateralValue = MARKET.quoteSell();
        principal = (collateralValue * OPENING_LTV_BPS) / BPS_DENOMINATOR;

        // "Pay an upfront rate in ETH pegged to the Black Market's current sell fee" — the same
        // 25/15/10 tier that a sale would pay, applied to the loan's value in ETH.
        uint256 principalInWei = (principal * MARKET.priceOracle().ethPerRun()) / 1e18;
        ethFee = (principalInWei * MARKET.sellFeeBps()) / BPS_DENOMINATOR;
    }

    /// @notice Deposit a Stock//Runner and borrow $RUN against it.
    /// @param tokenId The unit to pledge. Caller must have approved this contract for it.
    /// @param termCycles Loan term, in weekly cycles.
    function borrowAgainstRunner(uint256 tokenId, uint256 termCycles)
        external
        payable
        nonReentrant
        returns (uint256 loanId)
    {
        if (termCycles < MIN_TERM_CYCLES || termCycles > MAX_TERM_CYCLES) revert BadTerm();
        if (RUNNER.ownerOf(tokenId) != msg.sender) revert NotBorrower();

        (uint256 principal, uint256 ethFee,) = quoteRunnerLoan();
        if (principal == 0) revert NothingToBorrow();
        if (msg.value < ethFee) revert InsufficientEthFee(ethFee, msg.value);

        loanId = nextRunnerLoanId++;
        runnerLoans[loanId] = RunnerLoan({
            borrower: msg.sender,
            tokenId: tokenId,
            principal: principal,
            openedAt: block.timestamp,
            dueAt: block.timestamp + (termCycles * CYCLE_LENGTH),
            status: Status.Active
        });

        RUNNER.safeTransferFrom(msg.sender, address(this), tokenId);

        // The upfront rate is protocol revenue and splits 60/20/20 like every other fee.
        if (ethFee > 0) Address.sendValue(payable(address(SPLITTER)), ethFee);
        // Return any overpayment rather than keeping it.
        if (msg.value > ethFee) Address.sendValue(payable(msg.sender), msg.value - ethFee);

        MARKET.lendRun(msg.sender, principal);

        emit RunnerLoanOpened(
            loanId, msg.sender, tokenId, principal, ethFee, runnerLoans[loanId].dueAt
        );
    }

    /// @notice Repay a Runner loan and get the unit back. Works while Active or Iced.
    function repayRunnerLoan(uint256 loanId) external nonReentrant {
        RunnerLoan storage loan = runnerLoans[loanId];
        if (loan.status != Status.Active && loan.status != Status.Iced) revert LoanNotActive();
        if (loan.borrower != msg.sender) revert NotBorrower();

        loan.status = Status.Closed;

        // Principal goes straight back into the pool it came from.
        RUN_TOKEN.safeTransferFrom(msg.sender, address(this), loan.principal);
        IERC20(address(RUN_TOKEN)).forceApprove(address(MARKET), loan.principal);
        MARKET.repayRun(loan.principal);

        RUNNER.safeTransferFrom(address(this), msg.sender, loan.tokenId);
        emit RunnerLoanRepaid(loanId, msg.sender, loan.principal);
    }

    /// @notice Current loan-to-value of a Runner loan, in basis points.
    /// @dev The pool's quote moves as units are bought and sold, so LTV drifts without the borrower
    ///      doing anything. That is the risk the ETH rate is priced for.
    function runnerLoanLtvBps(uint256 loanId) public view returns (uint256) {
        RunnerLoan storage loan = runnerLoans[loanId];
        if (loan.status == Status.None || loan.status == Status.Closed) return 0;
        uint256 value = MARKET.quoteSell();
        if (value == 0) return type(uint256).max;
        return (loan.principal * BPS_DENOMINATOR) / value;
    }

    function isRunnerLoanIceable(uint256 loanId) public view returns (bool) {
        RunnerLoan storage loan = runnerLoans[loanId];
        if (loan.status != Status.Active) return false;
        return runnerLoanLtvBps(loanId) >= ICE_LTV_BPS || block.timestamp > loan.dueAt;
    }

    /*//////////////////////////////////////////////////////////////
                   $AUG LOANS AGAINST AN UNUSED AUGMENT
    //////////////////////////////////////////////////////////////*/

    /// @notice Borrow $AUG against a loose (never-seated) Augment.
    /// @dev Only unseated Augments exist as ERC-1155 balances at all — seating burns the token — so
    ///      "unused" is enforced structurally by requiring a transferable balance.
    function borrowAgainstAugment(uint256 augmentId) external nonReentrant returns (uint256 loanId) {
        if (!AUGMENTS.exists(augmentId)) revert AugmentNotInCatalog();

        uint256 collateralValue = Weights.tierPrice(AUGMENTS.tierOf(augmentId));
        uint256 principal = (collateralValue * OPENING_LTV_BPS) / BPS_DENOMINATOR;

        loanId = nextAugmentLoanId++;
        augmentLoans[loanId] = AugmentLoan({
            borrower: msg.sender,
            augmentId: augmentId,
            collateralValue: collateralValue,
            principal: principal,
            openedAt: block.timestamp,
            icedAt: 0,
            status: Status.Active
        });

        AUGMENTS.safeTransferFrom(msg.sender, address(this), augmentId, 1, "");
        RESERVE.lend(msg.sender, principal);

        emit AugmentLoanOpened(loanId, msg.sender, augmentId, principal);
    }

    /// @notice Total $AUG owed on an Augment loan: principal plus linear 25% APR interest.
    function augmentLoanDebt(uint256 loanId) public view returns (uint256) {
        AugmentLoan storage loan = augmentLoans[loanId];
        if (loan.status == Status.None || loan.status == Status.Closed) return 0;
        return loan.principal + augmentLoanInterest(loanId);
    }

    /// @notice Interest accrued so far. Stops at the moment of icing.
    function augmentLoanInterest(uint256 loanId) public view returns (uint256) {
        AugmentLoan storage loan = augmentLoans[loanId];
        if (loan.status == Status.None || loan.status == Status.Closed) return 0;
        uint256 endsAt = loan.icedAt == 0 ? block.timestamp : loan.icedAt;
        uint256 elapsed = endsAt - loan.openedAt;
        return (loan.principal * AUG_APR_BPS * elapsed) / (BPS_DENOMINATOR * YEAR);
    }

    /// @notice Current loan-to-value of an Augment loan, in basis points.
    /// @dev The collateral's $AUG value is fixed by its tier, so LTV rises purely as interest
    ///      accrues: 50% at open, reaching the 70% ice threshold after about 1.6 years at 25% APR.
    function augmentLoanLtvBps(uint256 loanId) public view returns (uint256) {
        AugmentLoan storage loan = augmentLoans[loanId];
        if (loan.status == Status.None || loan.status == Status.Closed) return 0;
        return (augmentLoanDebt(loanId) * BPS_DENOMINATOR) / loan.collateralValue;
    }

    function isAugmentLoanIceable(uint256 loanId) public view returns (bool) {
        if (augmentLoans[loanId].status != Status.Active) return false;
        return augmentLoanLtvBps(loanId) >= ICE_LTV_BPS;
    }

    /// @notice Repay an Augment loan and reclaim the Augment. Works while Active or Iced.
    /// @dev Principal returns to the reserve; **interest is burned**, so borrowing permanently
    ///      shrinks $AUG supply rather than accumulating anywhere.
    function repayAugmentLoan(uint256 loanId) external nonReentrant {
        AugmentLoan storage loan = augmentLoans[loanId];
        if (loan.status != Status.Active && loan.status != Status.Iced) revert LoanNotActive();
        if (loan.borrower != msg.sender) revert NotBorrower();

        uint256 interest = augmentLoanInterest(loanId);
        uint256 principal = loan.principal;
        loan.status = Status.Closed;

        IERC20(address(AUG_TOKEN)).safeTransferFrom(msg.sender, address(this), principal + interest);

        IERC20(address(AUG_TOKEN)).forceApprove(address(RESERVE), principal);
        RESERVE.repay(principal);

        if (interest > 0) {
            AUG_TOKEN.burn(interest);
            totalInterestBurned += interest;
        }

        AUGMENTS.safeTransferFrom(address(this), msg.sender, loan.augmentId, 1, "");
        emit AugmentLoanRepaid(loanId, msg.sender, principal, interest);
    }

    /*//////////////////////////////////////////////////////////////
                                 ICING
    //////////////////////////////////////////////////////////////*/

    /// @notice Ice a Runner loan that has hit 70% LTV or run past its term.
    /// @dev Permissionless. Icing freezes the position; it does not sell anything. The borrower can
    ///      still repay and redeem right up until the collateral is disposed of.
    function iceRunnerLoan(uint256 loanId) external {
        if (!isRunnerLoanIceable(loanId)) revert NotIceable(runnerLoanLtvBps(loanId));
        runnerLoans[loanId].status = Status.Iced;
        emit Iced(true, loanId, runnerLoanLtvBps(loanId));
    }

    /// @notice Ice an Augment loan that has hit 70% LTV.
    function iceAugmentLoan(uint256 loanId) external {
        if (!isAugmentLoanIceable(loanId)) revert NotIceable(augmentLoanLtvBps(loanId));
        AugmentLoan storage loan = augmentLoans[loanId];
        loan.status = Status.Iced;
        loan.icedAt = block.timestamp; // interest stops here
        emit Iced(false, loanId, augmentLoanLtvBps(loanId));
    }

    /// @notice Dispose of Iced Runner collateral into the Black Market pool.
    /// @dev Deliberately a separate, owner-gated step rather than automatic on icing, so a brief
    ///      price dip doesn't cost an operator their unit with no chance to react. Phase 7 can route
    ///      this to the Chop Shop instead.
    function disposeRunnerCollateral(uint256 loanId) external onlyOwner nonReentrant {
        RunnerLoan storage loan = runnerLoans[loanId];
        if (loan.status != Status.Iced) revert LoanNotIced();
        loan.status = Status.Closed;
        RUNNER.safeTransferFrom(address(this), address(MARKET), loan.tokenId);
        emit CollateralDisposed(true, loanId, address(MARKET));
    }

    /// @notice Dispose of Iced Augment collateral into the protocol reserve.
    function disposeAugmentCollateral(uint256 loanId) external onlyOwner nonReentrant {
        AugmentLoan storage loan = augmentLoans[loanId];
        if (loan.status != Status.Iced) revert LoanNotIced();
        loan.status = Status.Closed;
        AUGMENTS.safeTransferFrom(address(this), address(RESERVE), loan.augmentId, 1, "");
        emit CollateralDisposed(false, loanId, address(RESERVE));
    }

    /*//////////////////////////////////////////////////////////////
                                 MISC
    //////////////////////////////////////////////////////////////*/

    function onERC721Received(address, address, uint256, bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        return IERC721Receiver.onERC721Received.selector;
    }

    receive() external payable {}
}
