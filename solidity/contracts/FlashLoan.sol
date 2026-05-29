// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IFlashLoanReceiver {
    function onFlashLoan(address token, uint256 amount, uint256 fee, bytes calldata data) external;
}

contract FlashLoan {
    IERC20 public loanToken;
    uint256 public feeBPS; // fee in basis points
    uint256 public totalFees;
    address public owner;
    bool public paused;

    // Internal accounting to prevent rebasing token exploits
    uint256 public poolBalance;

    event FlashLoanExecuted(address indexed borrower, uint256 amount, uint256 fee);
    event Paused();
    event Unpaused();

    constructor(address _loanToken, uint256 _feeBPS) {
        loanToken = IERC20(_loanToken);
        feeBPS = _feeBPS;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }

    function flashLoan(uint256 amount, bytes calldata data) external {
        require(!paused, "Paused");
        require(amount > 0, "Amount must be > 0");

        // Max loan cap: 50% of pool balance to prevent drainage
        require(amount <= poolBalance / 2, "Exceeds max loan amount");

        uint256 fee = amount * feeBPS / 10000;
        // Minimum fee of 1 token unit prevents free flash loans
        if (fee == 0) {
            fee = 1;
        }

        loanToken.transfer(msg.sender, amount);

        IFlashLoanReceiver(msg.sender).onFlashLoan(address(loanToken), amount, fee, data);

        // Use internal accounting instead of balanceOf for rebasing token protection
        uint256 expectedBalance = poolBalance + fee;
        require(loanToken.balanceOf(address(this)) >= expectedBalance, "Loan not repaid");

        poolBalance = expectedBalance;
        totalFees += fee;
        emit FlashLoanExecuted(msg.sender, amount, fee);
    }

    function depositToPool(uint256 amount) external {
        loanToken.transferFrom(msg.sender, address(this), amount);
        poolBalance += amount;
    }

    function withdrawFees() external onlyOwner {
        uint256 fees = totalFees;
        totalFees = 0;
        loanToken.transfer(owner, fees);
        // Adjust pool balance since fees are withdrawn
        poolBalance -= fees;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    function getPoolBalance() external view returns (uint256) {
        return poolBalance;
    }
}
