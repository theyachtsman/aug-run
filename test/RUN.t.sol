// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RUN} from "../src/tokens/RUN.sol";

contract RUNTest is Test {
    RUN internal runTestnet;
    RUN internal runMainnet;

    address internal treasury = makeAddr("treasury");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        runTestnet = new RUN(treasury, true);
        runMainnet = new RUN(treasury, false);
    }

    /*//////////////////////////////////////////////////////////////
                                SUPPLY
    //////////////////////////////////////////////////////////////*/

    function test_totalSupply_isExactlyOneBillion() public view {
        assertEq(runTestnet.totalSupply(), 1_000_000_000e18);
        assertEq(runMainnet.totalSupply(), 1_000_000_000e18);
        assertEq(runTestnet.MAX_SUPPLY(), 1_000_000_000e18);
    }

    function test_decimals_is18() public view {
        assertEq(runTestnet.decimals(), 18);
    }

    function test_mainnetDeploy_sendsEntireSupplyToTreasury() public view {
        assertEq(runMainnet.balanceOf(treasury), 1_000_000_000e18);
        assertEq(runMainnet.balanceOf(address(runMainnet)), 0, "no faucet reserve on mainnet");
    }

    function test_testnetDeploy_carvesFaucetReserveOutOfSupply() public view {
        assertEq(runTestnet.balanceOf(address(runTestnet)), runTestnet.FAUCET_ALLOCATION());
        assertEq(runTestnet.balanceOf(treasury), 1_000_000_000e18 - runTestnet.FAUCET_ALLOCATION());
        // The carve-out is a split, not an extra mint.
        assertEq(
            runTestnet.balanceOf(treasury) + runTestnet.balanceOf(address(runTestnet)),
            runTestnet.MAX_SUPPLY()
        );
    }

    function test_constructor_revertsOnZeroTreasury() public {
        vm.expectRevert(RUN.ZeroTreasury.selector);
        new RUN(address(0), true);
    }

    /// @dev $RUN has no burn and no post-construction mint, so supply is pinned for all time.
    ///      Exercise the only state-changing paths that exist and assert supply never moves.
    function test_supplyIsImmutableAcrossEveryPath() public {
        uint256 before = runTestnet.totalSupply();

        vm.prank(treasury);
        runTestnet.transfer(alice, 1_000e18);

        vm.prank(alice);
        runTestnet.approve(bob, 500e18);

        vm.prank(bob);
        runTestnet.transferFrom(alice, bob, 500e18);

        vm.prank(alice);
        runTestnet.faucet();

        assertEq(runTestnet.totalSupply(), before, "totalSupply moved");
    }

    /*//////////////////////////////////////////////////////////////
                            FAUCET GATING
    //////////////////////////////////////////////////////////////*/

    function test_faucet_revertsWhenNotTestnet() public {
        assertFalse(runMainnet.TESTNET());
        vm.prank(alice);
        vm.expectRevert(RUN.FaucetDisabled.selector);
        runMainnet.faucet();
    }

    function test_faucet_dripsFixedAllocation() public {
        vm.prank(alice);
        runTestnet.faucet();
        assertEq(runTestnet.balanceOf(alice), runTestnet.FAUCET_DRIP());
    }

    function test_faucet_dripCoversFiveGenesisMints() public view {
        // 1,000,000 $RUN per Stock//Runner — one claim should fund five.
        assertEq(runTestnet.FAUCET_DRIP(), 5 * 1_000_000e18);
    }

    function test_faucet_anyAddressMayClaim() public {
        vm.prank(alice);
        runTestnet.faucet();
        vm.prank(bob);
        runTestnet.faucet();
        assertEq(runTestnet.balanceOf(alice), runTestnet.FAUCET_DRIP());
        assertEq(runTestnet.balanceOf(bob), runTestnet.FAUCET_DRIP());
    }

    function test_faucet_enforcesCooldown() public {
        vm.prank(alice);
        runTestnet.faucet();

        uint256 availableAt = block.timestamp + runTestnet.FAUCET_COOLDOWN();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(RUN.FaucetCooldownActive.selector, availableAt));
        runTestnet.faucet();
    }

    function test_faucet_claimableAgainAfterCooldown() public {
        vm.prank(alice);
        runTestnet.faucet();

        vm.warp(block.timestamp + runTestnet.FAUCET_COOLDOWN());

        vm.prank(alice);
        runTestnet.faucet();
        assertEq(runTestnet.balanceOf(alice), 2 * runTestnet.FAUCET_DRIP());
    }

    function test_faucetAvailableAt_reportsCorrectly() public {
        assertEq(runTestnet.faucetAvailableAt(alice), 0, "never claimed => claimable now");

        vm.prank(alice);
        runTestnet.faucet();
        assertEq(runTestnet.faucetAvailableAt(alice), block.timestamp + runTestnet.FAUCET_COOLDOWN());

        vm.warp(block.timestamp + runTestnet.FAUCET_COOLDOWN());
        assertEq(runTestnet.faucetAvailableAt(alice), 0);
    }

    function test_faucet_revertsWhenDrained() public {
        // Drain the reserve down to below one drip.
        uint256 claims = runTestnet.FAUCET_ALLOCATION() / runTestnet.FAUCET_DRIP();
        for (uint256 i = 0; i < claims; i++) {
            address claimer = address(uint160(0x1000 + i));
            vm.prank(claimer);
            runTestnet.faucet();
        }
        assertEq(runTestnet.faucetRemaining(), 0);

        vm.prank(alice);
        vm.expectRevert(RUN.FaucetDrained.selector);
        runTestnet.faucet();
    }

    function test_faucetRemaining_tracksBalance() public {
        assertEq(runTestnet.faucetRemaining(), runTestnet.FAUCET_ALLOCATION());
        vm.prank(alice);
        runTestnet.faucet();
        assertEq(runTestnet.faucetRemaining(), runTestnet.FAUCET_ALLOCATION() - runTestnet.FAUCET_DRIP());
    }
}
