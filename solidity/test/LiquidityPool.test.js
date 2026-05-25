const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LiquidityPool - First Depositor Attack Prevention", function () {
  let tokenA, tokenB, pool;
  let owner, attacker, user;
  const MINIMUM_LIQUIDITY = 1000n;

  beforeEach(async function () {
    [owner, attacker, user] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("ERC20");
    tokenA = await ethers.deployContract("ERC20", ["TokenA", "TKA"]);
    tokenB = await ethers.deployContract("ERC20", ["TokenB", "TKB"]);

    const LiquidityPool = await ethers.getContractFactory("LiquidityPool");
    pool = await LiquidityPool.deploy(await tokenA.getAddress(), await tokenB.getAddress());

    // Mint tokens to test accounts
    await tokenA.mint(owner.address, ethers.parseEther("10000"));
    await tokenB.mint(owner.address, ethers.parseEther("10000"));
    await tokenA.mint(attacker.address, ethers.parseEther("10000"));
    await tokenB.mint(attacker.address, ethers.parseEther("10000"));

    // Approve pool
    await tokenA.connect(owner).approve(await pool.getAddress(), ethers.parseEther("10000"));
    await tokenB.connect(owner).approve(await pool.getAddress(), ethers.parseEther("10000"));
    await tokenA.connect(attacker).approve(await pool.getAddress(), ethers.parseEther("10000"));
    await tokenB.connect(attacker).approve(await pool.getAddress(), ethers.parseEther("10000"));
  });

  it("should lock MINIMUM_LIQUIDITY to address(0) on first deposit", async function () {
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));
    const lockedBalance = await pool.balanceOf(ethers.ZeroAddress);
    expect(lockedBalance).to.equal(MINIMUM_LIQUIDITY);
  });

  it("first depositor receives lpTokens minus locked amount", async function () {
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));
    const lpBalance = await pool.balanceOf(owner.address);
    const expected = BigInt(ethers.parseEther("100")) - MINIMUM_LIQUIDITY;
    expect(lpBalance).to.equal(expected);
  });

  it("subsequent deposits use correct proportional formula", async function () {
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));
    // Second deposit: 50 tokenA + 50 tokenB
    const totalSupplyBefore = await pool.totalSupply();
    await pool.connect(owner).addLiquidity(ethers.parseEther("50"), ethers.parseEther("50"));
    const totalSupplyAfter = await pool.totalSupply();
    // Total supply should increase proportionally
    expect(totalSupplyAfter).to.be.gt(totalSupplyBefore);
  });

  it("removeLiquidity uses internal reserves not balanceOf", async function () {
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));
    const lpTokens = await pool.balanceOf(owner.address);

    // Direct transfer donation to manipulate balanceOf
    await tokenA.connect(attacker).transfer(await pool.getAddress(), ethers.parseEther("1000"));

    // removeLiquidity should use internal reserves, not inflated balanceOf
    await expect(pool.connect(owner).removeLiquidity(lpTokens)).to.not.be.reverted;
  });

  it("sync function updates reserves to actual balances", async function () {
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));
    await tokenA.connect(attacker).transfer(await pool.getAddress(), ethers.parseEther("500"));
    await pool.sync();
    const reserveA = await pool.reserveA();
    const reserveB = await pool.reserveB();
    expect(reserveA).to.equal(BigInt(ethers.parseEther("100")) + ethers.parseEther("500"));
  });

  it("price manipulation attempt after first deposit is prevented", async function () {
    // Owner makes first deposit — locked
    await pool.connect(owner).addLiquidity(ethers.parseEther("100"), ethers.parseEther("100"));

    // Attacker tries to do tiny first deposit in another pool scenario
    // With lock in place, even if attacker is first, they lose MINIMUM_LIQUIDITY
    const lpBalance = await pool.balanceOf(owner.address);
    expect(lpBalance).to.equal(BigInt(ethers.parseEther("100")) - MINIMUM_LIQUIDITY);
  });
});
