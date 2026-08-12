// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ChopShop} from "../src/chopshop/ChopShop.sol";
import {MockUSDG} from "../src/chopshop/MockUSDG.sol";
import {CommitRevealRandomness} from "../src/chopshop/CommitRevealRandomness.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @notice Phase 7 — the Chop Shop, run by the Scrapper.
/// @dev Chainlink VRF does NOT support Robinhood Chain (verified against Chainlink's supported
///      networks list and by probing for LINK/coordinator on-chain), so randomness comes from a
///      commit-reveal source behind IRandomnessSource. Swap it via `setRandomnessSource` when VRF
///      lands — the Chop Shop itself needs no change.
///
///      USDG is also absent on this chain, so a MockUSDG is deployed on testnet. On mainnet pass
///      the real USDG address and deploy no mock.
contract DeployPhase7 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);
        address aug = vm.envAddress("AUG_ADDRESS");
        address splitter = vm.envAddress("SPLITTER_ADDRESS");
        address usdg = vm.envOr("USDG_ADDRESS", address(0));
        uint256 augFloat = vm.envOr("CHOPSHOP_AUG_FLOAT", uint256(1_000_000e18));

        console.log("chainid ", block.chainid);
        console.log("deployer", deployer);
        console.log("testnet ", testnet);

        if (block.chainid == 4663) {
            require(!testnet, "AUGRUN_TESTNET must be false on mainnet");
            require(usdg != address(0), "real USDG_ADDRESS required on mainnet");
        }

        vm.startBroadcast(pk);

        CommitRevealRandomness rng = new CommitRevealRandomness();

        if (usdg == address(0)) {
            require(testnet, "no USDG on a non-testnet deploy");
            usdg = address(new MockUSDG());
        }

        ChopShop shop = new ChopShop(usdg, aug, splitter, address(rng));

        // Convert payouts pay in $AUG, so the shop needs a float to draw on.
        IERC20(aug).transfer(address(shop), augFloat);

        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 7 DEPLOYED ===");
        console.log("CommitRevealRandomness", address(rng));
        console.log("MockUSDG              ", usdg);
        console.log("ChopShop              ", address(shop));
        console.log("");
        console.log("REVEAL_DELAY   ", rng.REVEAL_DELAY());
        console.log("REVEAL_WINDOW  ", rng.REVEAL_WINDOW());
        console.log("MIN_BACKING_BPS", shop.MIN_BACKING_BPS());
        console.log("ENTRY_MARKUP   ", shop.ENTRY_MARKUP_BPS());
        console.log("aug float      ", IERC20(aug).balanceOf(address(shop)));
        console.log("p(V=1000,B=1000)", shop.winProbabilityBps(1000e6, 1000e6));
        console.log("entry(V=1000,B=1000)", shop.entryCost(1000e6, 1000e6));
    }
}
