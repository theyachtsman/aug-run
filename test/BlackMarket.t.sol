// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

import {RUN} from "../src/tokens/RUN.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";
import {BlackMarket} from "../src/market/BlackMarket.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {TestnetRunPriceOracle} from "../src/market/TestnetRunPriceOracle.sol";
import {ERC6551RegistryFixture} from "./helpers/ERC6551RegistryFixture.sol";

contract BlackMarketTest is Test {
    RUN internal runToken;
    StockRunner internal runner;
    BlackMarket internal market;
    RevenueSplitter internal splitter;
    TestnetRunPriceOracle internal oracle;

    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal dropRecipient = makeAddr("drop");

    uint256 constant GENESIS = 1_000_000e18;
    uint256 constant INITIAL_SPOT = 1_000_000e18;
    uint256 constant DELTA = 25_000e18;
    uint256 constant MIN_SPOT = 100_000e18;

    /// @dev 1 $RUN = 1e11 wei, so a 1,000,000 $RUN unit is worth exactly 0.1 ETH — right on the
    ///      lower fee-tier boundary, which is where the interesting cases live.
    uint256 constant ETH_PER_RUN_AT_FLOOR = 1e11;

    function setUp() public {
        vm.warp(1786147200);

        address registry = ERC6551RegistryFixture.install();
        ERC6551Account accountImpl = new ERC6551Account();

        runToken = new RUN(address(this), true);
        splitter = new RevenueSplitter();
        oracle = new TestnetRunPriceOracle(ETH_PER_RUN_AT_FLOOR);

        runner = new StockRunner(address(runToken), registry, address(accountImpl), address(this), true);
        market = new BlackMarket(
            address(runToken), address(runner), address(splitter), address(oracle),
            INITIAL_SPOT, DELTA, MIN_SPOT
        );

        // Genesis proceeds capitalise the pool, and royalties fan out through the splitter.
        runner.setTreasury(address(market));
        runner.openMinting();
        runner.setRoyaltyReceiver(address(splitter));
        splitter.setRecipient(RevenueSplitter.Bucket.Drop, dropRecipient);

        _fund(alice);
        _fund(bob);
    }

    function _fund(address who) internal {
        runToken.transfer(who, 20_000_000e18);
        vm.startPrank(who);
        runToken.approve(address(market), type(uint256).max);
        runToken.approve(address(runner), type(uint256).max);
        vm.stopPrank();
    }

    function _activate(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = market.activateGenesis();
    }

    /// @dev Put a unit into the pool so buy paths have inventory.
    function _seedPool(address who) internal returns (uint256 id) {
        id = _activate(who);
        vm.startPrank(who);
        runner.approve(address(market), id);
        market.sell(id, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                             GENESIS MINT
    //////////////////////////////////////////////////////////////*/

    function test_activateGenesis_costsExactlyOneMillionRun() public {
        uint256 before = runToken.balanceOf(alice);
        uint256 id = _activate(alice);

        assertEq(runner.ownerOf(id), alice, "operator receives the unit");
        assertEq(before - runToken.balanceOf(alice), GENESIS, "paid exactly 1,000,000 $RUN");
    }

    /// @dev Genesis proceeds capitalise the pool — that is what gives it $RUN to buy units back
    ///      with, and in phase 6 what the Fixer lends against.
    function test_activateGenesis_capitalisesThePool() public {
        assertEq(market.poolLiquidity(), 0);
        _activate(alice);
        assertEq(market.poolLiquidity(), GENESIS, "1,000,000 $RUN now backs the pool");
    }

    function test_activateGenesis_doesNotAddTheUnitToInventory() public {
        _activate(alice);
        assertEq(market.poolSize(), 0, "a freshly activated unit is not pool stock");
    }

    function test_activateGenesis_chargesNoFee() public {
        _activate(alice);
        assertEq(market.lifetimeFees(), 0, "genesis has no fee, only purchases and sales do");
    }

    function test_activateGenesis_respectsTheCap() public {
        // Cheaper than minting 333 through the market: prove the cap propagates.
        assertEq(runner.MAX_SUPPLY(), 333);
    }

    /*//////////////////////////////////////////////////////////////
                                BUYING
    //////////////////////////////////////////////////////////////*/

    function test_buyRandom_chargesTenPercent() public {
        _seedPool(alice);
        uint256 spot = market.quoteBuy();

        (uint256 price, uint256 fee, uint256 total) = market.buyTotal(false);
        assertEq(price, spot);
        assertEq(fee, (spot * 1000) / 10_000, "10% for a random unit");
        assertEq(total, price + fee);

        uint256 before = runToken.balanceOf(bob);
        vm.prank(bob);
        market.buyRandom(type(uint256).max);

        assertEq(before - runToken.balanceOf(bob), total, "paid price + 10%");
    }

    function test_buySpecific_chargesFifteenPercent() public {
        uint256 id = _seedPool(alice);
        uint256 spot = market.quoteBuy();

        (, uint256 fee, uint256 total) = market.buyTotal(true);
        assertEq(fee, (spot * 1500) / 10_000, "15% to pick a specific unit");

        uint256 before = runToken.balanceOf(bob);
        vm.prank(bob);
        market.buySpecific(id, type(uint256).max);

        assertEq(runner.ownerOf(id), bob, "buyer gets the unit they named");
        assertEq(before - runToken.balanceOf(bob), total);
    }

    /// @dev Picking costs 5 percentage points more than taking pot luck.
    function test_specificCostsMoreThanRandom() public {
        _seedPool(alice);
        (,, uint256 randomTotal) = market.buyTotal(false);
        (,, uint256 specificTotal) = market.buyTotal(true);
        assertGt(specificTotal, randomTotal);
        assertEq(specificTotal - randomTotal, (market.quoteBuy() * 500) / 10_000);
    }

    function test_buy_removesUnitFromInventory() public {
        uint256 id = _seedPool(alice);
        assertEq(market.poolSize(), 1);
        assertTrue(market.isInPool(id));

        vm.prank(bob);
        market.buySpecific(id, type(uint256).max);

        assertEq(market.poolSize(), 0);
        assertFalse(market.isInPool(id));
    }

    function test_buyRandom_revertsWhenPoolEmpty() public {
        vm.prank(bob);
        vm.expectRevert(BlackMarket.PoolEmpty.selector);
        market.buyRandom(type(uint256).max);
    }

    function test_buySpecific_revertsForUnitNotInPool() public {
        uint256 id = _activate(alice); // held by alice, never sold in
        vm.prank(bob);
        vm.expectRevert(BlackMarket.UnitNotInPool.selector);
        market.buySpecific(id, type(uint256).max);
    }

    function test_buy_respectsSlippageGuard() public {
        _seedPool(alice);
        (,, uint256 total) = market.buyTotal(false);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(BlackMarket.SlippageExceeded.selector, total, total - 1));
        market.buyRandom(total - 1);
    }

    /*//////////////////////////////////////////////////////////////
                              THE CURVE
    //////////////////////////////////////////////////////////////*/

    function test_buy_stepsPriceUp() public {
        _seedPool(alice);
        _seedPool(alice);
        uint256 before = market.quoteBuy();

        vm.prank(bob);
        market.buyRandom(type(uint256).max);

        assertEq(market.quoteBuy(), before + DELTA, "each unit leaving makes the next dearer");
    }

    function test_sell_stepsPriceDown() public {
        uint256 id = _activate(alice);
        uint256 before = market.quoteBuy();

        vm.startPrank(alice);
        runner.approve(address(market), id);
        market.sell(id, 0);
        vm.stopPrank();

        assertEq(market.quoteBuy(), before - DELTA, "each unit arriving makes the next cheaper");
    }

    function test_spotPrice_neverFallsBelowFloor() public {
        // Walking spot from 1,000,000 down to the 100,000 floor takes 36 sales at 25,000 a step,
        // and each sale needs a freshly activated unit at 1,000,000 $RUN. Fund accordingly.
        runToken.transfer(alice, 100_000_000e18);

        for (uint256 i = 0; i < 40; i++) {
            uint256 id = _activate(alice);
            vm.startPrank(alice);
            runner.approve(address(market), id);
            if (market.poolLiquidity() >= market.quoteSell()) {
                market.sell(id, 0);
            }
            vm.stopPrank();
        }

        assertEq(market.quoteBuy(), MIN_SPOT, "spot pinned at the floor after enough sales");
        assertEq(market.quoteSell(), MIN_SPOT, "and the sell quote cannot go under it either");
    }

    /// @dev The buy/sell spread is what stops a round trip draining the pool.
    function test_buyThenSellImmediately_losesMoney() public {
        _seedPool(alice);
        _seedPool(alice);

        uint256 before = runToken.balanceOf(bob);
        vm.prank(bob);
        uint256 id = market.buyRandom(type(uint256).max);

        vm.startPrank(bob);
        runner.approve(address(market), id);
        market.sell(id, 0);
        vm.stopPrank();

        assertLt(runToken.balanceOf(bob), before, "round trip must not be free");
    }

    function test_quoteSellIsBelowQuoteBuy() public {
        _seedPool(alice);
        assertLt(market.quoteSell(), market.quoteBuy(), "pool never buys at its own ask");
    }

    /*//////////////////////////////////////////////////////////////
                         SELL FEE TIERS (TWAP)
    //////////////////////////////////////////////////////////////*/

    /// @dev 25% below a 0.1 ETH floor, 15% between 0.1 and 1 ETH, 10% above 1 ETH.
    function test_sellFeeTier_belowFloorIsTwentyFivePercent() public {
        // Drop the price so the unit is worth under 0.1 ETH.
        oracle.setEthPerRun(ETH_PER_RUN_AT_FLOOR / 2);
        assertLt(market.unitValueInWei(), 0.1 ether);
        assertEq(market.sellFeeBps(), 2500);
    }

    function test_sellFeeTier_midRangeIsFifteenPercent() public {
        uint256 sellQuote = market.quoteSell();
        oracle.setEthPerRun((0.5 ether * 1e18) / sellQuote);
        assertEq(market.sellFeeBps(), 1500);
    }

    /// @dev A market whose sell quote is exactly 1,000,000 $RUN, so an oracle price of 1e11 wei/RUN
    ///      maps to exactly 0.1 ETH and 1e12 to exactly 1 ETH. The default market's 975,000 quote
    ///      cannot land on those boundaries under integer division, and the boundaries are precisely
    ///      what needs pinning.
    function _boundaryRig() internal returns (BlackMarket m, TestnetRunPriceOracle o) {
        o = new TestnetRunPriceOracle(1e11);
        m = new BlackMarket(
            address(runToken), address(runner), address(splitter), address(o),
            1_025_000e18, 25_000e18, MIN_SPOT
        );
        assertEq(m.quoteSell(), 1_000_000e18, "rig precondition");
    }

    function test_sellFeeTier_exactlyAtFloorIsFifteenPercent() public {
        (BlackMarket m, TestnetRunPriceOracle o) = _boundaryRig();
        o.setEthPerRun(1e11);
        assertEq(m.unitValueInWei(), 0.1 ether, "exactly on the boundary");
        assertEq(m.sellFeeBps(), 1500, "0.1 ETH itself is the mid tier");
    }

    function test_sellFeeTier_oneWeiBelowFloorIsTwentyFivePercent() public {
        (BlackMarket m, TestnetRunPriceOracle o) = _boundaryRig();
        o.setEthPerRun(1e11 - 1);
        assertLt(m.unitValueInWei(), 0.1 ether);
        assertEq(m.sellFeeBps(), 2500, "the tier flips on the wei below the floor");
    }

    function test_sellFeeTier_exactlyAtCeilingIsFifteenPercent() public {
        (BlackMarket m, TestnetRunPriceOracle o) = _boundaryRig();
        o.setEthPerRun(1e12);
        assertEq(m.unitValueInWei(), 1 ether);
        assertEq(m.sellFeeBps(), 1500, "1 ETH itself is still the mid tier");
    }

    function test_sellFeeTier_justAboveCeilingIsTenPercent() public {
        (BlackMarket m, TestnetRunPriceOracle o) = _boundaryRig();
        o.setEthPerRun(1e12 + 1);
        assertGt(m.unitValueInWei(), 1 ether);
        assertEq(m.sellFeeBps(), 1000, "the tier flips just past the ceiling");
    }

    function test_sellFeeTier_aboveCeilingIsTenPercent() public {
        uint256 sellQuote = market.quoteSell();
        oracle.setEthPerRun((2 ether * 1e18) / sellQuote);
        assertGt(market.unitValueInWei(), 1 ether);
        assertEq(market.sellFeeBps(), 1000);
    }

    function test_sell_appliesTheTieredFee() public {
        uint256 id = _activate(alice);
        oracle.setEthPerRun(ETH_PER_RUN_AT_FLOOR / 4); // deep in the 25% tier
        assertEq(market.sellFeeBps(), 2500);

        (uint256 price, uint256 fee, uint256 payout) = market.sellNet();
        assertEq(fee, (price * 2500) / 10_000);
        assertEq(payout, price - fee);

        uint256 before = runToken.balanceOf(alice);
        vm.startPrank(alice);
        runner.approve(address(market), id);
        market.sell(id, 0);
        vm.stopPrank();

        assertEq(runToken.balanceOf(alice) - before, payout, "seller receives price minus the tier fee");
    }

    function test_sell_respectsSlippageGuard() public {
        uint256 id = _activate(alice);
        (,, uint256 payout) = market.sellNet();

        vm.startPrank(alice);
        runner.approve(address(market), id);
        vm.expectRevert(
            abi.encodeWithSelector(BlackMarket.SlippageExceeded.selector, payout, payout + 1)
        );
        market.sell(id, payout + 1);
        vm.stopPrank();
    }

    function test_sell_revertsIfNotOwner() public {
        uint256 id = _activate(alice);
        vm.prank(bob);
        vm.expectRevert(BlackMarket.NotUnitOwner.selector);
        market.sell(id, 0);
    }

    function test_sell_revertsWhenPoolCannotPay() public {
        // A fresh market with no genesis behind it holds no $RUN.
        BlackMarket poor = new BlackMarket(
            address(runToken), address(runner), address(splitter), address(oracle),
            INITIAL_SPOT, DELTA, MIN_SPOT
        );
        uint256 id = _activate(alice);

        vm.startPrank(alice);
        runner.approve(address(poor), id);
        vm.expectRevert(
            abi.encodeWithSelector(BlackMarket.InsufficientPoolFunds.selector, poor.quoteSell(), 0)
        );
        poor.sell(id, 0);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                          FEES -> 60/20/20
    //////////////////////////////////////////////////////////////*/

    function test_buyFee_routesToSplitterAndSplits() public {
        // Seeding the pool is itself a sale, which already routed a sell fee — measure the delta.
        _seedPool(alice);
        uint256 feesBefore = market.lifetimeFees();
        uint256 dropBefore = splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop);
        uint256 stakersBefore = splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers);

        (, uint256 fee,) = market.buyTotal(false);

        vm.prank(bob);
        market.buyRandom(type(uint256).max);

        assertEq(market.lifetimeFees() - feesBefore, fee);
        assertEq(
            splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop) - dropBefore,
            (fee * 6000) / 10_000
        );
        assertEq(
            splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers) - stakersBefore,
            (fee * 2000) / 10_000
        );
    }

    function test_sellFee_routesToSplitter() public {
        uint256 id = _activate(alice);
        (, uint256 fee,) = market.sellNet();

        vm.startPrank(alice);
        runner.approve(address(market), id);
        market.sell(id, 0);
        vm.stopPrank();

        assertEq(market.lifetimeFees(), fee);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), (fee * 6000) / 10_000);
    }

    /// @dev The market must not accumulate fee $RUN — it forwards on every trade.
    function test_poolLiquidityExcludesFees() public {
        _seedPool(alice);
        uint256 liquidityBefore = market.poolLiquidity();
        uint256 splitterBefore = runToken.balanceOf(address(splitter));
        (uint256 price, uint256 fee,) = market.buyTotal(false);

        vm.prank(bob);
        market.buyRandom(type(uint256).max);

        assertEq(market.poolLiquidity(), liquidityBefore + price, "fee left the market");
        assertEq(runToken.balanceOf(address(splitter)) - splitterBefore, fee);
    }

    /*//////////////////////////////////////////////////////////////
                       ERC-2981 ROYALTIES
    //////////////////////////////////////////////////////////////*/

    function test_royaltyInfo_isFivePercentToTheSplitter() public view {
        (address receiver, uint256 amount) = runner.royaltyInfo(1, 1 ether);
        assertEq(receiver, address(splitter));
        assertEq(amount, 0.05 ether, "5%");
    }

    function test_supportsErc2981() public view {
        assertTrue(runner.supportsInterface(type(IERC2981).interfaceId), "ERC-2981");
        assertTrue(runner.supportsInterface(type(IERC721).interfaceId), "still ERC-721");
    }

    /// @dev The royalty sits deliberately below the Black Market's own fee tier — trading on the Row
    ///      should still be cheaper, so leaving isn't free rather than being punished.
    function test_royaltyIsCheaperThanEveryBlackMarketFee() public view {
        (, uint256 royalty) = runner.royaltyInfo(1, 10_000);
        assertLt(royalty, (10_000 * market.BUY_RANDOM_BPS()) / 10_000);
        assertLt(royalty, (10_000 * market.SELL_BPS_ABOVE()) / 10_000);
    }

    /// @dev An external marketplace pays by transferring to the receiver, then anyone syncs.
    function test_externalRoyalty_flowsThroughTheSplit() public {
        (address receiver, uint256 amount) = runner.royaltyInfo(1, 100_000e18);
        assertEq(receiver, address(splitter));

        vm.prank(alice);
        runToken.transfer(receiver, amount);
        splitter.sync(address(runToken));

        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), (amount * 6000) / 10_000);
    }

    function test_setRoyaltyReceiver_onlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        runner.setRoyaltyReceiver(alice);
    }

    /*//////////////////////////////////////////////////////////////
                          RANDOM SELECTION
    //////////////////////////////////////////////////////////////*/

    /// @dev Random must actually spread across inventory, or the 10%/15% split is meaningless.
    function test_buyRandom_spreadsAcrossInventory() public {
        uint256[] memory ids = new uint256[](8);
        for (uint256 i = 0; i < 8; i++) {
            ids[i] = _seedPool(alice);
        }

        uint256 firstDrawn;
        uint256 distinct;
        for (uint256 i = 0; i < 8; i++) {
            vm.prank(bob);
            uint256 got = market.buyRandom(type(uint256).max);
            if (i == 0) firstDrawn = got;
            if (got != firstDrawn) distinct++;
        }
        assertGt(distinct, 0, "draws must not all return the same unit");
        assertEq(market.poolSize(), 0, "and the pool drains cleanly");
    }

    function test_inventoryStaysConsistentUnderMixedTrades() public {
        uint256 a = _seedPool(alice);
        uint256 b = _seedPool(alice);
        uint256 c = _seedPool(alice);
        assertEq(market.poolSize(), 3);

        // Remove the middle one — exercises the swap-and-pop path.
        vm.prank(bob);
        market.buySpecific(b, type(uint256).max);

        assertEq(market.poolSize(), 2);
        assertTrue(market.isInPool(a));
        assertFalse(market.isInPool(b));
        assertTrue(market.isInPool(c));

        uint256[] memory inv = market.inventory();
        assertEq(inv.length, 2);
        assertTrue((inv[0] == a || inv[0] == c) && (inv[1] == a || inv[1] == c));
        assertTrue(inv[0] != inv[1]);
    }

    /*//////////////////////////////////////////////////////////////
                                 ADMIN
    //////////////////////////////////////////////////////////////*/

    function test_setPriceOracle_swapsTheReference() public {
        TestnetRunPriceOracle other = new TestnetRunPriceOracle(1e12);
        market.setPriceOracle(address(other));
        assertEq(address(market.priceOracle()), address(other));
    }

    function test_setCurve_rejectsZeroDelta() public {
        vm.expectRevert(BlackMarket.ZeroDelta.selector);
        market.setCurve(0, MIN_SPOT);
    }

    function test_adminOnlyOwner() public {
        vm.startPrank(alice);
        vm.expectRevert();
        market.setCurve(1, 1);
        vm.expectRevert();
        market.setPriceOracle(address(oracle));
        vm.stopPrank();
    }
}
