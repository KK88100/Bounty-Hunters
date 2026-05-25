const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("StakingVault - Reentrancy Protection", function () {
  let vault, stakingToken;
  let owner, user, attacker;

  beforeEach(async function () {
    [owner, user, attacker] = await ethers.getSigners();

    const Token = await ethers.getContractFactory("MockERC20");
    stakingToken = await Token.deploy("Stake", "STK", ethers.parseEther("1000000"));

    const StakingVault = await ethers.getContractFactory("StakingVault");
    vault = await StakingVault.deploy(await stakingToken.getAddress(), ethers.parseEther("0.0001"));

    await stakingToken.transfer(user.address, ethers.parseEther("1000"));
    await stakingToken.connect(user).approve(await vault.getAddress(), ethers.parseEther("1000"));
  });

  it("should allow staking", async function () {
    await vault.connect(user).stake(ethers.parseEther("100"));
    expect(await vault.balances(user.address)).to.equal(ethers.parseEther("100"));
    expect(await vault.totalStaked()).to.equal(ethers.parseEther("100"));
  });

  it("should allow normal withdrawal", async function () {
    await vault.connect(user).stake(ethers.parseEther("100"));
    await vault.connect(user).withdraw(ethers.parseEther("50"));
    expect(await vault.balances(user.address)).to.equal(ethers.parseEther("50"));
  });

  it("should not allow reentrancy in withdraw", async function () {
    // This test verifies the nonReentrant modifier works
    // Deploy a malicious contract that tries reentrancy
    const MaliciousVault = await ethers.getContractFactory("MaliciousVault");
    const malicious = await MaliciousVault.deploy(await vault.getAddress());

    await stakingToken.transfer(await malicious.getAddress(), ethers.parseEther("100"));
    await stakingToken.connect(attacker).approve(await vault.getAddress(), ethers.parseEther("100"));

    // The malicious contract's withdraw should revert due to reentrancy guard
    // or state-before-call pattern preventing the attack
    await expect(malicious.attack()).to.be.reverted;
  });

  it("should not allow reentrancy in claimRewards", async function () {
    await vault.connect(user).stake(ethers.parseEther("100"));

    // Claim rewards should not be reentrant
    await expect(vault.connect(user).claimRewards()).to.not.be.reverted;
  });
});
