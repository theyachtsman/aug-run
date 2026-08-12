// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {RUN} from "../src/tokens/RUN.sol";
import {AUG} from "../src/tokens/AUG.sol";

/// @notice Phase 1 — deploy $RUN and $AUG.
/// @dev Run via `bin/deploy.sh phase1`, which sources the key from ~/.aug_run/.env.
///
///      TESTNET flag: driven by the AUGRUN_TESTNET env var, default true. A mainnet
///      deployment MUST set AUGRUN_TESTNET=false, which disables both faucets and
///      routes the full supply to the configured recipients.
contract DeployPhase1 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);

        // On testnet these all default to the deployer so one wallet can drive the whole harness.
        address treasury = vm.envOr("TREASURY", deployer);
        address circulating = vm.envOr("AUG_CIRCULATING", deployer);
        address protocolReserve = vm.envOr("PROTOCOL_RESERVE", deployer);
        address launchSeed = vm.envOr("LAUNCH_SEED", deployer);

        console.log("chainid          ", block.chainid);
        console.log("deployer         ", deployer);
        console.log("deployer balance ", deployer.balance);
        console.log("testnet mode     ", testnet);

        require(deployer.balance > 0, "deployer has no gas");
        if (block.chainid == 4663) {
            require(!testnet, "AUGRUN_TESTNET must be false on mainnet");
        }

        // $RUN is unaffected by anything downstream, so an existing deployment is reused when
        // RUN_ADDRESS is set. Keeps balances and approvals intact across an $AUG redeploy.
        address existingRun = vm.envOr("RUN_ADDRESS", address(0));

        vm.startBroadcast(pk);
        RUN runToken;
        if (existingRun == address(0)) {
            runToken = new RUN(treasury, testnet);
        } else {
            require(existingRun.code.length > 0, "RUN_ADDRESS has no code");
            runToken = RUN(existingRun);
        }
        AUG augToken = new AUG(circulating, protocolReserve, launchSeed, testnet);
        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 1 DEPLOYED ===");
        console.log("RUN              ", address(runToken));
        console.log("  (reused)       ", existingRun != address(0));
        console.log("AUG              ", address(augToken));
        console.log("");
        console.log("RUN total supply   ", runToken.totalSupply());
        console.log("RUN faucet reserve ", runToken.faucetRemaining());
        console.log("AUG total supply   ", augToken.totalSupply());
        console.log("AUG faucet pot     ", augToken.faucetRemaining());
    }
}
