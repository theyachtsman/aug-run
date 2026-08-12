// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {StockRunner} from "../src/runner/StockRunner.sol";
import {ERC6551Account} from "../src/runner/ERC6551Account.sol";

/// @notice Phase 2 — deploy the ERC-6551 account implementation and the Stock//Runner core.
/// @dev The ERC-6551 REGISTRY is not deployed here. The canonical registry is already live on
///      Robinhood Chain testnet at 0x000000006551c19487814612e58FE06813775758 and we point at it,
///      per spec ("standard reference registry, not custom"). Only the account implementation needs
///      deploying, since Tokenbound's is absent on this chain.
contract DeployPhase2 is Script {
    address constant CANONICAL_REGISTRY = 0x000000006551c19487814612e58FE06813775758;

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);
        address runToken = vm.envAddress("RUN_ADDRESS");
        address treasury = vm.envOr("TREASURY", deployer);
        address registry = vm.envOr("ERC6551_REGISTRY", CANONICAL_REGISTRY);

        console.log("chainid   ", block.chainid);
        console.log("deployer  ", deployer);
        console.log("RUN       ", runToken);
        console.log("registry  ", registry);
        console.log("testnet   ", testnet);

        require(runToken.code.length > 0, "RUN_ADDRESS has no code");
        require(registry.code.length > 0, "ERC-6551 registry not deployed on this chain");
        if (block.chainid == 4663) {
            require(!testnet, "AUGRUN_TESTNET must be false on mainnet");
        }

        // The account implementation is generic and holds no per-deployment state, so an existing
        // one is reused when ERC6551_ACCOUNT_IMPL is set rather than deploying a duplicate.
        address existingImpl = vm.envOr("ERC6551_ACCOUNT_IMPL", address(0));

        vm.startBroadcast(pk);
        address accountImpl = existingImpl;
        if (accountImpl == address(0)) {
            accountImpl = address(new ERC6551Account());
        } else {
            require(existingImpl.code.length > 0, "ERC6551_ACCOUNT_IMPL has no code");
        }
        StockRunner runner = new StockRunner(runToken, registry, accountImpl, treasury, testnet);

        // Minting ships CLOSED. On testnet open it immediately so the harness is usable; on mainnet
        // leave it shut — $RUN launches first, the site and art land, then `openMinting()` is called
        // deliberately. That call is one-way.
        bool openNow = vm.envOr("OPEN_MINTING", testnet);
        if (openNow) {
            require(testnet, "refusing to open minting automatically on mainnet");
            runner.openMinting();
        }
        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 2 DEPLOYED ===");
        console.log("ERC6551Account impl", accountImpl);
        console.log("  (reused existing) ", existingImpl != address(0));
        console.log("StockRunner        ", address(runner));
        console.log("");
        console.log("MAX_SUPPLY   ", runner.MAX_SUPPLY());
        console.log("GENESIS_PRICE", runner.GENESIS_PRICE());
        console.log("currentCycle ", runner.currentCycle());
        console.log("TBA for #1   ", runner.tokenBoundAccount(1));
        console.log("mintingOpen  ", runner.mintingOpen());
    }
}
