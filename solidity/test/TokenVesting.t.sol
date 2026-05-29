// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/TokenVesting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockToken is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(address(this), 10_000_000e18);
    }
}

contract TokenVestingTest is Test {
    TokenVesting public vesting;
    MockToken public token;
    address public owner = address(0x1);
    address public beneficiary = address(0x2);
    uint256 public totalAllocation = 1_000_000e18;
    uint256 public start;
    uint256 public cliffDuration = 30 days;
    uint256 public vestingDuration = 365 days;

    function setUp() public {
        token = new MockToken();
        start = block.timestamp;
        vesting = new TokenVesting(
            address(token),
            beneficiary,
            totalAllocation,
            start,
            cliffDuration,
            vestingDuration
        );
        token.transfer(address(vesting), totalAllocation);
    }

    function test_NoOverflowForLargeAllocation() public {
        // Test with 1 billion tokens with 18 decimals
        TokenVesting largeVesting = new TokenVesting(
            address(token),
            beneficiary,
            1_000_000_000e18,
            start,
            30 days,
            365 days
        );

        // Fast forward slightly past cliff
        vm.warp(start + 31 days);

        // This should not overflow
        uint256 vested = largeVesting.vestedAmount();
        assertTrue(vested > 0);
        assertLe(vested, 1_000_000_000e18);
    }

    function test_VestedBeforeCliff() public {
        vm.warp(start + 15 days);
        assertEq(vesting.vestedAmount(), 0);
    }

    function test_VestedAfterFullDuration() public {
        vm.warp(start + vestingDuration + 1 days);
        assertEq(vesting.vestedAmount(), totalAllocation);
    }

    function test_LinearVestingAccurate() public {
        vm.warp(start + cliffDuration + (vestingDuration / 2));
        uint256 vested = vesting.vestedAmount();
        // Should be approximately half of total allocation
        uint256 expected = totalAllocation * (vestingDuration / 2 + cliffDuration) / vestingDuration;
        // Allow 1 token unit for remainder rounding
        assertApproxEqAbs(vested, expected, 1);
    }

    function test_ClaimPartialVested() public {
        vm.warp(start + 31 days);
        uint256 vested = vesting.vestedAmount();

        vm.prank(beneficiary);
        vesting.claim();

        assertEq(vesting.claimed(), vested);
    }

    function test_ClaimFullAfterVesting() public {
        vm.warp(start + vestingDuration + 1 days);

        vm.prank(beneficiary);
        vesting.claim();

        assertEq(vesting.claimed(), totalAllocation);
    }

    function test_RevokeDuringCliff() public {
        // Revoke during cliff period (before cliff)
        vm.warp(start + 15 days);

        vm.prank(owner);
        vesting.revoke();

        // Beneficiary should have claimed 0, so unvested = totalAllocation
        assertTrue(vesting.revoked());

        // During cliff, nothing was claimable, so all should be returned to owner
        // unvested = totalAllocation - claimed = totalAllocation - 0 = totalAllocation
        uint256 ownerBalance = token.balanceOf(owner);
        assertEq(ownerBalance, totalAllocation);
    }

    function test_RevokeAfterPartialClaim() public {
        vm.warp(start + 31 days);
        uint256 vested = vesting.vestedAmount();

        vm.prank(beneficiary);
        vesting.claim();

        // Revoke after partial claim
        vm.prank(owner);
        vesting.revoke();

        // unvested = totalAllocation - claimed (not totalAllocation - vested at revoke time)
        // After claim, claimed = vestedAtClaim time
        // The unvested should be totalAllocation - claimed
        uint256 unvested = totalAllocation - vested;
        // Owner should receive the unvested tokens
        assertApproxEqAbs(token.balanceOf(owner), unvested, 1);
    }

    function test_RemainderHandling() public {
        // Test that total claimed equals total allocation at vesting end
        vm.warp(start + vestingDuration + 1 days);
        vm.prank(beneficiary);
        vesting.claim();

        assertEq(vesting.claimed(), totalAllocation);
    }

    function test_RemainderAccuracy() public {
        // Use an allocation that doesn't divide evenly by duration
        TokenVesting oddVesting = new TokenVesting(
            address(token),
            beneficiary,
            1_000_000e18 + 7, // odd number
            start,
            30 days,
            365 days
        );
        token.transfer(address(oddVesting), 1_000_000e18 + 7);

        vm.warp(start + vestingDuration + 1 days);
        vm.prank(beneficiary);
        oddVesting.claim();

        // Total claimed should equal total allocation (within 1 token)
        assertApproxEqAbs(oddVesting.claimed(), 1_000_000e18 + 7, 1);
    }
}
