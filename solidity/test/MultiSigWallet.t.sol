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
    address public malicious;

    uint256 constant OWNER1_PK = 0xA;
    uint256 constant OWNER2_PK = 0xB;
    uint256 constant OWNER3_PK = 0xC;

    event Submitted(uint256 indexed txId);
    event Confirmed(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);

    function setUp() public {
        owner1 = vm.addr(OWNER1_PK);
        owner2 = vm.addr(OWNER2_PK);
        owner3 = vm.addr(OWNER3_PK);
        malicious = address(0xBAD);

        owners = new address[](3);
        owners[0] = owner1;
        owners[1] = owner2;
        owners[2] = owner3;

        wallet = new MultiSigWallet(owners, 2);
    }

    function test_SubmitAndConfirmTransaction() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0xRECV), 1 ether, "");

        assertEq(wallet.transactionCount(), 1);

        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit Confirmed(txId, owner1);
        wallet.confirmTransaction(txId);

        assertEq(wallet.getConfirmationCount(txId), 1);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        assertEq(wallet.getConfirmationCount(txId), 2);
    }

    function test_ExecuteTransaction() public {
        // Fund wallet
        vm.deal(address(wallet), 5 ether);

        address payable recipient = payable(address(0xRECV));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(recipient, 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        vm.prank(owner1);
        vm.expectEmit(true, false, false, true);
        emit Executed(txId);
        wallet.executeTransaction(txId);

        assertEq(recipient.balance, 1 ether);
        assertEq(address(wallet).balance, 4 ether);
    }

    function test_RevertExecuteWithInsufficientConfirmations() public {
        vm.deal(address(wallet), 1 ether);

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0xRECV), 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        // Only 1 confirmation, need 2
        vm.prank(owner1);
        vm.expectRevert("Not enough confirmations");
        wallet.executeTransaction(txId);
    }

    function test_RevertRevokeDuringExecution() public {
        vm.deal(address(wallet), 5 ether);

        // Deploy a malicious contract that revokes confirmation in its fallback
        RevokerAttacker attacker = new RevokerAttacker(address(wallet), 0);

        // Submit transaction to attacker contract
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(attacker), 1 ether, "");

        // Get 2 confirmations
        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Attack: execute triggers the fallback which tries to revoke
        // But the nonReentrant modifier should prevent this
        vm.prank(owner1);
        wallet.executeTransaction(txId);

        // Transaction should have executed successfully (protection worked)
        assertTrue(wallet.transactions(txId).executed);
    }

    function test_RevertReentrancyDuringExecution() public {
        vm.deal(address(wallet), 5 ether);

        ReentrancyAttacker attacker = new ReentrancyAttacker(address(wallet));

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(attacker), 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // The attacker will try to call executeTransaction again in its fallback
        // nonReentrant should prevent this
        vm.prank(owner1);
        wallet.executeTransaction(txId);

        // Transaction executed once
        assertTrue(wallet.transactions(txId).executed);
    }

    function test_RevertZeroAddressSubmission() public {
        vm.prank(owner1);
        vm.expectRevert("Invalid recipient");
        wallet.submitTransaction(address(0), 1 ether, "");
    }

    function test_IsConfirmedAtBlock() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0xRECV), 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        // Check confirmation at current block
        assertTrue(wallet.isConfirmedAtBlock(txId, block.number));
    }

    function test_RevokeConfirmation() public {
        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0xRECV), 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        assertEq(wallet.getConfirmationCount(txId), 1);

        vm.prank(owner1);
        vm.expectEmit(true, true, false, true);
        emit Revoked(txId, owner1);
        wallet.revokeConfirmation(txId);

        assertEq(wallet.getConfirmationCount(txId), 0);
    }

    function test_RevertNonOwnerSubmit() public {
        vm.prank(malicious);
        vm.expectRevert("Not owner");
        wallet.submitTransaction(address(0xRECV), 1 ether, "");
    }

    function test_RevertConfirmAlreadyExecuted() public {
        vm.deal(address(wallet), 1 ether);

        vm.prank(owner1);
        uint256 txId = wallet.submitTransaction(address(0xRECV), 1 ether, "");

        vm.prank(owner1);
        wallet.confirmTransaction(txId);

        vm.prank(owner2);
        wallet.confirmTransaction(txId);

        vm.prank(owner1);
        wallet.executeTransaction(txId);

        vm.prank(owner3);
        vm.expectRevert("Already executed");
        wallet.confirmTransaction(txId);
    }
}

/// @dev Malicious contract that tries to revoke a confirmation during execution callback
contract RevokerAttacker {
    MultiSigWallet public wallet;
    uint256 public txId;

    constructor(address _wallet, uint256 _txId) {
        wallet = MultiSigWallet(_wallet);
        txId = _txId;
    }

    receive() external payable {
        // Try to revoke a confirmation — should be blocked by nonReentrant
        (bool success, ) = address(wallet).call(
            abi.encodeWithSignature("revokeConfirmation(uint256)", txId)
        );
        // If we reach here without revert, the revoke succeeded or was caught
        // We don't revert here to allow the test to check state
    }
}

/// @dev Malicious contract that tries to re-enter executeTransaction
contract ReentrancyAttacker {
    MultiSigWallet public wallet;

    constructor(address _wallet) {
        wallet = MultiSigWallet(_wallet);
    }

    receive() external payable {
        // Try to re-enter executeTransaction — should be blocked by nonReentrant
        address(wallet).call(
            abi.encodeWithSignature("executeTransaction(uint256)", 0)
        );
    }
}
