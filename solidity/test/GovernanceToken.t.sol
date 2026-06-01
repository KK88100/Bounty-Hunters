// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/GovernanceToken.sol";

contract PhishingContract {
    GovernanceToken public token;

    constructor(GovernanceToken _token) {
        token = _token;
    }

    function attemptPhishingDelegate(address to) external {
        // If tx.origin was used, this would delegate the caller's vote
        // With msg.sender, it delegates this contract's vote (which has 0 balance)
        token.delegateVote(to);
    }
}

contract GovernanceTokenTest is Test {
    GovernanceToken public token;
    address public admin;
    address public alice;
    address public bob;

    function setUp() public {
        admin = makeAddr("admin");
        alice = makeAddr("alice");
        bob = makeAddr("bob");

        vm.prank(admin);
        token = new GovernanceToken(1000000 ether);

        // Transfer tokens to alice
        vm.prank(admin);
        token.transfer(alice, 1000 ether);
    }

    function test_DelegateVoteUsesMsgSender() public {
        vm.prank(alice);
        token.delegateVote(bob);

        assertEq(token.delegates(alice), bob);
        assertEq(token.getVotingPower(bob), 1000 ether);
    }

    function test_PhishingCannotDelegateOthers() public {
        // Deploy phishing contract
        PhishingContract phisher = new PhishingContract(token);

        // Alice approves and calls phisher
        vm.prank(alice);
        vm.expectRevert(); // The phisher contract has 0 balance, no voting power to delegate
        phisher.attemptPhishingDelegate(bob);

        // Alice's delegation should remain unchanged
        assertEq(token.delegates(alice), address(0));
    }

    function test_RevokeDelegateUsesMsgSender() public {
        vm.prank(alice);
        token.delegateVote(bob);
        assertEq(token.getVotingPower(bob), 1000 ether);

        vm.prank(alice);
        token.revokeDelegate();
        assertEq(token.delegates(alice), address(0));
        assertEq(token.getVotingPower(bob), 0);
    }

    function test_SnapshotOnlyOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.snapshot();

        vm.prank(admin);
        token.snapshot(); // Should succeed
    }

    function test_DelegateToSelfRejected() public {
        vm.prank(alice);
        vm.expectRevert("Cannot delegate to self");
        token.delegateVote(alice);
    }

    function test_DelegateVoteRevertsForZeroAddress() public {
        vm.prank(alice);
        vm.expectRevert("Cannot delegate to zero address");
        token.delegateVote(address(0));
    }

    function test_GovernanceProposalAndVoting() public {
        // Create proposal
        vm.prank(admin);
        uint256 proposalId = token.createProposal("Test proposal", 7 days);

        // Alice delegates to herself (implicitly, she has voting power)
        // Then votes
        vm.prank(alice);
        token.vote(proposalId, true);

        (uint256 forVotes,, , , ) = token.proposals(proposalId);
        assertEq(forVotes, 1000 ether);
    }
}
