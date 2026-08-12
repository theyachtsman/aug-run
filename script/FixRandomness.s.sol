// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {ChopShop} from "../src/chopshop/ChopShop.sol";
import {CommitRevealRandomness} from "../src/chopshop/CommitRevealRandomness.sol";

/// @notice Swap the Chop Shop's randomness source without touching the Chop Shop.
/// @dev Exercises the VRF migration path for real: the first CommitRevealRandomness recorded L1
///      block numbers against L2 block hashes and could never resolve. Replacing it is a one-call
///      change precisely because entropy sits behind IRandomnessSource.
contract FixRandomness is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address shopAddr = vm.envAddress("CHOPSHOP_ADDRESS");
        ChopShop shop = ChopShop(shopAddr);

        vm.startBroadcast(pk);
        CommitRevealRandomness rng = new CommitRevealRandomness();
        shop.setRandomnessSource(address(rng));
        vm.stopBroadcast();

        console.log("new CommitRevealRandomness", address(rng));
        console.log("shop.randomnessSource     ", address(shop.randomnessSource()));
    }
}
