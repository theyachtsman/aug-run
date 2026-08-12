// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Terminal} from "../src/terminal/Terminal.sol";
import {MockLpToken} from "../src/terminal/MockLpToken.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";

/// @notice Phase 5 — the Terminal. $AUG staking and LP rewards.
/// @dev Wires the Terminal as the splitter's recipient for the Stakers and LPs buckets, which is
///      what finally makes 40% of every fee claimable. The Drop bucket (60%) stays unwired until
///      phase 8 and keeps accruing safely.
///
///      On testnet a MockLpToken is deployed so the LP pool is exercisable. On mainnet, skip it and
///      call `setLpToken` with the real Uniswap-V2-style pair token — a V3 position is an ERC-721
///      and will not work here.
contract DeployPhase5 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);
        address aug = vm.envAddress("AUG_ADDRESS");
        address runToken = vm.envAddress("RUN_ADDRESS");
        address splitterAddr = vm.envAddress("SPLITTER_ADDRESS");

        console.log("chainid ", block.chainid);
        console.log("deployer", deployer);
        console.log("AUG     ", aug);
        console.log("RUN     ", runToken);
        console.log("splitter", splitterAddr);
        console.log("testnet ", testnet);

        require(aug.code.length > 0, "AUG_ADDRESS has no code");
        require(runToken.code.length > 0, "RUN_ADDRESS has no code");
        require(splitterAddr.code.length > 0, "SPLITTER_ADDRESS has no code");

        RevenueSplitter splitter = RevenueSplitter(payable(splitterAddr));
        require(splitter.owner() == deployer, "deployer does not own the splitter");
        if (block.chainid == 4663) {
            require(!testnet, "AUGRUN_TESTNET must be false on mainnet");
        }

        vm.startBroadcast(pk);

        Terminal terminal = new Terminal(aug, runToken, splitterAddr);

        address lpToken;
        if (testnet) {
            lpToken = address(new MockLpToken());
            terminal.setLpToken(lpToken);
        }

        // 20% stakers + 20% LPs now flow to the Terminal.
        splitter.setRecipient(RevenueSplitter.Bucket.Stakers, address(terminal));
        splitter.setRecipient(RevenueSplitter.Bucket.Lps, address(terminal));

        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 5 DEPLOYED ===");
        console.log("Terminal        ", address(terminal));
        console.log("MockLpToken     ", lpToken);
        console.log("");
        console.log("REWARD_DURATION ", terminal.REWARD_DURATION());
        console.log("stakers recipient", splitter.recipientOf(RevenueSplitter.Bucket.Stakers));
        console.log("lps recipient   ", splitter.recipientOf(RevenueSplitter.Bucket.Lps));
        console.log("drop recipient  ", splitter.recipientOf(RevenueSplitter.Bucket.Drop));
        console.log("stakers claimable", splitter.accrued(runToken, RevenueSplitter.Bucket.Stakers));
        console.log("lps claimable   ", splitter.accrued(runToken, RevenueSplitter.Bucket.Lps));
    }
}
