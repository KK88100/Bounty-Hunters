// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/SimpleSwap.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestToken is ERC20 {
    constructor() ERC20("Test", "TST") {
        _mint(msg.sender, 1_000_000e18);
    }
}

contract SimpleSwapTest is Test {
    TestToken tokenA;
    TestToken tokenB;
    SimpleSwap swap;
    address user = address(0x123);
    uint256 deadline;

    function setUp() public {
        tokenA = new TestToken();
        tokenB = new TestToken();
        swap = new SimpleSwap(address(tokenA), address(tokenB), 30);
        tokenA.transfer(user, 10000e18);
        tokenB.transfer(address(swap), 10000e18);
        tokenA.transfer(address(swap), 10000e18);
        vm.warp(1000000);
        deadline = block.timestamp + 3600;
        vm.startPrank(user);
        tokenA.approve(address(swap), type(uint256).max);
        vm.stopPrank();
    }

    function test_SwapWithExactOutput() public {
        vm.prank(user);
        uint256 out = swap.swap(address(tokenA), 1000e18, 0, deadline);
        assertGt(out, 0);
    }

    function test_SlippageReverts() public {
        vm.prank(user);
        vm.expectRevert("Slippage exceeded");
        swap.swap(address(tokenA), 1000e18, type(uint256).max, deadline);
    }

    function test_ExpiredTransactionReverts() public {
        vm.warp(block.timestamp + 7200);
        vm.prank(user);
        vm.expectRevert("Deadline exceeded");
        swap.swap(address(tokenA), 1000e18, 0, deadline);
    }
}
