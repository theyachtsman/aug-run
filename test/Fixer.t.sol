// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RUN} from "../src/tokens/RUN.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";
import {Augments} from "../src/items/Augments.sol";
import {ExpansionModules} from "../src/items/ExpansionModules.sol";
import {Ripperdoc} from "../src/items/Ripperdoc.sol";
import {BlackMarket} from "../src/market/BlackMarket.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {TestnetRunPriceOracle} from "../src/market/TestnetRunPriceOracle.sol";
import {ProtocolReserve} from "../src/fixer/ProtocolReserve.sol";
import {Fixer} from "../src/fixer/Fixer.sol";
import {ERC6551RegistryFixture} from "./helpers/ERC6551RegistryFixture.sol";

contract FixerTest is Test {
    RUN internal runToken;
    AUG internal aug;
    StockRunner internal runner;
    Augments internal augments;
    ExpansionModules internal modules;
    Ripperdoc internal doc;
    BlackMarket internal market;
    RevenueSplitter internal splitter;
    TestnetRunPriceOracle internal oracle;
    ProtocolReserve internal reserve;
    Fixer internal fixer;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant INITIAL_SPOT = 1_000_000e18;
    uint256 constant DELTA = 25_000e18;
    uint256 constant MIN_SPOT = 100_000e18;
    uint256 constant ETH_PER_RUN = 1e12; // 1,000,000 $RUN ~ 1 ETH

    uint256 constant T1_SPY = 1;
    uint256 constant T3_NVDA = 9;

    function setUp() public {
        vm.warp(1786147200);

        address registry = ERC6551RegistryFixture.install();
        ERC6551Account impl = new ERC6551Account();

        runToken = new RUN(address(this), true);
        aug = new AUG(address(this), address(this), address(this), true);
        splitter = new RevenueSplitter();
        oracle = new TestnetRunPriceOracle(ETH_PER_RUN);

        runner = new StockRunner(address(runToken), registry, address(impl), address(this), true);
        augments = new Augments("uri", true);
        modules = new ExpansionModules("uri", true);
        doc = new Ripperdoc(address(aug), address(runner), address(augments), address(modules), address(this));
        runner.setRipperdoc(address(doc));
        runner.openMinting();
        augments.setRipperdoc(address(doc));
        modules.setRipperdoc(address(doc));
        augments.addAugment("SPY", 1);
        for (uint256 i = 0; i < 7; i++) augments.addAugment("FILL", 1);
        augments.addAugment("NVDA", 3);

        market = new BlackMarket(
            address(runToken), address(runner), address(splitter), address(oracle),
            INITIAL_SPOT, DELTA, MIN_SPOT
        );
        runner.setTreasury(address(market));

        reserve = new ProtocolReserve(address(aug));
        fixer = new Fixer(
            address(runToken), address(aug), address(runner), address(augments),
            address(market), address(reserve), address(splitter)
        );

        market.setFixer(address(fixer));
        reserve.setFixer(address(fixer));
        aug.transfer(address(reserve), 1_000_000e18);

        _fund(alice);
        _fund(bob);
    }

    function _fund(address who) internal {
        runToken.transfer(who, 60_000_000e18);
        aug.transfer(who, 1_000_000e18);
        vm.deal(who, 100 ether);
        vm.startPrank(who);
        runToken.approve(address(market), type(uint256).max);
        runToken.approve(address(fixer), type(uint256).max);
        aug.approve(address(doc), type(uint256).max);
        aug.approve(address(fixer), type(uint256).max);
        runner.setApprovalForAll(address(fixer), true);
        runner.setApprovalForAll(address(market), true);
        augments.setApprovalForAll(address(fixer), true);
        vm.stopPrank();
    }

    function _activate(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = market.activateGenesis();
    }

    /// @dev Push the pool quote down by selling units in, which is what drags a Runner loan's LTV up.
    function _pushPriceDown(uint256 sales) internal {
        for (uint256 i = 0; i < sales; i++) {
            uint256 id = _activate(bob);
            vm.prank(bob);
            market.sell(id, 0);
        }
    }

    /*//////////////////////////////////////////////////////////////
                        $RUN LOANS — QUOTE & OPEN
    //////////////////////////////////////////////////////////////*/

    function test_quote_isHalfThePoolQuote() public {
        _activate(alice); // capitalise the pool
        (uint256 principal,, uint256 collateralValue) = fixer.quoteRunnerLoan();
        assertEq(collateralValue, market.quoteSell());
        assertEq(principal, collateralValue / 2, "50% opening LTV");
    }

    /// @dev The upfront rate is the Black Market's current sell fee tier, applied to the loan's
    ///      value in ETH.
    function test_quote_ethFeeTracksTheSellFeeTier() public {
        _activate(alice);
        (uint256 principal, uint256 ethFee,) = fixer.quoteRunnerLoan();

        uint256 principalWei = (principal * ETH_PER_RUN) / 1e18;
        assertEq(ethFee, (principalWei * market.sellFeeBps()) / 10_000);
        assertEq(market.sellFeeBps(), 1500, "mid tier at this price");

        // Move into the 25% tier and the rate should follow.
        oracle.setEthPerRun(ETH_PER_RUN / 20);
        (, uint256 cheaperFee,) = fixer.quoteRunnerLoan();
        assertEq(market.sellFeeBps(), 2500);
        assertGt((cheaperFee * 10_000) / ((principal * (ETH_PER_RUN / 20)) / 1e18), 2400);
    }

    function test_borrow_transfersUnitAndPaysOutRun() public {
        uint256 id = _activate(alice);
        _activate(bob); // more pool liquidity

        (uint256 principal, uint256 ethFee,) = fixer.quoteRunnerLoan();
        uint256 runBefore = runToken.balanceOf(alice);

        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 4);

        assertEq(runner.ownerOf(id), address(fixer), "unit escrowed");
        assertEq(runToken.balanceOf(alice) - runBefore, principal, "principal paid out");
        assertEq(fixer.runnerLoanLtvBps(loanId), 5000, "opens at 50% LTV");
    }

    function test_borrow_ethFeeGoesToTheSplitter() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();

        vm.prank(alice);
        fixer.borrowAgainstRunner{value: ethFee}(id, 4);

        assertEq(address(splitter).balance, ethFee, "upfront rate is protocol revenue");
        splitter.sync(address(0));
        assertEq(splitter.accrued(address(0), RevenueSplitter.Bucket.Drop), (ethFee * 6000) / 10_000);
    }

    function test_borrow_refundsEthOverpayment() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();

        uint256 balBefore = alice.balance;
        vm.prank(alice);
        fixer.borrowAgainstRunner{value: ethFee + 5 ether}(id, 4);

        assertEq(balBefore - alice.balance, ethFee, "overpayment returned");
    }

    function test_borrow_revertsOnInsufficientEthFee() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(Fixer.InsufficientEthFee.selector, ethFee, ethFee - 1)
        );
        fixer.borrowAgainstRunner{value: ethFee - 1}(id, 4);
    }

    function test_borrow_revertsOnBadTerm() public {
        uint256 id = _activate(alice);
        vm.startPrank(alice);
        vm.expectRevert(Fixer.BadTerm.selector);
        fixer.borrowAgainstRunner{value: 1 ether}(id, 0);
        vm.expectRevert(Fixer.BadTerm.selector);
        fixer.borrowAgainstRunner{value: 1 ether}(id, 53);
        vm.stopPrank();
    }

    function test_borrow_revertsIfNotUnitOwner() public {
        uint256 id = _activate(alice);
        vm.prank(bob);
        vm.expectRevert(Fixer.NotBorrower.selector);
        fixer.borrowAgainstRunner{value: 1 ether}(id, 4);
    }

    /*//////////////////////////////////////////////////////////////
                        $RUN LOANS — REPAY
    //////////////////////////////////////////////////////////////*/

    function test_repay_returnsTheUnitAndRefillsThePool() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (uint256 principal, uint256 ethFee,) = fixer.quoteRunnerLoan();

        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 4);

        uint256 lentBefore = market.totalLent();
        assertEq(lentBefore, principal);

        vm.prank(alice);
        fixer.repayRunnerLoan(loanId);

        assertEq(runner.ownerOf(id), alice, "unit returned");
        assertEq(market.totalLent(), 0, "pool made whole");
    }

    function test_repay_onlyBorrower() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 4);

        vm.prank(bob);
        vm.expectRevert(Fixer.NotBorrower.selector);
        fixer.repayRunnerLoan(loanId);
    }

    /*//////////////////////////////////////////////////////////////
                     $RUN LOANS — LTV DRIFT & ICING
    //////////////////////////////////////////////////////////////*/

    /// @dev The borrower does nothing; the pool quote falls and drags LTV up. That drift is the risk
    ///      the upfront ETH rate is priced for.
    function test_ltvDriftsAsThePoolQuoteFalls() public {
        _activate(alice);
        for (uint256 i = 0; i < 6; i++) _activate(bob);
        uint256 id = _activate(alice);

        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 52);
        assertEq(fixer.runnerLoanLtvBps(loanId), 5000);

        _pushPriceDown(6);
        uint256 ltv = fixer.runnerLoanLtvBps(loanId);
        assertGt(ltv, 5000, "LTV rose without the borrower acting");
        assertLt(ltv, 7000, "not yet iceable");
        assertFalse(fixer.isRunnerLoanIceable(loanId));
    }

    function test_iceableOnceLtvReachesSeventyPercent() public {
        _activate(alice);
        for (uint256 i = 0; i < 8; i++) _activate(bob);
        uint256 id = _activate(alice);

        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 52);

        _pushPriceDown(12);
        assertGe(fixer.runnerLoanLtvBps(loanId), 7000, "hit the ice threshold");
        assertTrue(fixer.isRunnerLoanIceable(loanId));

        fixer.iceRunnerLoan(loanId);
        (,,,,, Fixer.Status status) = fixer.runnerLoans(loanId);
        assertEq(uint256(status), uint256(Fixer.Status.Iced));
    }

    function test_cannotIceAHealthyLoan() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 52);

        vm.expectRevert(abi.encodeWithSelector(Fixer.NotIceable.selector, 5000));
        fixer.iceRunnerLoan(loanId);
    }

    function test_iceableOnceTermExpires() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 1);

        assertFalse(fixer.isRunnerLoanIceable(loanId));
        vm.warp(block.timestamp + 8 days);
        assertTrue(fixer.isRunnerLoanIceable(loanId), "past term");
        fixer.iceRunnerLoan(loanId);
    }

    /// @dev Icing seizes control, not ownership — the borrower can still clear the debt and redeem
    ///      right up until the collateral is disposed of.
    function test_icedLoanIsStillRedeemable() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 1);

        vm.warp(block.timestamp + 8 days);
        fixer.iceRunnerLoan(loanId);

        vm.prank(alice);
        fixer.repayRunnerLoan(loanId);
        assertEq(runner.ownerOf(id), alice, "redeemed after icing");
    }

    function test_disposeSendsUnitToThePool() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 1);

        vm.warp(block.timestamp + 8 days);
        fixer.iceRunnerLoan(loanId);

        uint256 poolBefore = market.poolSize();
        fixer.disposeRunnerCollateral(loanId);

        assertEq(market.poolSize(), poolBefore + 1, "unit became pool stock");
        assertTrue(market.isInPool(id));

        vm.prank(alice);
        vm.expectRevert(Fixer.LoanNotActive.selector);
        fixer.repayRunnerLoan(loanId);
    }

    function test_disposeRequiresIced() public {
        uint256 id = _activate(alice);
        _activate(bob);
        (, uint256 ethFee,) = fixer.quoteRunnerLoan();
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstRunner{value: ethFee}(id, 4);

        vm.expectRevert(Fixer.LoanNotIced.selector);
        fixer.disposeRunnerCollateral(loanId);
    }

    /*//////////////////////////////////////////////////////////////
                      POOL LENDING CEILING
    //////////////////////////////////////////////////////////////*/

    /// @dev Without a ceiling the Fixer could drain the pool's $RUN and `sell` would start
    ///      reverting, stranding operators who expect a floor bid.
    function test_lendingCeilingProtectsTheFloorBid() public {
        _activate(alice);
        uint256 lendable = market.lendableRun();
        assertEq(lendable, market.poolLiquidity() / 2, "50% ceiling by default");

        market.setMaxLendBps(0);
        assertEq(market.lendableRun(), 0);

        uint256 id = _activate(alice);
        vm.prank(alice);
        vm.expectRevert();
        fixer.borrowAgainstRunner{value: 10 ether}(id, 4);
    }

    /*//////////////////////////////////////////////////////////////
                     $AUG LOANS AGAINST AN AUGMENT
    //////////////////////////////////////////////////////////////*/

    function _buyLooseAugment(address who, uint256 augmentId) internal {
        vm.prank(who);
        doc.buyAugment(augmentId, 1);
    }

    function test_augmentLoan_drawsHalfItsValue() public {
        _buyLooseAugment(alice, T3_NVDA);
        uint256 augBefore = aug.balanceOf(alice);

        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        // Tier 3 is 500 $AUG, so the draw is 250.
        assertEq(aug.balanceOf(alice) - augBefore, 250e18, "half the Augment's value");
        assertEq(augments.balanceOf(alice, T3_NVDA), 0, "collateral escrowed");
        assertEq(fixer.augmentLoanLtvBps(loanId), 5000, "opens at 50% LTV");
    }

    function test_augmentLoan_onlyLooseAugmentsCanBePledged() public {
        // Seating burns the ERC-1155, so a seated Augment has no balance to pledge at all.
        uint256 unitId = _activate(alice);
        vm.prank(alice);
        doc.buyAndSeatAugment(unitId, 0, T3_NVDA);

        vm.prank(alice);
        vm.expectRevert();
        fixer.borrowAgainstAugment(T3_NVDA);
    }

    /// @dev Linear 25% APR — readable without modelling a curve.
    function test_augmentLoan_interestAccruesLinearly() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        assertEq(fixer.augmentLoanInterest(loanId), 0);

        vm.warp(block.timestamp + 365 days);
        // 25% of 250 = 62.5
        assertApproxEqAbs(fixer.augmentLoanInterest(loanId), 62.5e18, 1e12, "one year");

        vm.warp(block.timestamp + 365 days);
        assertApproxEqAbs(fixer.augmentLoanInterest(loanId), 125e18, 1e12, "two years, linear");
    }

    /// @dev Collateral value is fixed by tier, so LTV rises purely with interest: 50% at open,
    ///      reaching the 70% ice threshold after about 1.6 years at 25% APR.
    function test_augmentLoan_icesAfterAboutSixteenMonths() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        vm.warp(block.timestamp + 365 days);
        assertLt(fixer.augmentLoanLtvBps(loanId), 7000, "not yet");
        assertFalse(fixer.isAugmentLoanIceable(loanId));

        vm.warp(block.timestamp + 250 days);
        assertGe(fixer.augmentLoanLtvBps(loanId), 7000, "crossed the threshold");
        assertTrue(fixer.isAugmentLoanIceable(loanId));

        fixer.iceAugmentLoan(loanId);
    }

    function test_icingStopsInterestAccrual() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        vm.warp(block.timestamp + 700 days);
        fixer.iceAugmentLoan(loanId);
        uint256 frozen = fixer.augmentLoanInterest(loanId);

        vm.warp(block.timestamp + 365 days);
        assertEq(fixer.augmentLoanInterest(loanId), frozen, "debt frozen at icing");
    }

    /// @dev Interest paid back in is burned — borrowing shrinks $AUG supply rather than banking it.
    function test_repayBurnsInterestAndReturnsPrincipal() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        vm.warp(block.timestamp + 365 days);
        uint256 interest = fixer.augmentLoanInterest(loanId);
        uint256 debt = fixer.augmentLoanDebt(loanId);
        assertEq(debt, 250e18 + interest);

        uint256 supplyBefore = aug.totalSupply();
        uint256 reserveBefore = aug.balanceOf(address(reserve));

        vm.prank(alice);
        fixer.repayAugmentLoan(loanId);

        assertEq(aug.totalSupply(), supplyBefore - interest, "interest burned, exactly");
        assertEq(aug.balanceOf(address(reserve)) - reserveBefore, 250e18, "principal returned");
        assertEq(augments.balanceOf(alice, T3_NVDA), 1, "collateral released");
        assertEq(fixer.totalInterestBurned(), interest);
    }

    function test_icedAugmentLoanIsStillRedeemable() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        vm.warp(block.timestamp + 700 days);
        fixer.iceAugmentLoan(loanId);

        vm.prank(alice);
        fixer.repayAugmentLoan(loanId);
        assertEq(augments.balanceOf(alice, T3_NVDA), 1, "redeemed after icing");
    }

    function test_disposeAugmentSendsItToTheReserve() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);

        vm.warp(block.timestamp + 700 days);
        fixer.iceAugmentLoan(loanId);
        fixer.disposeAugmentCollateral(loanId);

        assertEq(augments.balanceOf(address(reserve), T3_NVDA), 1);
    }

    function test_augmentLoan_tierOneDrawsFifty() public {
        _buyLooseAugment(alice, T1_SPY);
        uint256 before = aug.balanceOf(alice);
        vm.prank(alice);
        fixer.borrowAgainstAugment(T1_SPY);
        assertEq(aug.balanceOf(alice) - before, 50e18, "half of 100");
    }

    function test_reserveTracksOutstanding() public {
        _buyLooseAugment(alice, T3_NVDA);
        vm.prank(alice);
        uint256 loanId = fixer.borrowAgainstAugment(T3_NVDA);
        assertEq(reserve.outstanding(), 250e18);

        vm.prank(alice);
        fixer.repayAugmentLoan(loanId);
        assertEq(reserve.outstanding(), 0);
    }

    function test_reserveLendOnlyByFixer() public {
        vm.prank(alice);
        vm.expectRevert(ProtocolReserve.NotFixer.selector);
        reserve.lend(alice, 1e18);
    }

    function test_marketLendOnlyByFixer() public {
        vm.prank(alice);
        vm.expectRevert(BlackMarket.NotFixer.selector);
        market.lendRun(alice, 1e18);
    }
}
