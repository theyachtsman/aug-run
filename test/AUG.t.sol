// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {AUG} from "../src/tokens/AUG.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";

contract AUGTest is Test {
    AUG internal augTestnet;
    AUG internal augMainnet;

    address internal circulating = makeAddr("circulating");
    address internal protocolReserve = makeAddr("protocolReserve");
    address internal launchSeed = makeAddr("launchSeed");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        augTestnet = new AUG(circulating, protocolReserve, launchSeed, true);
        augMainnet = new AUG(circulating, protocolReserve, launchSeed, false);
    }

    /*//////////////////////////////////////////////////////////////
                            SUPPLY & SPLIT
    //////////////////////////////////////////////////////////////*/

    function test_totalSupply_isExactlyOneHundredMillion() public view {
        assertEq(augTestnet.totalSupply(), 100_000_000e18);
        assertEq(augMainnet.totalSupply(), 100_000_000e18);
    }

    function test_decimals_is18() public view {
        assertEq(augTestnet.decimals(), 18);
    }

    /// @dev Spec: 80% circulating / 15% protocol reserve / 5% launch seed.
    function test_mainnetDeploy_splitsEightyFifteenFive() public view {
        assertEq(augMainnet.balanceOf(circulating), 80_000_000e18);
        assertEq(augMainnet.balanceOf(protocolReserve), 15_000_000e18);
        assertEq(augMainnet.balanceOf(launchSeed), 5_000_000e18);
        assertEq(augMainnet.balanceOf(address(augMainnet)), 0, "no faucet reserve on mainnet");
    }

    function test_allocationsSumToInitialSupply() public view {
        assertEq(
            augMainnet.CIRCULATING_ALLOCATION() + augMainnet.RESERVE_ALLOCATION()
                + augMainnet.SEED_ALLOCATION(),
            augMainnet.INITIAL_SUPPLY()
        );
    }

    /// @dev The faucet must come out of the circulating slice — never out of the protocol reserve,
    ///      which phase 3 relies on being exactly 15%.
    function test_testnetFaucet_comesOutOfCirculatingNotReserve() public view {
        assertEq(augTestnet.balanceOf(protocolReserve), 15_000_000e18, "reserve must be untouched");
        assertEq(augTestnet.balanceOf(launchSeed), 5_000_000e18, "seed must be untouched");
        assertEq(
            augTestnet.balanceOf(circulating),
            80_000_000e18 - augTestnet.FAUCET_ALLOCATION(),
            "faucet carved from circulating"
        );
        assertEq(augTestnet.balanceOf(address(augTestnet)), augTestnet.FAUCET_ALLOCATION());
    }

    function test_constructor_revertsOnZeroRecipient() public {
        vm.expectRevert(AUG.ZeroRecipient.selector);
        new AUG(address(0), protocolReserve, launchSeed, true);

        vm.expectRevert(AUG.ZeroRecipient.selector);
        new AUG(circulating, address(0), launchSeed, true);

        vm.expectRevert(AUG.ZeroRecipient.selector);
        new AUG(circulating, protocolReserve, address(0), true);
    }

    /*//////////////////////////////////////////////////////////////
                                 BURN
    //////////////////////////////////////////////////////////////*/

    function test_burn_reducesTotalSupplyExactly() public {
        uint256 before = augMainnet.totalSupply();

        vm.prank(circulating);
        augMainnet.burn(1_000e18);

        assertEq(augMainnet.totalSupply(), before - 1_000e18);
        assertEq(augMainnet.balanceOf(circulating), 80_000_000e18 - 1_000e18);
    }

    function test_burnFrom_respectsAllowance() public {
        vm.prank(circulating);
        augMainnet.transfer(alice, 1_000e18);

        vm.prank(alice);
        augMainnet.approve(bob, 400e18);

        uint256 before = augMainnet.totalSupply();
        vm.prank(bob);
        augMainnet.burnFrom(alice, 400e18);

        assertEq(augMainnet.totalSupply(), before - 400e18);
        assertEq(augMainnet.allowance(alice, bob), 0);
    }

    function test_burnFrom_revertsWithoutAllowance() public {
        vm.prank(circulating);
        augMainnet.transfer(alice, 1_000e18);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, bob, 0, 100e18)
        );
        augMainnet.burnFrom(alice, 100e18);
    }

    function test_burn_isOneWay_supplyNeverRecovers() public {
        vm.prank(circulating);
        augMainnet.burn(5_000e18);
        uint256 afterBurn = augMainnet.totalSupply();

        // Every remaining state-changing path, none of which may re-mint.
        vm.prank(circulating);
        augMainnet.transfer(alice, 1e18);
        vm.prank(alice);
        augMainnet.approve(bob, 1e18);
        vm.prank(bob);
        augMainnet.transferFrom(alice, bob, 1e18);

        assertEq(augMainnet.totalSupply(), afterBurn);
        assertLt(augMainnet.totalSupply(), augMainnet.INITIAL_SUPPLY());
    }

    function testFuzz_burn_reducesSupplyByExactAmount(uint256 amount) public {
        amount = bound(amount, 0, 80_000_000e18);
        uint256 before = augMainnet.totalSupply();

        vm.prank(circulating);
        augMainnet.burn(amount);

        assertEq(augMainnet.totalSupply(), before - amount);
    }

    /*//////////////////////////////////////////////////////////////
                            FAUCET GATING
    //////////////////////////////////////////////////////////////*/

    function test_faucet_revertsWhenNotTestnet() public {
        assertFalse(augMainnet.TESTNET());
        vm.prank(alice);
        vm.expectRevert(AUG.FaucetDisabled.selector);
        augMainnet.faucet();
    }

    function test_faucet_dripsFixedAllocation() public {
        vm.prank(alice);
        augTestnet.faucet();
        assertEq(augTestnet.balanceOf(alice), augTestnet.FAUCET_DRIP());
    }

    function test_faucet_dripCoversTwentyTierThreeAugments() public view {
        // Tier 3 costs 500 $AUG.
        assertEq(augTestnet.FAUCET_DRIP(), 20 * 500e18);
    }

    function test_faucet_enforcesCooldown() public {
        vm.prank(alice);
        augTestnet.faucet();

        uint256 availableAt = block.timestamp + augTestnet.FAUCET_COOLDOWN();

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(AUG.FaucetCooldownActive.selector, availableAt));
        augTestnet.faucet();
    }

    function test_faucet_claimableAgainAfterCooldown() public {
        vm.prank(alice);
        augTestnet.faucet();

        vm.warp(block.timestamp + augTestnet.FAUCET_COOLDOWN());

        vm.prank(alice);
        augTestnet.faucet();
        assertEq(augTestnet.balanceOf(alice), 2 * augTestnet.FAUCET_DRIP());
    }

    /// @dev The faucet transfers pre-funded tokens; it must never inflate supply.
    function test_faucet_doesNotMint() public {
        uint256 before = augTestnet.totalSupply();
        vm.prank(alice);
        augTestnet.faucet();
        assertEq(augTestnet.totalSupply(), before);
    }
}
