// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {BlackMarket} from "../src/market/BlackMarket.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {TestnetRunPriceOracle} from "../src/market/TestnetRunPriceOracle.sol";

/// @notice Phase 4 — the Black Market, the 60/20/20 splitter, and the $RUN price reference.
/// @dev Wires the StockRunner's treasury to the Black Market (so genesis proceeds capitalise the
///      pool) and its ERC-2981 royalty receiver to the splitter.
///
///      The splitter's three bucket recipients are deliberately left unwired: the Terminal (phase 5)
///      and the Drop (phase 8) don't exist yet. Fees accrue safely in the meantime and stay
///      claimable once those land — covered by a test.
contract DeployPhase4 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        address runToken = vm.envAddress("RUN_ADDRESS");
        address runnerAddr = vm.envAddress("STOCKRUNNER_ADDRESS");

        // Curve. Spot opens at the genesis price so secondary starts where primary left off.
        uint256 initialSpot = vm.envOr("BM_INITIAL_SPOT", uint256(1_000_000e18));
        uint256 delta = vm.envOr("BM_DELTA", uint256(25_000e18));
        uint256 minSpot = vm.envOr("BM_MIN_SPOT", uint256(100_000e18));

        // 1e12 wei per $RUN puts a 1,000,000 $RUN unit at ~1 ETH, i.e. the middle sell-fee tier.
        uint256 initialEthPerRun = vm.envOr("ORACLE_ETH_PER_RUN", uint256(1e12));

        console.log("chainid    ", block.chainid);
        console.log("deployer   ", deployer);
        console.log("RUN        ", runToken);
        console.log("StockRunner", runnerAddr);

        require(runToken.code.length > 0, "RUN_ADDRESS has no code");
        require(runnerAddr.code.length > 0, "STOCKRUNNER_ADDRESS has no code");

        StockRunner runner = StockRunner(runnerAddr);
        require(runner.owner() == deployer, "deployer does not own StockRunner");

        vm.startBroadcast(pk);

        RevenueSplitter splitter = new RevenueSplitter();
        TestnetRunPriceOracle oracle = new TestnetRunPriceOracle(initialEthPerRun);
        BlackMarket market = new BlackMarket(
            runToken, runnerAddr, address(splitter), address(oracle), initialSpot, delta, minSpot
        );

        // Genesis proceeds now capitalise the Black Market pool rather than sitting in a treasury.
        runner.setTreasury(address(market));
        // External-marketplace royalties fan out 60/20/20 like every other fee.
        runner.setRoyaltyReceiver(address(splitter));

        vm.stopBroadcast();

        (address royaltyReceiver, uint256 royaltyOnOneEth) = runner.royaltyInfo(1, 1 ether);

        console.log("");
        console.log("=== PHASE 4 DEPLOYED ===");
        console.log("RevenueSplitter     ", address(splitter));
        console.log("TestnetRunPriceOracle", address(oracle));
        console.log("BlackMarket         ", address(market));
        console.log("");
        console.log("runner.treasury     ", runner.treasury());
        console.log("royalty receiver    ", royaltyReceiver);
        console.log("royalty on 1 ETH    ", royaltyOnOneEth);
        console.log("spotPrice           ", market.quoteBuy());
        console.log("quoteSell           ", market.quoteSell());
        console.log("sellFeeBps          ", market.sellFeeBps());
        console.log("unitValueInWei      ", market.unitValueInWei());
    }
}
