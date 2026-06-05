// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "../GovernanceToken.sol";

/**
 * @title PhishingContract
 * @notice Malicious contract that attempts to trick users into delegating their votes
 *         to an attacker via a seemingly benign interface.
 *         The fix (msg.sender instead of tx.origin) prevents this attack.
 */
contract PhishingContract {
    GovernanceToken public token;

    constructor(address _token) {
        token = GovernanceToken(_token);
    }

    /// @notice Attempts to delegate the caller's voting power to the attacker.
    ///         With the fix, msg.sender is this contract, not the user,
    ///         so only this contract's own (zero) balance gets delegated.
    function delegateToHacker(address attacker) external {
        // The user thinks this is a benign action,
        // but it tries to delegate their votes to the attacker.
        // With tx.origin, this would delegate the user's votes.
        // With msg.sender, it only delegates this contract's votes (which is zero).
        token.delegateVote(attacker);
    }
}
