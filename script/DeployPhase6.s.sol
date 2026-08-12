// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {Ripperdoc} from "../src/items/Ripperdoc.sol";
import {BlackMarket} from "../src/market/BlackMarket.sol";
import {ProtocolReserve} from "../src/fixer/ProtocolReserve.sol";
import {Fixer} from "../src/fixer/Fixer.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Phase 6 — the Fixer, the protocol reserve, and a Black Market that can lend.
/// @dev The Black Market MUST be redeployed: $RUN loans "draw from and repay into the Black Market's
///      own liquidity pool", and the deployed one has no lending entry point and no generic execute.
///      Its existing pool $RUN is stranded — there is no withdraw function, by design.
///
///      Config is grouped into a struct because reading it all as locals overflows the stack.
contract DeployPhase6 is Script {
    struct Config {
        address runToken;
        address augToken;
        address runner;
        address augments;
        address ripperdoc;
        address splitter;
        address oracle;
        uint256 initialSpot;
        uint256 delta;
        uint256 minSpot;
        uint256 reserveSeed;
    }

    function _config() internal view returns (Config memory c) {
        c.runToken = vm.envAddress("RUN_ADDRESS");
        c.augToken = vm.envAddress("AUG_ADDRESS");
        c.runner = vm.envAddress("STOCKRUNNER_ADDRESS");
        c.augments = vm.envAddress("AUGMENTS_ADDRESS");
        c.ripperdoc = vm.envAddress("RIPPERDOC_ADDRESS");
        c.splitter = vm.envAddress("SPLITTER_ADDRESS");
        c.oracle = vm.envAddress("ORACLE_ADDRESS");
        c.initialSpot = vm.envOr("BM_INITIAL_SPOT", uint256(1_000_000e18));
        c.delta = vm.envOr("BM_DELTA", uint256(25_000e18));
        c.minSpot = vm.envOr("BM_MIN_SPOT", uint256(100_000e18));
        c.reserveSeed = vm.envOr("RESERVE_SEED_AUG", uint256(15_000_000e18));
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);
        Config memory c = _config();

        console.log("chainid ", block.chainid);
        console.log("deployer", deployer);

        require(StockRunner(c.runner).owner() == deployer, "deployer does not own StockRunner");
        require(Ripperdoc(c.ripperdoc).owner() == deployer, "deployer does not own Ripperdoc");

        vm.startBroadcast(pk);

        ProtocolReserve reserve = new ProtocolReserve(c.augToken);
        BlackMarket market = new BlackMarket(
            c.runToken, c.runner, c.splitter, c.oracle, c.initialSpot, c.delta, c.minSpot
        );
        Fixer fixer = new Fixer(
            c.runToken, c.augToken, c.runner, c.augments, address(market), address(reserve), c.splitter
        );

        // Genesis proceeds now capitalise the NEW pool.
        StockRunner(c.runner).setTreasury(address(market));
        // The Fixer may draw pool $RUN and reserve $AUG.
        market.setFixer(address(fixer));
        reserve.setFixer(address(fixer));
        // Half of every Ripperdoc payment now lands in a real reserve contract, not an EOA.
        Ripperdoc(c.ripperdoc).setProtocolReserve(address(reserve));

        // Seed the reserve with the spec's 15% allocation so $AUG loans can actually be funded.
        IERC20(c.augToken).transfer(address(reserve), c.reserveSeed);

        vm.stopBroadcast();

        _report(c, address(reserve), address(market), address(fixer));
    }

    function _report(Config memory c, address reserve, address market, address fixer) internal view {
        console.log("");
        console.log("=== PHASE 6 DEPLOYED ===");
        console.log("ProtocolReserve", reserve);
        console.log("BlackMarket(v2)", market);
        console.log("Fixer          ", fixer);
        console.log("");
        console.log("runner.treasury", StockRunner(c.runner).treasury());
        console.log("market.fixer   ", BlackMarket(market).fixer());
        console.log("reserve.fixer  ", ProtocolReserve(reserve).fixer());
        console.log("doc.reserve    ", Ripperdoc(c.ripperdoc).protocolReserve());
        console.log("reserve balance", ProtocolReserve(reserve).balance());
        console.log("maxLendBps     ", BlackMarket(market).maxLendBps());
        console.log("OPENING_LTV_BPS", Fixer(payable(fixer)).OPENING_LTV_BPS());
        console.log("ICE_LTV_BPS    ", Fixer(payable(fixer)).ICE_LTV_BPS());
        console.log("AUG_APR_BPS    ", Fixer(payable(fixer)).AUG_APR_BPS());
    }
}
