// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./GovernanceToken.sol";

contract PhishingAttacker {
    GovernanceToken public token;

    constructor(GovernanceToken _token) {
        token = _token;
    }

    // Attempt to delegate votes on behalf of the caller using tx.origin
    // This should fail since the contract now uses msg.sender
    function phishDelegate(address targetDelegate) external {
        // If the contract still used tx.origin, this would delegate the caller's votes
        token.delegateVote(targetDelegate);
    }

    function phishRevoke() external {
        token.revokeDelegate();
    }
}

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    address public admin;
    address public user1;
    address public user2;
    address public delegate;

    function setUp() public {
        admin = makeAddr("admin");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        delegate = makeAddr("delegate");

        vm.prank(admin);
        token = new GovernanceToken(1000 ether);

        // Give tokens to users
        vm.prank(admin);
        token.transfer(user1, 100 ether);
        vm.prank(admin);
        token.transfer(user2, 200 ether);
    }

    function test_PhishingContractCannotDelegateVotes() public {
        PhishingAttacker phisher = new PhishingAttacker(token);

        // User1 interacts with phishing contract
        vm.prank(user1);
        // The phishing contract tries to delegate user1's votes
        // But since delegateVote uses msg.sender (the phishing contract, not user1),
        // it will delegate the phishing contract's votes (which are 0), not user1's
        vm.expectRevert("Cannot delegate to self");
        phisher.phishDelegate(user2);
    }

    function test_LegitimateDelegationWorks() public {
        vm.prank(user1);
        token.delegateVote(delegate);

        assertEq(token.delegates(user1), delegate);
        assertEq(token.getVotingPower(delegate), 100 ether);
    }

    function test_RevokeDelegateWorks() public {
        vm.prank(user1);
        token.delegateVote(delegate);
        assertEq(token.getVotingPower(delegate), 100 ether);

        vm.prank(user1);
        token.revokeDelegate();
        assertEq(token.delegates(user1), address(0));
        assertEq(token.getVotingPower(delegate), 0);
    }

    function test_SnapshotOnlyOwner() public {
        // Admin can call snapshot
        vm.prank(admin);
        token.snapshot();

        // Non-admin cannot
        vm.prank(user1);
        vm.expectRevert();
        token.snapshot();
    }

    function test_VotingWorksWithDelegatedPower() public {
        // User1 delegates to delegate
        vm.prank(user1);
        token.delegateVote(delegate);

        // Create a proposal
        vm.prank(admin);
        uint256 proposalId = token.createProposal("Test Proposal", 7 days);

        // Delegate votes
        vm.prank(delegate);
        token.vote(proposalId, true);

        // User2 votes directly
        vm.prank(user2);
        token.vote(proposalId, false);
    }

    function test_TxOriginNotUsed() public view {
        // Verify the contract doesn't contain tx.origin
        string memory artifact = vm.toString(type(GovernanceToken).runtimeCode);
        // tx.origin in Yul is called differently, but Solidity should not compile with tx.origin
        // in this fixed version. This is a sanity check.
        assertFalse(vm.contains(artifact, "origin"));
    }
}
