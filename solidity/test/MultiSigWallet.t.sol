// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./MultiSigWallet.sol";

contract ReentrancyAttacker {
    MultiSigWallet public wallet;
    uint256 public txId;
    bool public attackDone;

    constructor(MultiSigWallet _wallet) {
        wallet = _wallet;
    }

    function setTxId(uint256 _txId) external {
        txId = _txId;
    }

    receive() external payable {
        if (!attackDone) {
            attackDone = true;
            // Revoke confirmation during execution callback
            wallet.revokeConfirmation(txId);
        }
    }
}

contract MultiSigWalletTest is Test {
    MultiSigWallet public wallet;
    address[] public owners;
    address public owner1;
    address public owner2;
    address public owner3;
    address public attacker;
    uint256 public constant REQUIRED = 2;

    function setUp() public {
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        owner3 = makeAddr("owner3");
        attacker = makeAddr("attacker");

        owners.push(owner1);
        owners.push(owner2);
        owners.push(owner3);

        wallet = new MultiSigWallet(owners, REQUIRED);
        vm.deal(address(wallet), 10 ether);
    }

    function test_RevokeDuringCallbackPrevented() public {
        ReentrancyAttacker reentrancyTarget = new ReentrancyAttacker(wallet);

        // Submit transaction to reentrancy target
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(reentrancyTarget), 1 ether, "");

        reentrancyTarget.setTxId(txId);

        // Owner1 and owner2 confirm
        vm.prank(owner1);
        wallet.confirmTransaction(txId);
        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Execute — the callback will try to revoke but nonReentrant should prevent it
        vm.prank(owner1);
        wallet.executeTransaction(txId);

        // The transaction should have executed successfully despite revocation attempt
        assertTrue(wallet.transactions(txId).executed);
    }

    function test_ZeroAddressTransactionRejected() public {
        vm.prank(owner1);
        vm.expectRevert("Invalid recipient address");
        wallet.submitTransaction(address(0), 1 ether, "");
    }

    function test_NormalMultiSigFlow() public {
        address recipient = makeAddr("recipient");
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");
        assertEq(txId, 0);

        vm.prank(owner1);
        wallet.confirmTransaction(txId);
        assertEq(wallet.getConfirmationCount(txId), 1);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);
        assertEq(wallet.getConfirmationCount(txId), 2);

        vm.prank(owner1);
        wallet.executeTransaction(txId);
        assertTrue(wallet.transactions(txId).executed);
        assertEq(recipient.balance, 1 ether);
    }

    function test_RevokeAndReExecute() public {
        address recipient = makeAddr("recipient");
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);
        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Revoke
        vm.prank(owner2);
        wallet.revokeConfirmation(txId);
        assertEq(wallet.getConfirmationCount(txId), 1);

        // Re-confirm
        vm.prank(owner3);
        wallet.confirmTransaction(txId);
        assertEq(wallet.getConfirmationCount(txId), 2);

        vm.prank(owner1);
        wallet.executeTransaction(txId);
        assertTrue(wallet.transactions(txId).executed);
    }

    function test_IsConfirmedAtBlockWorks() public {
        address recipient = makeAddr("recipient");
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);
        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        uint256 currentBlock = block.number;
        assertTrue(wallet.isConfirmedAtBlock(txId, currentBlock));
    }
}
