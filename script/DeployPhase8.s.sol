// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Drop} from "../src/drop/Drop.sol";
import {MockRwaVenue} from "../src/drop/MockRwaVenue.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";
import {Augments} from "../src/items/Augments.sol";

/// @notice Phase 8 — the Drop. Protocol revenue becomes real-world assets in unit wallets.
/// @dev Wires the Drop as the splitter's recipient for the 60% bucket, which has been accruing
///      since phase 4. On testnet a MockRwaVenue mints stand-in stock tokens; on mainnet implement
///      IRwaVenue against real Robinhood Stock Token liquidity, priced by Chainlink Data Feeds
///      (live on Robinhood Chain), and call `Drop.setVenue`.
contract DeployPhase8 is Script {
    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        bool testnet = vm.envOr("AUGRUN_TESTNET", true);
        address runToken = vm.envAddress("RUN_ADDRESS");
        address runner = vm.envAddress("STOCKRUNNER_ADDRESS");
        address ripperdoc = vm.envAddress("RIPPERDOC_ADDRESS");
        address augmentsAddr = vm.envAddress("AUGMENTS_ADDRESS");
        address splitterAddr = vm.envAddress("SPLITTER_ADDRESS");

        console.log("chainid ", block.chainid);
        console.log("deployer", deployer);
        require(testnet || block.chainid == 4663, "set AUGRUN_TESTNET appropriately");

        RevenueSplitter splitter = RevenueSplitter(payable(splitterAddr));
        Augments augments = Augments(augmentsAddr);
        require(splitter.owner() == deployer, "deployer does not own the splitter");

        vm.startBroadcast(pk);

        MockRwaVenue venue = new MockRwaVenue();

        // One mock asset per catalog ticker so aggregate purchasing is exercisable.
        uint256 n = augments.augmentCount();
        for (uint256 i = 1; i <= n; i++) {
            string memory t = augments.tickerOf(i);
            venue.listTicker(keccak256(bytes(t)), string.concat("Mock ", t), string.concat("m", t), 1e18);
        }

        Drop drop =
            new Drop(runToken, runner, ripperdoc, augmentsAddr, splitterAddr, address(venue));

        // The 60% bucket finally has somewhere to go.
        splitter.setRecipient(RevenueSplitter.Bucket.Drop, address(drop));

        vm.stopBroadcast();

        console.log("");
        console.log("=== PHASE 8 DEPLOYED ===");
        console.log("MockRwaVenue", address(venue));
        console.log("Drop        ", address(drop));
        console.log("");
        console.log("tickers listed  ", venue.tickerCount());
        console.log("drop recipient  ", splitter.recipientOf(RevenueSplitter.Bucket.Drop));
        console.log("Drop bucket now ", splitter.accrued(runToken, RevenueSplitter.Bucket.Drop));
        console.log("CLAIM_WINDOW_LEAD", drop.CLAIM_WINDOW_LEAD());
        console.log("dustFloor (wei) ", drop.dustFloor());
    }
}
