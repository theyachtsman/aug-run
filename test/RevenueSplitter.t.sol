// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {RUN} from "../src/tokens/RUN.sol";
import {RevenueSplitter} from "../src/market/RevenueSplitter.sol";

contract RevenueSplitterTest is Test {
    RUN internal runToken;
    RevenueSplitter internal splitter;

    address internal dropRecipient = makeAddr("drop");
    address internal stakerRecipient = makeAddr("stakers");
    address internal lpRecipient = makeAddr("lps");
    address internal payer = makeAddr("payer");

    address constant ETH = address(0);

    function setUp() public {
        runToken = new RUN(address(this), true);
        splitter = new RevenueSplitter();

        splitter.setRecipient(RevenueSplitter.Bucket.Drop, dropRecipient);
        splitter.setRecipient(RevenueSplitter.Bucket.Stakers, stakerRecipient);
        splitter.setRecipient(RevenueSplitter.Bucket.Lps, lpRecipient);

        runToken.transfer(payer, 1_000_000e18);
        vm.prank(payer);
        runToken.approve(address(splitter), type(uint256).max);
    }

    /*//////////////////////////////////////////////////////////////
                             THE 60/20/20
    //////////////////////////////////////////////////////////////*/

    function test_deposit_splitsSixtyTwentyTwenty() public {
        vm.prank(payer);
        splitter.deposit(address(runToken), 1000e18);

        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 600e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers), 200e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Lps), 200e18);
        assertEq(splitter.pending(address(runToken)), 1000e18);
    }

    /// @dev Nothing may be lost to rounding — the remainder goes to LPs.
    function testFuzz_splitIsLossless(uint256 amount) public {
        amount = bound(amount, 1, 1_000_000e18);

        vm.prank(payer);
        splitter.deposit(address(runToken), amount);

        uint256 d = splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop);
        uint256 s = splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers);
        uint256 l = splitter.accrued(address(runToken), RevenueSplitter.Bucket.Lps);

        assertEq(d + s + l, amount, "split must be exact");
        assertEq(d, (amount * 6000) / 10_000);
        assertEq(s, (amount * 2000) / 10_000);
    }

    function test_oddAmount_remainderGoesToLps() public {
        // 7 wei: 60% = 4 (floor), 20% = 1 (floor), remainder 2 to LPs.
        vm.prank(payer);
        splitter.deposit(address(runToken), 7);

        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 4);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers), 1);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Lps), 2);
    }

    /*//////////////////////////////////////////////////////////////
                    ROYALTIES ARRIVE AS RAW TRANSFERS
    //////////////////////////////////////////////////////////////*/

    /// @dev An external marketplace paying an ERC-2981 royalty just transfers to the receiver — it
    ///      never calls a function. `sync` is what turns that into a split.
    function test_sync_picksUpRawErc20Transfer() public {
        vm.prank(payer);
        runToken.transfer(address(splitter), 500e18);

        assertEq(splitter.unaccounted(address(runToken)), 500e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 0);

        splitter.sync(address(runToken));

        assertEq(splitter.unaccounted(address(runToken)), 0);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 300e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Stakers), 100e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Lps), 100e18);
    }

    function test_sync_picksUpRawEth() public {
        vm.deal(payer, 10 ether);
        vm.prank(payer);
        (bool ok,) = address(splitter).call{value: 1 ether}("");
        assertTrue(ok, "splitter must accept ETH");

        assertEq(splitter.unaccounted(ETH), 1 ether);
        splitter.sync(ETH);

        assertEq(splitter.accrued(ETH, RevenueSplitter.Bucket.Drop), 0.6 ether);
        assertEq(splitter.accrued(ETH, RevenueSplitter.Bucket.Stakers), 0.2 ether);
        assertEq(splitter.accrued(ETH, RevenueSplitter.Bucket.Lps), 0.2 ether);
    }

    function test_sync_isPermissionless() public {
        vm.prank(payer);
        runToken.transfer(address(splitter), 100e18);

        vm.prank(makeAddr("randomer"));
        splitter.sync(address(runToken));

        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 60e18);
    }

    function test_sync_revertsWhenNothingUnaccounted() public {
        vm.expectRevert(RevenueSplitter.NothingToSync.selector);
        splitter.sync(address(runToken));
    }

    /// @dev A second sync must not double-count what the first already split.
    function test_sync_doesNotDoubleCount() public {
        vm.prank(payer);
        runToken.transfer(address(splitter), 100e18);
        splitter.sync(address(runToken));

        vm.expectRevert(RevenueSplitter.NothingToSync.selector);
        splitter.sync(address(runToken));

        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 60e18);
    }

    /*//////////////////////////////////////////////////////////////
                                 CLAIM
    //////////////////////////////////////////////////////////////*/

    function test_claim_paysTheRecipient() public {
        vm.prank(payer);
        splitter.deposit(address(runToken), 1000e18);

        vm.prank(dropRecipient);
        splitter.claim(address(runToken), RevenueSplitter.Bucket.Drop);

        assertEq(runToken.balanceOf(dropRecipient), 600e18);
        assertEq(splitter.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 0);
        assertEq(splitter.pending(address(runToken)), 400e18, "other buckets still owed");
    }

    function test_claim_eth() public {
        vm.deal(payer, 10 ether);
        vm.prank(payer);
        (bool ok,) = address(splitter).call{value: 1 ether}("");
        assertTrue(ok);
        splitter.sync(ETH);

        vm.prank(stakerRecipient);
        splitter.claim(ETH, RevenueSplitter.Bucket.Stakers);
        assertEq(stakerRecipient.balance, 0.2 ether);
    }

    function test_claim_onlyByWiredRecipient() public {
        vm.prank(payer);
        splitter.deposit(address(runToken), 1000e18);

        vm.prank(lpRecipient);
        vm.expectRevert(RevenueSplitter.NotRecipient.selector);
        splitter.claim(address(runToken), RevenueSplitter.Bucket.Drop);
    }

    function test_claim_revertsWithoutRecipientWired() public {
        RevenueSplitter fresh = new RevenueSplitter();
        vm.expectRevert(RevenueSplitter.NoRecipient.selector);
        fresh.claim(address(runToken), RevenueSplitter.Bucket.Drop);
    }

    function test_claim_revertsWhenNothingAccrued() public {
        vm.prank(dropRecipient);
        vm.expectRevert(RevenueSplitter.NothingToClaim.selector);
        splitter.claim(address(runToken), RevenueSplitter.Bucket.Drop);
    }

    /// @dev Value accrued before recipients exist is not lost — phases 5 and 8 wire in later and
    ///      claim whatever built up in the meantime.
    function test_accrualSurvivesUntilRecipientsAreWired() public {
        RevenueSplitter fresh = new RevenueSplitter();
        vm.prank(payer);
        runToken.transfer(address(fresh), 1000e18);
        fresh.sync(address(runToken));

        assertEq(fresh.accrued(address(runToken), RevenueSplitter.Bucket.Drop), 600e18);

        address lateDrop = makeAddr("dropV1");
        fresh.setRecipient(RevenueSplitter.Bucket.Drop, lateDrop);

        vm.prank(lateDrop);
        fresh.claim(address(runToken), RevenueSplitter.Bucket.Drop);
        assertEq(runToken.balanceOf(lateDrop), 600e18);
    }

    function test_setRecipient_onlyOwner() public {
        vm.prank(payer);
        vm.expectRevert();
        splitter.setRecipient(RevenueSplitter.Bucket.Drop, payer);
    }

    /// @dev Claiming one asset must not disturb another's accounting.
    function test_assetsAreAccountedIndependently() public {
        vm.prank(payer);
        splitter.deposit(address(runToken), 1000e18);

        vm.deal(address(splitter), 1 ether);
        splitter.sync(ETH);

        vm.prank(dropRecipient);
        splitter.claim(address(runToken), RevenueSplitter.Bucket.Drop);

        assertEq(splitter.accrued(ETH, RevenueSplitter.Bucket.Drop), 0.6 ether, "ETH untouched");
        assertEq(splitter.pending(ETH), 1 ether);
    }
}
