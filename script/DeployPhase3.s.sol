// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Augments} from "../src/items/Augments.sol";
import {ExpansionModules} from "../src/items/ExpansionModules.sol";
import {Ripperdoc} from "../src/items/Ripperdoc.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";

/// @notice Phase 3 — Augments, Expansion Modules and the Ripperdoc, then wire them together.
/// @dev Seeds the launch catalog of twelve, four per tier. Tickers are PLACEHOLDERS: the real
///      twelve depend on what is genuinely tokenized and liquid as Stock Tokens on Robinhood Chain
///      at launch. `addAugment` appends more at any time without redeploying anything.
contract DeployPhase3 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);
        address aug = vm.envAddress("AUG_ADDRESS");
        address runnerAddr = vm.envAddress("STOCKRUNNER_ADDRESS");
        address protocolReserve = vm.envOr("PROTOCOL_RESERVE", deployer);
        string memory augUri = vm.envOr("AUGMENT_URI", string("https://augrun.local/augment/{id}.json"));
        string memory modUri = vm.envOr("MODULE_URI", string("https://augrun.local/module/{id}.json"));

        console.log("chainid        ", block.chainid);
        console.log("deployer       ", deployer);
        console.log("AUG            ", aug);
        console.log("StockRunner    ", runnerAddr);
        console.log("protocolReserve", protocolReserve);
        console.log("testnet        ", testnet);

        require(aug.code.length > 0, "AUG_ADDRESS has no code");
        require(runnerAddr.code.length > 0, "STOCKRUNNER_ADDRESS has no code");

        StockRunner runner = StockRunner(runnerAddr);
        require(runner.owner() == deployer, "deployer does not own StockRunner");
        if (block.chainid == 4663) {
            require(!testnet, "AUGRUN_TESTNET must be false on mainnet");
        }
        // On mainnet the wiring is strictly set-once, so refuse to run against an already-wired
        // StockRunner. On testnet re-pointing is allowed and expected between phases.
        if (!testnet) {
            require(runner.ripperdoc() == address(0), "ripperdoc already wired on StockRunner");
        }

        vm.startBroadcast(pk);

        Augments augments = new Augments(augUri, testnet);
        ExpansionModules modules = new ExpansionModules(modUri, testnet);
        Ripperdoc doc =
            new Ripperdoc(aug, runnerAddr, address(augments), address(modules), protocolReserve);

        // Wire. Set-once on mainnet; re-pointable by the owner on testnet.
        runner.setRipperdoc(address(doc));
        augments.setRipperdoc(address(doc));
        modules.setRipperdoc(address(doc));

        // Launch catalog: twelve, four per tier. Tier and risk stay independent — each tier spans
        // the risk spectrum so conservative operators are never structurally penalised.
        augments.addAugment("SPY", 1); //  1  broad index
        augments.addAugment("JNJ", 1); //  2  defensive
        augments.addAugment("BRKB", 1); // 3  value
        augments.addAugment("TSLA", 1); // 4  high-beta
        augments.addAugment("QQQ", 2); //  5  broad tech
        augments.addAugment("AAPL", 2); // 6  mega-cap
        augments.addAugment("KO", 2); //   7  defensive
        augments.addAugment("COIN", 2); // 8  volatile
        augments.addAugment("NVDA", 3); // 9  mega-cap momentum
        augments.addAugment("MSFT", 3); // 10 stable mega
        augments.addAugment("AMD", 3); //  11 volatile
        augments.addAugment("GLD", 3); //  12 alternative

        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 3 DEPLOYED ===");
        console.log("Augments        ", address(augments));
        console.log("ExpansionModules", address(modules));
        console.log("Ripperdoc       ", address(doc));
        console.log("");
        console.log("catalog size    ", augments.augmentCount());
        console.log("MODULE_PRICE    ", doc.MODULE_PRICE());
        console.log("CALIBRATION     ", doc.CALIBRATION_PRICE());
        console.log("runner.ripperdoc", runner.ripperdoc());
    }
}
