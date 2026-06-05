import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

describe("GovernanceToken (Issue #912)", function () {
  let token, phishingContract;
  let owner, user, attacker;

  beforeEach(async function () {
    [owner, user, attacker] = await ethers.getSigners();

    token = await ethers.deployContract("GovernanceToken", [
      ethers.parseEther("1000000"),
    ]);

    phishingContract = await ethers.deployContract("contracts/test/PhishingContract.sol:PhishingContract", [
      token.target,
    ]);

    // Transfer some tokens to user for testing
    await token.connect(owner).transfer(user.address, ethers.parseEther("10000"));
  });

  describe("Authorization uses msg.sender (not tx.origin)", function () {
    it("should allow a legitimate user to delegate votes", async function () {
      await token.connect(user).delegateVote(attacker.address);
      const delegate = await token.delegates(user.address);
      expect(delegate).to.equal(attacker.address);
    });

    it("should update delegatedPower when user delegates", async function () {
      const userBalance = await token.balanceOf(user.address);
      await token.connect(user).delegateVote(attacker.address);
      const power = await token.delegatedPower(attacker.address);
      expect(power).to.equal(userBalance);
    });

    it("should allow user to revoke delegate", async function () {
      await token.connect(user).delegateVote(attacker.address);
      await token.connect(user).revokeDelegate();
      const delegate = await token.delegates(user.address);
      expect(delegate).to.equal(ethers.ZeroAddress);
    });

    it("should revert revokeDelegate when no delegate exists", async function () {
      await expect(
        token.connect(user).revokeDelegate()
      ).to.be.revertedWith("No delegate");
    });

    it("should prevent self-delegation", async function () {
      await expect(
        token.connect(user).delegateVote(user.address)
      ).to.be.revertedWith("Cannot delegate to self");
    });

    it("should prevent delegation to zero address", async function () {
      await expect(
        token.connect(user).delegateVote(ethers.ZeroAddress)
      ).to.be.revertedWith("Invalid delegate address");
    });
  });

  describe("Phishing resistance (msg.sender vs tx.origin)", function () {
    it("should prevent phishing contract from delegating user's votes", async function () {
      await phishingContract.connect(user).delegateToHacker(attacker.address);

      // User's delegate should NOT be attacker
      const userDelegate = await token.delegates(user.address);
      expect(userDelegate).to.not.equal(attacker.address);
      expect(userDelegate).to.equal(ethers.ZeroAddress);

      // Attacker should have 0 delegated power from the phishing attempt
      const attackerPower = await token.delegatedPower(attacker.address);
      expect(attackerPower).to.equal(0n);
    });

    it("should allow phishing contract to delegate its own tokens if it has any", async function () {
      await token.connect(owner).transfer(phishingContract.target, ethers.parseEther("1000"));

      await phishingContract.connect(user).delegateToHacker(attacker.address);

      // User's delegate should still be untouched
      const userDelegate = await token.delegates(user.address);
      expect(userDelegate).to.equal(ethers.ZeroAddress);

      // Only the phishing contract's own tokens were delegated
      const phishingPower = await token.delegatedPower(attacker.address);
      expect(phishingPower).to.equal(ethers.parseEther("1000"));
    });
  });

  describe("onlyOwner protects admin functions", function () {
    it("should allow owner to call snapshot", async function () {
      await expect(
        token.connect(owner).snapshot()
      ).to.not.be.reverted;
    });

    it("should prevent non-owner from calling snapshot", async function () {
      await expect(
        token.connect(user).snapshot()
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount")
        .withArgs(user.address);
    });
  });

  describe("Voting and proposals still work", function () {
    it("should allow user to create and vote on proposals", async function () {
      await token.connect(user).delegateVote(user.address);

      const duration = 7 * 86400;
      await token.connect(user).createProposal("Test proposal", duration);
      await token.connect(user).vote(0, true);

      const proposal = await token.proposals(0);
      expect(proposal.forVotes).to.equal(ethers.parseEther("10000"));
    });

    it("should prevent double voting", async function () {
      await token.connect(user).delegateVote(user.address);
      const duration = 7 * 86400;
      await token.connect(user).createProposal("Test proposal", duration);
      await token.connect(user).vote(0, true);

      await expect(
        token.connect(user).vote(0, true)
      ).to.be.revertedWith("Already voted");
    });

    it("should prevent voting after proposal deadline", async function () {
      await token.connect(user).delegateVote(user.address);
      const duration = 1;
      await token.connect(user).createProposal("Test proposal", duration);

      // Increase time past deadline
      await ethers.provider.send("evm_increaseTime", [10]);
      await ethers.provider.send("evm_mine");

      await expect(
        token.connect(user).vote(0, true)
      ).to.be.revertedWith("Voting ended");
    });

    it("should prevent voting with no power", async function () {
      const duration = 7 * 86400;
      await token.connect(attacker).createProposal("Test proposal", duration);

      await expect(
        token.connect(attacker).vote(0, true)
      ).to.be.revertedWith("No voting power");
    });
  });
});
