// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/FlashLoan.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    bool public isRebasing;

    constructor() ERC20("Mock", "MCK") {
        _mint(address(this), 1_000_000e18);
    }

    function setRebasing(bool _isRebasing) external {
        isRebasing = _isRebasing;
    }

    function balanceOf(address account) public view override returns (uint256) {
        if (isRebasing) {
            // Simulate rebasing by returning 20% less
            return super.balanceOf(account) * 80 / 100;
        }
        return super.balanceOf(account);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MockReceiver {
    address private flashLoan;
    bool public shouldRevert;

    constructor(address _flashLoan) {
        flashLoan = _flashLoan;
    }

    function onFlashLoan(address, uint256, uint256, bytes calldata) external {
        require(msg.sender == flashLoan, "Not flash loan");
        if (shouldRevert) {
            revert("Receiver reverted");
        }
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }
}

contract FlashLoanTest is Test {
    FlashLoan public flashLoan;
    MockERC20 public token;
    MockReceiver public receiver;
    address public owner = address(0x1);
    address public borrower = address(0x2);
    uint256 public feeBPS = 50; // 0.5%

    function setUp() public {
        token = new MockERC20();
        vm.prank(owner);
        flashLoan = new FlashLoan(address(token), feeBPS);
        receiver = new MockReceiver(address(flashLoan));

        // Fund the pool
        token.mint(address(flashLoan), 100_000e18);
        vm.prank(owner);
        flashLoan.depositToPool(100_000e18);
    }

    function test_MinimumFeePreventsFreeLoans() public {
        // Very small loan should have minimum fee of 1
        vm.prank(borrower);
        flashLoan.flashLoan(1, "");

        // Fee should be at least 1 token unit
        assertGe(flashLoan.totalFees(), 1);
    }

    function test_MaxLoanCapRejected() public {
        // Loan exceeding 50% of pool should be rejected
        vm.prank(borrower);
        vm.expectRevert("Exceeds max loan amount");
        flashLoan.flashLoan(60_000e18, "");
    }

    function test_LoanWithinCapAllowed() public {
        // Loan at exactly 50% of pool should be allowed
        vm.prank(borrower);
        flashLoan.flashLoan(50_000e18, "");

        // Fee should be calculated properly
        uint256 expectedFee = 50_000e18 * feeBPS / 10000;
        if (expectedFee == 0) expectedFee = 1;
        assertEq(flashLoan.totalFees(), expectedFee);
    }

    function test_RebasingTokenProtection() public {
        // Set token to "rebasing" mode that reduces balance by 20%
        token.setRebasing(true);

        // Loan should still work with internal accounting
        vm.prank(borrower);
        flashLoan.flashLoan(1000, "");

        // Pool balance should track correctly despite rebasing
        assertEq(flashLoan.getPoolBalance(), 100_000e18 + 1); // original + min fee
    }

    function test_PauseAndUnpause() public {
        vm.prank(owner);
        flashLoan.pause();

        // Flash loan should be rejected when paused
        vm.prank(borrower);
        vm.expectRevert("Paused");
        flashLoan.flashLoan(1000, "");

        vm.prank(owner);
        flashLoan.unpause();

        // Flash loan should work again
        vm.prank(borrower);
        flashLoan.flashLoan(1000, "");
        assertTrue(flashLoan.totalFees() > 0);
    }

    function test_UnauthorizedPause() public {
        vm.prank(borrower);
        vm.expectRevert("Not owner");
        flashLoan.pause();
    }

    function test_FeeAccrualTracking() public {
        // Multiple loans should accumulate fees
        vm.prank(borrower);
        flashLoan.flashLoan(10_000e18, "");

        vm.prank(borrower);
        flashLoan.flashLoan(20_000e18, "");

        uint256 expectedFee1 = 10_000e18 * feeBPS / 10000;
        if (expectedFee1 == 0) expectedFee1 = 1;
        uint256 expectedFee2 = 20_000e18 * feeBPS / 10000;
        assertEq(flashLoan.totalFees(), expectedFee1 + expectedFee2);
    }
}
