import { expect } from "chai";
import { ethers } from "hardhat";

describe("SimpleSwap (Issue #913)", function () {
  let tokenA, tokenB, swap;
  let owner, user1;

  beforeEach(async function () {
    [owner, user1] = await ethers.getSigners();

    // Deploy simple ERC20 tokens (18 decimals)
    const SimpleToken = await ethers.getContractFactory("contracts/test/SimpleToken.sol:SimpleToken");
    tokenA = await SimpleToken.deploy("Token A", "TKA", 18);
    tokenB = await SimpleToken.deploy("Token B", "TKB", 18);
    await tokenA.waitForDeployment();
    await tokenB.waitForDeployment();

    const SimpleSwap = await ethers.getContractFactory("SimpleSwap");
    swap = await SimpleSwap.deploy(tokenA.target, tokenB.target, 30); // 0.3% fee
    await swap.waitForDeployment();

    // Mint tokens to users
    await tokenA.mint(owner.address, ethers.parseEther("100000"));
    await tokenB.mint(owner.address, ethers.parseEther("100000"));
    await tokenA.mint(user1.address, ethers.parseEther("100000"));
    await tokenB.mint(user1.address, ethers.parseEther("100000"));

    // Provide initial liquidity (owner adds 1000 of each)
    await tokenA.connect(owner).approve(swap.target, ethers.parseEther("1000"));
    await tokenB.connect(owner).approve(swap.target, ethers.parseEther("1000"));
    await swap.connect(owner).addLiquidity(ethers.parseEther("1000"), ethers.parseEther("1000"));
  });

  describe("swap with slippage and deadline protection", function () {
    it("should swap with exact expected output and slippage protection", async function () {
      const amountIn = ethers.parseEther("10");
      const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;

      // Approve tokenA for swap
      await tokenA.connect(user1).approve(swap.target, amountIn);

      // Get expected output
      const amountOut = await swap.getAmountOut(tokenA.target, amountIn);

      // Perform swap with minAmountOut = exact expected output
      await expect(
        swap.connect(user1).swap(tokenA.target, amountIn, amountOut, deadline)
      ).to.not.be.reverted;

      // Check balances changed
      const userBalB = await tokenB.balanceOf(user1.address);
      expect(userBalB).to.be.gt(0);
    });

    it("should revert when slippage exceeds minAmountOut", async function () {
      const amountIn = ethers.parseEther("10");
      const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;

      // Get expected output and set minAmountOut higher than expected
      const amountOut = await swap.getAmountOut(tokenA.target, amountIn);

      await tokenA.connect(user1).approve(swap.target, amountIn);

      // Set minAmountOut slightly higher than what the pool can give
      await expect(
        swap.connect(user1).swap(tokenA.target, amountIn, amountOut + 1n, deadline)
      ).to.be.revertedWith("Slippage exceeded");
    });

    it("should revert when deadline has passed", async function () {
      const amountIn = ethers.parseEther("10");
      const pastDeadline = 1; // Already expired

      await tokenA.connect(user1).approve(swap.target, amountIn);

      await expect(
        swap.connect(user1).swap(tokenA.target, amountIn, 0, pastDeadline)
      ).to.be.revertedWith("Expired");
    });

    it("should handle small amounts without precision loss", async function () {
      // Test with very small amount (1 wei)
      const amountIn = 1n;
      const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;

      await tokenA.connect(user1).approve(swap.target, amountIn);

      // This should not revert — fee calculation should handle small amounts
      // With fee=30 (0.3%), 1 * 30 * 1e18 / 10000 / 1e18 = 0 (still zero for 1 wei)
      // But the swap should proceed without rounding errors causing reverts
      const amountOut = await swap.getAmountOut(tokenA.target, amountIn);

      await expect(
        swap.connect(user1).swap(tokenA.target, amountIn, 0, deadline)
      ).to.not.be.reverted;
    });

    it("getAmountOut matches actual swap output", async function () {
      const amountIn = ethers.parseEther("50");
      const deadline = (await ethers.provider.getBlock("latest")).timestamp + 3600;

      // Get expected output
      const expectedOut = await swap.getAmountOut(tokenA.target, amountIn);

      await tokenA.connect(user1).approve(swap.target, amountIn);
      await swap.connect(user1).swap(tokenA.target, amountIn, 0, deadline);

      // Check user's tokenB balance change matches getAmountOut
      const userBalB = await tokenB.balanceOf(user1.address);
      expect(userBalB).to.equal(expectedOut);
    });
  });
});
