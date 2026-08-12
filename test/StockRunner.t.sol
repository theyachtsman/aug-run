// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

import {RUN} from "../src/tokens/RUN.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";
import {Cycles} from "../src/runner/Cycles.sol";
import {IERC6551Account} from "../src/runner/interfaces/IERC6551.sol";
import {ERC6551RegistryFixture} from "./helpers/ERC6551RegistryFixture.sol";

contract StockRunnerTest is Test {
    RUN internal runToken;
    StockRunner internal runner;
    ERC6551Account internal accountImpl;
    address internal registry;

    address internal treasury = makeAddr("treasury");
    address internal ripperdoc = makeAddr("ripperdoc");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    uint256 constant PRICE = 1_000_000e18;

    function setUp() public {
        // Foundry starts at timestamp 1, which is before the cycle genesis. Warp to a realistic
        // point (Sat 2026-08-08) so the clock behaves as it will on chain.
        vm.warp(1786147200);

        registry = ERC6551RegistryFixture.install();
        accountImpl = new ERC6551Account();

        runToken = new RUN(address(this), true);
        runner = new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        runner.setRipperdoc(ripperdoc);
        runner.openMinting();

        runToken.transfer(alice, 50_000_000e18);
        runToken.transfer(bob, 50_000_000e18);
    }

    function _mint(address who) internal returns (uint256 tokenId) {
        vm.startPrank(who);
        runToken.approve(address(runner), PRICE);
        tokenId = runner.mint();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                              SUPPLY CAP
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                            MINTING GATE
    //////////////////////////////////////////////////////////////*/

    /// @dev Minting must be closed on deploy. The spec sequences $RUN's launch ahead of the mint,
    ///      and a contract is public the instant it lands — withholding the UI is not a control.
    function test_mintingIsClosedOnDeploy() public {
        StockRunner fresh =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        assertFalse(fresh.mintingOpen(), "must ship closed");

        vm.startPrank(alice);
        runToken.approve(address(fresh), PRICE);
        vm.expectRevert(StockRunner.MintingNotOpen.selector);
        fresh.mint();
        vm.stopPrank();
    }

    function test_openMinting_letsMintingThrough() public {
        StockRunner fresh =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        fresh.openMinting();
        assertTrue(fresh.mintingOpen());

        vm.startPrank(alice);
        runToken.approve(address(fresh), PRICE);
        assertEq(fresh.mint(), 1, "mints once open");
        vm.stopPrank();
    }

    function test_openMinting_onlyOwner() public {
        StockRunner fresh =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        vm.prank(alice);
        vm.expectRevert();
        fresh.openMinting();
    }

    /// @dev One-way by design. A closeable mint is a lever over holders, and an operator who can
    ///      halt minting at will is an operator who can be pressured to.
    function test_openMinting_cannotBeReopenedOrClosed() public {
        StockRunner fresh =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, true);
        fresh.openMinting();
        vm.expectRevert(StockRunner.MintingAlreadyOpen.selector);
        fresh.openMinting();

        // There is no close function at all — assert the surface doesn't exist.
        assertTrue(fresh.mintingOpen(), "still open, permanently");
    }

    function test_maxSupplyIs333() public view {
        assertEq(runner.MAX_SUPPLY(), 333);
    }

    function test_tokenIdsRunFromOne() public {
        assertEq(_mint(alice), 1);
        assertEq(_mint(alice), 2);
    }

    /// @dev The cap: 333 succeed, the 334th reverts.
    function test_capEnforced_mint334Reverts() public {
        runToken.transfer(alice, 400_000_000e18);

        for (uint256 i = 0; i < 333; i++) {
            _mint(alice);
        }
        assertEq(runner.totalMinted(), 333);
        assertEq(runner.balanceOf(alice), 333);

        vm.startPrank(alice);
        runToken.approve(address(runner), PRICE);
        vm.expectRevert(StockRunner.SupplyExhausted.selector);
        runner.mint();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            PAYMENT PATH
    //////////////////////////////////////////////////////////////*/

    function test_mint_transfersExactlyOneMillionRunToTreasury() public {
        uint256 before = runToken.balanceOf(alice);
        _mint(alice);
        assertEq(runToken.balanceOf(treasury), PRICE);
        assertEq(runToken.balanceOf(alice), before - PRICE);
    }

    function test_mint_revertsWithoutApproval() public {
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(runner), 0, PRICE)
        );
        runner.mint();
    }

    function test_mint_revertsWithInsufficientBalance() public {
        address broke = makeAddr("broke");
        vm.startPrank(broke);
        runToken.approve(address(runner), PRICE);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, broke, 0, PRICE)
        );
        runner.mint();
        vm.stopPrank();
    }

    function test_mint_revertsWithPartialApproval() public {
        vm.startPrank(alice);
        runToken.approve(address(runner), PRICE - 1);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(runner), PRICE - 1, PRICE
            )
        );
        runner.mint();
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                         ERC-6551 TOKEN-BOUND ACCOUNT
    //////////////////////////////////////////////////////////////*/

    function test_mint_deploysTokenBoundAccount() public {
        uint256 id = _mint(alice);
        address tba = runner.tokenBoundAccount(id);

        assertGt(tba.code.length, 0, "TBA must be deployed at mint");
    }

    function test_tokenBoundAccount_isBoundToTheRightToken() public {
        uint256 id = _mint(alice);
        address tba = runner.tokenBoundAccount(id);

        (uint256 chainId, address tokenContract, uint256 tokenId) = IERC6551Account(payable(tba)).token();
        assertEq(chainId, block.chainid);
        assertEq(tokenContract, address(runner));
        assertEq(tokenId, id);
    }

    function test_tokenBoundAccount_ownerIsTheUnitHolder() public {
        uint256 id = _mint(alice);
        ERC6551Account tba = ERC6551Account(payable(runner.tokenBoundAccount(id)));
        assertEq(tba.owner(), alice);
    }

    /// @dev The wallet follows the unit. This is what "the machine remembers" rests on — selling a
    ///      Stock//Runner hands over its wallet and contents with no migration step.
    function test_tokenBoundAccount_followsTheNFTOnTransfer() public {
        uint256 id = _mint(alice);
        address tbaAddr = runner.tokenBoundAccount(id);
        ERC6551Account tba = ERC6551Account(payable(tbaAddr));
        assertEq(tba.owner(), alice);

        vm.prank(alice);
        runner.transferFrom(alice, bob, id);

        assertEq(tba.owner(), bob, "wallet must follow the unit");
        assertEq(runner.tokenBoundAccount(id), tbaAddr, "address must not change");
    }

    function test_tokenBoundAccount_eachUnitGetsADistinctWallet() public {
        uint256 a = _mint(alice);
        uint256 b = _mint(alice);
        assertTrue(runner.tokenBoundAccount(a) != runner.tokenBoundAccount(b));
    }

    function test_tokenBoundAccount_viewMatchesPreMintPrediction() public {
        address predicted = runner.tokenBoundAccount(1);
        uint256 id = _mint(alice);
        assertEq(id, 1);
        assertEq(runner.tokenBoundAccount(id), predicted, "address must be deterministic");
    }

    function test_tokenBoundAccount_onlyOwnerCanExecute() public {
        uint256 id = _mint(alice);
        ERC6551Account tba = ERC6551Account(payable(runner.tokenBoundAccount(id)));
        vm.deal(address(tba), 1 ether);

        vm.prank(bob);
        vm.expectRevert(ERC6551Account.InvalidSigner.selector);
        tba.execute(payable(bob), 1 ether, "", 0);

        vm.prank(alice);
        tba.execute(payable(alice), 1 ether, "", 0);
        assertEq(alice.balance, 1 ether);
    }

    /*//////////////////////////////////////////////////////////////
                          MODEL ASSIGNMENT
    //////////////////////////////////////////////////////////////*/

    function test_modelCountIs11() public view {
        assertEq(runner.MODEL_COUNT(), 11);
    }

    function test_initialModelBuckets_are31_31_31_then30() public view {
        uint16[11] memory rem = runner.modelRemaining();
        uint256 sum;
        for (uint256 i = 0; i < 11; i++) {
            assertEq(rem[i], i < 3 ? 31 : 30, "bucket size");
            sum += rem[i];
        }
        assertEq(sum, 333);
    }

    function test_mint_assignsModelInRange() public {
        for (uint256 i = 0; i < 20; i++) {
            uint256 id = _mint(alice);
            assertLt(runner.modelOf(id), 11);
        }
    }

    /// @dev Equal counts are load-bearing: they keep supply rarity off the table entirely. After all
    ///      333 are activated the distribution must be exactly 31/31/31 + 30x8, whatever order the
    ///      draws came in.
    function test_fullMintOut_producesExactEqualCounts() public {
        runToken.transfer(alice, 400_000_000e18);

        uint256[11] memory counts;
        for (uint256 i = 0; i < 333; i++) {
            uint256 id = _mint(alice);
            counts[runner.modelOf(id)]++;
        }

        uint256 total;
        for (uint256 i = 0; i < 11; i++) {
            assertEq(counts[i], i < 3 ? 31 : 30, "final model counts must be exact");
            total += counts[i];
        }
        assertEq(total, 333);

        uint16[11] memory rem = runner.modelRemaining();
        for (uint256 i = 0; i < 11; i++) {
            assertEq(rem[i], 0, "all buckets drained");
        }
    }

    /// @dev A caller cannot reroll: their own address is an input to the draw, so resubmitting the
    ///      same mint from the same address at the same state yields the same model.
    function test_modelDraw_isNotRerollable() public {
        uint256 snap = vm.snapshotState();
        uint256 id1 = _mint(alice);
        uint8 model1 = runner.modelOf(id1);

        vm.revertToState(snap);
        uint256 id2 = _mint(alice);
        uint8 model2 = runner.modelOf(id2);

        assertEq(id1, id2);
        assertEq(model1, model2, "same caller, same state => same model");
    }

    /*//////////////////////////////////////////////////////////////
                             UNIT STATE
    //////////////////////////////////////////////////////////////*/

    function test_mint_startsWithOneBay() public {
        uint256 id = _mint(alice);
        assertEq(runner.bayCountOf(id), 1);
    }

    function test_mint_startsWithEmptyBays() public {
        uint256 id = _mint(alice);
        StockRunner.Bay memory bay = runner.getBay(id, 0);
        assertEq(bay.augmentId, 0);
        assertEq(bay.tier, 0);
        assertFalse(bay.everChanged);
    }

    /*//////////////////////////////////////////////////////////////
                                CYCLES
    //////////////////////////////////////////////////////////////*/

    function test_currentCycle_matchesPureClock() public view {
        assertEq(runner.currentCycle(), Cycles.cycleAt(block.timestamp));
    }

    function test_currentCycle_advancesAtBoundary() public {
        uint256 c = runner.currentCycle();
        vm.warp(Cycles.nextBoundary(block.timestamp) - 1);
        assertEq(runner.currentCycle(), c, "still the same cycle one second before");
        vm.warp(block.timestamp + 1);
        assertEq(runner.currentCycle(), c + 1, "ticks exactly at the boundary");
    }

    function test_advanceCycles_movesEffectiveCycle() public {
        uint256 c = runner.currentCycle();
        runner.advanceCycles(3);
        assertEq(runner.currentCycle(), c + 3);
        assertEq(runner.cycleOffset(), 3);
    }

    function test_advanceCycles_isPermissionlessOnTestnet() public {
        uint256 c = runner.currentCycle();
        vm.prank(alice);
        runner.advanceCycles(1);
        assertEq(runner.currentCycle(), c + 1);
    }

    function test_advanceCycles_revertsWhenNotTestnet() public {
        StockRunner mainnetRunner =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, false);
        vm.expectRevert(StockRunner.TestnetOnly.selector);
        mainnetRunner.advanceCycles(1);
    }

    function test_mainnetRunner_cycleIsPureFunctionOfTime() public {
        StockRunner mainnetRunner =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, false);
        assertEq(mainnetRunner.cycleOffset(), 0);
        assertEq(mainnetRunner.currentCycle(), Cycles.cycleAt(block.timestamp));
    }

    function test_timeUntilNextCycle() public view {
        assertEq(runner.timeUntilNextCycle(), Cycles.timeUntilNextBoundary(block.timestamp));
        assertLe(runner.timeUntilNextCycle(), 7 days);
    }

    /*//////////////////////////////////////////////////////////////
                          BAY ACCESS CONTROL
    //////////////////////////////////////////////////////////////*/

    function test_setBay_onlyRipperdoc() public {
        uint256 id = _mint(alice);

        vm.prank(alice);
        vm.expectRevert(StockRunner.NotRipperdoc.selector);
        runner.setBay(id, 0, 1, 1);

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);
        assertEq(runner.getBay(id, 0).augmentId, 1);
    }

    function test_addBay_onlyRipperdoc() public {
        uint256 id = _mint(alice);
        vm.prank(alice);
        vm.expectRevert(StockRunner.NotRipperdoc.selector);
        runner.addBay(id);
    }

    /// @dev Strictly set-once on mainnet: whoever holds this address can rewrite every unit's
    ///      seating and tenure, so it must not be re-pointable in production.
    function test_setRipperdoc_isStrictlySetOnceOnMainnet() public {
        StockRunner mainnetRunner =
            new StockRunner(address(runToken), registry, address(accountImpl), treasury, false);
        mainnetRunner.setRipperdoc(ripperdoc);

        vm.expectRevert(StockRunner.RipperdocAlreadySet.selector);
        mainnetRunner.setRipperdoc(makeAddr("other"));

        assertEq(mainnetRunner.ripperdoc(), ripperdoc, "must stay pointed at the original");
    }

    /// @dev Re-pointable on testnet only, so later phases can swap the Ripperdoc without forcing a
    ///      fresh StockRunner and a re-mint of every test unit.
    function test_setRipperdoc_isRepointableOnTestnet() public {
        address next = makeAddr("ripperdocV2");
        runner.setRipperdoc(next);
        assertEq(runner.ripperdoc(), next);
    }

    function test_setRipperdoc_stillOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        runner.setRipperdoc(makeAddr("other"));
    }

    function test_setRipperdoc_rejectsZero() public {
        vm.expectRevert(StockRunner.ZeroAddress.selector);
        runner.setRipperdoc(address(0));
    }

    function test_setBay_revertsOnBayOutOfRange() public {
        uint256 id = _mint(alice);
        // Unit ships with one bay, so index 1 is not open yet.
        vm.prank(ripperdoc);
        vm.expectRevert(StockRunner.BayIndexOutOfRange.selector);
        runner.setBay(id, 1, 1, 1);
    }

    function test_setBay_revertsOnNonexistentUnit() public {
        vm.prank(ripperdoc);
        vm.expectRevert(StockRunner.NonexistentUnit.selector);
        runner.setBay(999, 0, 1, 1);
    }

    /*//////////////////////////////////////////////////////////////
                        THREE-BAY CEILING
    //////////////////////////////////////////////////////////////*/

    function test_addBay_ceilingIsThree() public {
        uint256 id = _mint(alice);
        assertEq(runner.bayCountOf(id), 1);

        vm.startPrank(ripperdoc);
        runner.addBay(id);
        assertEq(runner.bayCountOf(id), 2);
        runner.addBay(id);
        assertEq(runner.bayCountOf(id), 3);

        vm.expectRevert(StockRunner.BayCeilingReached.selector);
        runner.addBay(id);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                       ONE CHANGE PER BAY PER CYCLE
    //////////////////////////////////////////////////////////////*/

    function test_secondChangeToSameBayInOneCycle_reverts() public {
        uint256 id = _mint(alice);

        vm.startPrank(ripperdoc);
        runner.setBay(id, 0, 1, 1);

        vm.expectRevert(StockRunner.BayLockedThisCycle.selector);
        runner.setBay(id, 0, 2, 1);
        vm.stopPrank();
    }

    function test_bayUnlocksNextCycle() public {
        uint256 id = _mint(alice);

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);
        assertFalse(runner.isBayUnlocked(id, 0));

        runner.advanceCycles(1);
        assertTrue(runner.isBayUnlocked(id, 0));

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 2, 2);
        assertEq(runner.getBay(id, 0).augmentId, 2);
    }

    /// @dev The lock is per bay, not per unit — changing bay 0 must not freeze bay 1.
    function test_lockIsPerBayNotPerUnit() public {
        uint256 id = _mint(alice);
        vm.startPrank(ripperdoc);
        runner.addBay(id);

        runner.setBay(id, 0, 1, 1);
        runner.setBay(id, 1, 2, 2); // different bay, same cycle — fine
        vm.stopPrank();

        assertEq(runner.getBay(id, 0).augmentId, 1);
        assertEq(runner.getBay(id, 1).augmentId, 2);
    }

    function test_clearingAnAlreadyEmptyBayReverts() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        vm.expectRevert(StockRunner.BayAlreadyEmpty.selector);
        runner.setBay(id, 0, 0, 0);
    }

    function test_setBay_rejectsInvalidTier() public {
        uint256 id = _mint(alice);
        vm.startPrank(ripperdoc);
        vm.expectRevert(StockRunner.InvalidTier.selector);
        runner.setBay(id, 0, 1, 0);
        vm.expectRevert(StockRunner.InvalidTier.selector);
        runner.setBay(id, 0, 1, 4);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        TENURE & SEASONING
    //////////////////////////////////////////////////////////////*/

    /// @dev Seated during cycle N: not eligible in N, freshly seasoned (tenure 0) in N+1, first
    ///      completed cycle at N+2.
    function test_seasoning_seatedMidCycleIsIneligibleThatCycle() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);

        assertFalse(runner.isBayEligible(id, 0), "ineligible in the cycle it was seated");

        runner.advanceCycles(1);
        assertTrue(runner.isBayEligible(id, 0), "eligible from the next full cycle");
    }

    function test_tenure_freshlySeasonedIsZero() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);

        assertEq(runner.tenureCycles(id, 0), 0, "seated cycle");
        runner.advanceCycles(1);
        assertEq(runner.tenureCycles(id, 0), 0, "freshly seasoned => 1.0x");
        runner.advanceCycles(1);
        assertEq(runner.tenureCycles(id, 0), 1, "first completed cycle");
    }

    function test_tenure_accruesOnePerCycle() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);

        runner.advanceCycles(2);
        assertEq(runner.tenureCycles(id, 0), 1);
        for (uint256 i = 2; i <= 10; i++) {
            runner.advanceCycles(1);
            assertEq(runner.tenureCycles(id, 0), i);
        }
    }

    function test_tenure_emptyBayHasNone() public {
        uint256 id = _mint(alice);
        runner.advanceCycles(10);
        assertEq(runner.tenureCycles(id, 0), 0);
        assertFalse(runner.isBayEligible(id, 0));
    }

    /// @dev Rebinding resets that bay's tenure to zero. This is the anti-churn mechanic.
    function test_rebind_resetsTenureToZero() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);

        runner.advanceCycles(6);
        assertEq(runner.tenureCycles(id, 0), 5);

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 2, 2); // swap to a different Augment

        assertEq(runner.tenureCycles(id, 0), 0, "rebind must reset tenure");
        assertFalse(runner.isBayEligible(id, 0), "and reseason from scratch");
    }

    function test_sellingBackResetsTenure() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);
        runner.advanceCycles(6);

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 0, 0); // sell back to the Ripperdoc

        assertEq(runner.tenureCycles(id, 0), 0);
        assertEq(runner.getBay(id, 0).augmentId, 0);
    }

    /*//////////////////////////////////////////////////////////////
                    TENURE SURVIVES NFT TRANSFER
    //////////////////////////////////////////////////////////////*/

    /// @dev Deliberate and load-bearing: tenure travels with the unit, so a built unit's resale
    ///      premium buys real earning power rather than just a history log.
    function test_nftTransfer_preservesTenure() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 3);

        runner.advanceCycles(6);
        uint256 tenureBefore = runner.tenureCycles(id, 0);
        assertGt(tenureBefore, 0, "precondition: tenure accrued");

        vm.prank(alice);
        runner.transferFrom(alice, bob, id);

        assertEq(runner.ownerOf(id), bob);
        assertEq(runner.tenureCycles(id, 0), tenureBefore, "tenure must survive transfer");
        assertGt(runner.tenureCycles(id, 0), 0, "explicitly non-zero after transfer");
        assertTrue(runner.isBayEligible(id, 0), "and stays eligible");

        StockRunner.Bay memory bay = runner.getBay(id, 0);
        assertEq(bay.augmentId, 1, "seated Augment travels with the unit");
        assertEq(bay.tier, 3);
    }

    function test_nftTransfer_preservesBayCountAndModel() public {
        uint256 id = _mint(alice);
        uint8 model = runner.modelOf(id);

        vm.startPrank(ripperdoc);
        runner.addBay(id);
        runner.addBay(id);
        vm.stopPrank();

        vm.prank(alice);
        runner.transferFrom(alice, bob, id);

        assertEq(runner.bayCountOf(id), 3, "capacity travels with the unit");
        assertEq(runner.modelOf(id), model);
    }

    /// @dev A new owner rebinding still resets — buy a tenured unit and immediately swap tickers and
    ///      you destroy exactly what you paid the premium for.
    function test_newOwnerRebind_stillResetsTenure() public {
        uint256 id = _mint(alice);
        vm.prank(ripperdoc);
        runner.setBay(id, 0, 1, 1);
        runner.advanceCycles(9);
        assertGt(runner.tenureCycles(id, 0), 0);

        vm.prank(alice);
        runner.transferFrom(alice, bob, id);
        assertGt(runner.tenureCycles(id, 0), 0, "survives the sale");

        vm.prank(ripperdoc);
        runner.setBay(id, 0, 7, 2); // new owner swaps the ticker

        assertEq(runner.tenureCycles(id, 0), 0, "new owner's rebind resets it anyway");
    }

    /*//////////////////////////////////////////////////////////////
                             CALIBRATION
    //////////////////////////////////////////////////////////////*/

    function test_calibration_oncePerUnitPerDay() public {
        uint256 id = _mint(alice);

        vm.prank(ripperdoc);
        runner.recordCalibration(id);
        assertEq(runner.calibrationCountOf(id), 1);

        vm.prank(ripperdoc);
        vm.expectRevert(StockRunner.AlreadyCalibratedToday.selector);
        runner.recordCalibration(id);

        vm.warp(block.timestamp + 1 days);
        vm.prank(ripperdoc);
        runner.recordCalibration(id);
        assertEq(runner.calibrationCountOf(id), 2);
    }

    function test_calibration_isPerUnit() public {
        uint256 a = _mint(alice);
        uint256 b = _mint(alice);

        vm.startPrank(ripperdoc);
        runner.recordCalibration(a);
        runner.recordCalibration(b);
        vm.stopPrank();

        assertEq(runner.calibrationCountOf(a), 1);
        assertEq(runner.calibrationCountOf(b), 1);
    }

    /*//////////////////////////////////////////////////////////////
                                ADMIN
    //////////////////////////////////////////////////////////////*/

    function test_setTreasury_repointsPayment() public {
        address newTreasury = makeAddr("blackMarket");
        runner.setTreasury(newTreasury);
        _mint(alice);
        assertEq(runToken.balanceOf(newTreasury), PRICE);
        assertEq(runToken.balanceOf(treasury), 0);
    }

    function test_setTreasury_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        runner.setTreasury(alice);
    }

    /*//////////////////////////////////////////////////////////////
                             ERC-721 BASICS
    //////////////////////////////////////////////////////////////*/

    function test_nameAndSymbol() public view {
        assertEq(runner.name(), "Stock//Runner");
        assertEq(runner.symbol(), "RUNNER");
    }

    function test_ownerOf_revertsForUnminted() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        runner.ownerOf(1);
    }
}
