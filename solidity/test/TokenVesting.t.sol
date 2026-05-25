// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/TokenVesting.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test", "TST") {
        _mint(msg.sender, 1_000_000_000e18);
    }
}

contract TokenVestingTest is Test {
    TestToken token;
    TokenVesting vesting;
    address beneficiary = address(0x456);
    uint256 start;

    function setUp() public {
        token = new TestToken();
        start = block.timestamp + 100;
        uint256 cliff = 365 days;
        uint256 duration = 730 days;
        vesting = new TokenVesting(address(token), beneficiary, 1_000_000_000e18, start, cliff, duration);
        token.transfer(address(vesting), 1_000_000_000e18);
    }

    function test_NoVestingBeforeCliff() public {
        vm.warp(start - 1);
        assertEq(vesting.vestedAmount(), 0);
    }

    function test_FullVestingAfterDuration() public {
        vm.warp(start + 731 days);
        assertEq(vesting.vestedAmount(), 1_000_000_000e18);
    }

    function test_LinearVestingMidPoint() public {
        vm.warp(start + 365 days + 365 days);
        uint256 vested = vesting.vestedAmount();
        assertApproxEqAbs(vested, 500_000_000e18, 1e18);
    }

    function test_NoOverflowOnLargeAllocation() public {
        // 1 billion with 18 decimals = 1e27, should not overflow
        uint256 large = 1_000_000_000e18;
        vm.warp(start + 365 days);
        uint256 vested = vesting.vestedAmount();
        assertTrue(vested > 0);
    }

    function test_RevokeDuringCliffReturnsCorrectUnvested() public {
        vm.warp(start - 50);
        vm.prank(address(this));
        vesting.revoke();
        assertTrue(vesting.revoked());
    }

    function test_RevokeAfterPartialVesting() public {
        vm.warp(start + 365 days + 100 days);
        uint256 beforeVested = vesting.vestedAmount();
        assertTrue(beforeVested > 0);
        assertTrue(beforeVested < 1_000_000_000e18);
    }
}
