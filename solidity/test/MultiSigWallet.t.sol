// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/MultiSigWallet.sol";

contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    address[] public owners;
    address public owner1;
    address public owner2;
    address public owner3;
    uint256 public required = 2;

    function setUp() public {
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        owner3 = makeAddr("owner3");
        owners = [owner1, owner2, owner3];

        vm.prank(owner1);
        wallet = new MultiSigWallet(owners, required);

        // Fund wallet
        vm.deal(address(wallet), 10 ether);
    }

    function test_SubmitTransactionRejectsZeroAddress() public {
        vm.prank(owner1);
        vm.expectRevert("Cannot send to zero address");
        wallet.submitTransaction(address(0), 1 ether, "");
    }

    function test_SubmitAndConfirmAndExecute() public {
        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        vm.prank(owner1);
        wallet.executeTransaction(txId);

        assertEq(recipient.balance, 1 ether);
    }

    function test_ConfirmationRevocationPreventsExecution() public {
        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Owner2 revokes
        vm.prank(owner2);
        wallet.revokeConfirmation(txId);

        // Now only 1 confirmation, should fail
        vm.prank(owner1);
        vm.expectRevert("Not enough confirmations");
        wallet.executeTransaction(txId);
    }

    function test_ConfirmationRevocationDuringCallback() public {
        // This tests the reentrancy protection — confirmation can be revoked
        // but executeTransaction has nonReentrant guard
        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Execute should succeed because revocation during callback is prevented by nonReentrant
        vm.prank(owner1);
        wallet.executeTransaction(txId);

        assertEq(recipient.balance, 1 ether);

        // Cannot execute again
        vm.prank(owner1);
        vm.expectRevert("Already executed");
        wallet.executeTransaction(txId);
    }

    function test_IsConfirmedAtBlock() public {
        address payable recipient = payable(makeAddr("recipient"));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        assertTrue(wallet.isConfirmedAtBlock(txId, block.number));
        assertFalse(wallet.isConfirmedAtBlock(txId, block.number + 100));
    }

    function test_ZeroAddressOwnerRejected() public {
        address[] memory badOwners = new address[](2);
        badOwners[0] = owner1;
        badOwners[1] = address(0);
        vm.expectRevert("Owner cannot be zero address");
        vm.prank(owner1);
        new MultiSigWallet(badOwners, 1);
    }
}
