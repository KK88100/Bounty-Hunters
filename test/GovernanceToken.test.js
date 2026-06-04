import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

describe("GovernanceToken", function () {
  let token, owner, alice, bob, phishing, addr1;
  const INITIAL_SUPPLY = ethers.parseEther("10000");

  beforeEach(async function () {
    [owner, alice, bob, phishing, addr1] = await ethers.getSigners();
    const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
    token = await GovernanceToken.deploy(INITIAL_SUPPLY);
    await token.waitForDeployment();
  });

  describe("Deployment", function () {
    it("should mint initial supply to owner", async function () {
      expect(await token.balanceOf(owner.address)).to.equal(INITIAL_SUPPLY);
    });

    it("should set admin and owner correctly", async function () {
      expect(await token.admin()).to.equal(owner.address);
      expect(await token.owner()).to.equal(owner.address);
    });
  });

  describe("Delegation (msg.sender protection)", function () {
    it("should delegate voting power using msg.sender", async function () {
      const amount = ethers.parseEther("1000");
      await token.connect(owner).transfer(alice.address, amount);
      expect(await token.balanceOf(alice.address)).to.equal(amount);

      await token.connect(alice).delegateVote(bob.address);
      expect(await token.delegates(alice.address)).to.equal(bob.address);
      expect(await token.delegatedPower(bob.address)).to.equal(amount);
      expect(await token.getVotingPower(bob.address)).to.equal(
        (await token.balanceOf(bob.address)) + amount
      );
    });

    it("should prevent self-delegation", async function () {
      await expect(
        token.connect(owner).delegateVote(owner.address)
      ).to.be.revertedWith("Cannot delegate to self");
    });

    it("should revoke delegation using msg.sender", async function () {
      const amount = ethers.parseEther("500");
      await token.connect(owner).transfer(alice.address, amount);
      await token.connect(alice).delegateVote(bob.address);
      expect(await token.delegatedPower(bob.address)).to.equal(amount);

      await token.connect(alice).revokeDelegate();
      expect(await token.delegatedPower(bob.address)).to.equal(0);
      expect(await token.delegates(alice.address)).to.equal(ethers.ZeroAddress);
    });

    it("should fail revoke with no delegate", async function () {
      await expect(
        token.connect(owner).revokeDelegate()
      ).to.be.revertedWith("No delegate");
    });

    it("should update delegation when switching delegates", async function () {
      const amount = ethers.parseEther("1000");
      await token.connect(owner).transfer(alice.address, amount);
      await token.connect(alice).delegateVote(bob.address);
      expect(await token.delegatedPower(bob.address)).to.equal(amount);

      await token.connect(alice).delegateVote(phishing.address);
      expect(await token.delegates(alice.address)).to.equal(phishing.address);
      expect(await token.delegatedPower(bob.address)).to.equal(0);
      expect(await token.delegatedPower(phishing.address)).to.equal(amount);
    });
  });

  describe("getVotingPower completeness", function () {
    it("should include delegated power from phishing contracts", async function () {
      const amount = ethers.parseEther("2000");
      await token.connect(owner).transfer(alice.address, amount);
      await token.connect(owner).transfer(bob.address, amount);

      await token.connect(alice).delegateVote(phishing.address);
      expect(await token.getVotingPower(phishing.address)).to.equal(amount);

      await token.connect(bob).delegateVote(phishing.address);
      expect(await token.getVotingPower(phishing.address)).to.equal(amount * 2n);
    });

    it("should reflect own balance plus delegated power for any account", async function () {
      const amount = ethers.parseEther("1000");
      await token.connect(owner).transfer(alice.address, amount);
      await token.connect(alice).delegateVote(bob.address);

      const bobBalance = await token.balanceOf(bob.address);
      expect(await token.getVotingPower(bob.address)).to.equal(bobBalance + amount);
    });
  });

  describe("Proposals and Voting", function () {
    it("should create a proposal", async function () {
      await token.createProposal("Test proposal", 3600);
      const proposal = await token.proposals(0);
      expect(proposal.description).to.equal("Test proposal");
      expect(proposal.forVotes).to.equal(0);
      expect(proposal.againstVotes).to.equal(0);
      expect(proposal.executed).to.equal(false);
    });

    it("should allow voting with voting power", async function () {
      const amount = ethers.parseEther("500");
      await token.connect(owner).transfer(alice.address, amount);
      await token.createProposal("Test proposal", 3600);
      const proposalId = 0;

      await token.connect(alice).vote(proposalId, true);
      const proposal = await token.proposals(proposalId);
      expect(proposal.forVotes).to.equal(amount);
    });

    it("should prevent double voting", async function () {
      await token.createProposal("Test", 3600);
      await token.connect(owner).vote(0, true);
      await expect(
        token.connect(owner).vote(0, true)
      ).to.be.revertedWith("Already voted");
    });

    it("should prevent voting after deadline", async function () {
      await token.createProposal("Test", 1);
      await ethers.provider.send("evm_increaseTime", [2]);
      await ethers.provider.send("evm_mine", []);
      await expect(
        token.connect(owner).vote(0, true)
      ).to.be.revertedWith("Voting ended");
    });

    it("should allow against votes", async function () {
      const amount = ethers.parseEther("500");
      await token.connect(owner).transfer(alice.address, amount);
      await token.createProposal("Test", 3600);
      await token.connect(alice).vote(0, false);
      const proposal = await token.proposals(0);
      expect(proposal.againstVotes).to.equal(amount);
    });
  });

  describe("Admin/Owner controls", function () {
    it("should allow owner to call snapshot", async function () {
      await expect(token.connect(owner).snapshot()).to.not.revert(ethers);
    });

    it("should reject snapshot from non-owner", async function () {
      await expect(
        token.connect(alice).snapshot()
      ).to.be.revertedWithCustomError(token, "OwnableUnauthorizedAccount");
    });
  });
});
