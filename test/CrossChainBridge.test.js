import { expect } from "chai";
import { network } from "hardhat";

const { ethers } = await network.create();

describe("CrossChainBridge (Issue #920) — EIP-712 Replay Protection", function () {
  let bridgeToken, bridge;
  let owner, validator, user, attacker;
  let chainId;

  const AMOUNT = ethers.parseEther("100");
  const TARGET_CHAIN = 31337; // hardhat default chainId

  before(async function () {
    [owner, validator, user, attacker] = await ethers.getSigners();
    const net = await ethers.provider.getNetwork();
    chainId = Number(net.chainId);
  });

  beforeEach(async function () {
    // Deploy SimpleToken as bridge token
    const SimpleToken = await ethers.getContractFactory("SimpleToken");
    bridgeToken = await SimpleToken.deploy("Bridge Token", "BRDG", 18);
    await bridgeToken.waitForDeployment();

    // Deploy CrossChainBridge
    const CrossChainBridge = await ethers.getContractFactory("CrossChainBridge");
    bridge = await CrossChainBridge.deploy(bridgeToken.target, validator.address);
    await bridge.waitForDeployment();

    // Mint tokens to user and approve bridge
    await bridgeToken.mint(user.address, ethers.parseEther("10000"));
    await bridgeToken.connect(user).approve(bridge.target, ethers.parseEther("10000"));
  });

  /**
   * Helper: sign EIP-712 typed data for a cross-chain transfer
   */
  async function signTransfer({ recipient, amount, nonce, chainId: overrideChainId, signer }) {
    const actualChainId = overrideChainId ?? chainId;

    const domain = {
      name: "CrossChainBridge",
      version: "1",
      chainId: actualChainId,
      verifyingContract: bridge.target,
    };

    const types = {
      Transfer: [
        { name: "recipient", type: "address" },
        { name: "amount", type: "uint256" },
        { name: "nonce", type: "uint256" },
        { name: "chainId", type: "uint256" },
      ],
    };

    const value = {
      recipient,
      amount,
      nonce,
      chainId: actualChainId,
    };

    return signer.signTypedData(domain, types, value);
  }

  describe("EIP-712 replay protection", function () {
    it("should initiate and process a valid transfer with EIP-712", async function () {
      // User initiates a transfer
      await expect(bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN))
        .to.emit(bridge, "TransferInitiated")
        .withArgs(user.address, AMOUNT, TARGET_CHAIN, 0);

      // Validator signs the transfer with EIP-712
      const signature = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 0,
        signer: validator,
      });

      // Process the transfer
      await expect(bridge.processTransfer(user.address, AMOUNT, 0, signature))
        .to.emit(bridge, "TransferProcessed");

      // User received the tokens
      const balance = await bridgeToken.balanceOf(user.address);
      expect(balance).to.equal(ethers.parseEther("10000")); // initial 10000 - 100 sent + 100 received
    });

    it("should reject cross-chain replay (different chainId in signature)", async function () {
      // Initiate transfer
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Sign for a different chain (e.g., chain 1 = Ethereum mainnet)
      const signature = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 0,
        chainId: 1, // different chain
        signer: validator,
      });

      // Should revert because the hash won't match (chainId mismatch)
      await expect(
        bridge.processTransfer(user.address, AMOUNT, 0, signature)
      ).to.be.revertedWith("Invalid signature");
    });

    it("should reject same-chain replay (nonce reuse)", async function () {
      // Initiate first transfer — nonce becomes 0
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Sign with nonce 0
      const signature = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 0,
        signer: validator,
      });

      // Process first time — succeeds
      await bridge.processTransfer(user.address, AMOUNT, 0, signature);

      // Try to process again with same signature/nonce — should fail
      await expect(
        bridge.processTransfer(user.address, AMOUNT, 0, signature)
      ).to.be.revertedWith("Invalid nonce");
    });

    it("should reject invalid signature (ecrecover zero address)", async function () {
      // Initiate transfer
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Create a garbage signature (invalid r,s,v)
      const badSignature = ethers.concat([
        ethers.randomBytes(32), // r
        ethers.randomBytes(32), // s
        new Uint8Array([28]),   // v
      ]);

      // Should revert with "Invalid signature" from ecrecover zero-address check
      await expect(
        bridge.processTransfer(user.address, AMOUNT, 0, badSignature)
      ).to.be.revertedWith("Invalid signature");
    });

    it("should reject transfer with wrong nonce", async function () {
      // Initiate transfer
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Sign with nonce 1 instead of 0
      const signature = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 1, // wrong nonce
        signer: validator,
      });

      // Should revert because nonces[user] is 0, not 1
      await expect(
        bridge.processTransfer(user.address, AMOUNT, 1, signature)
      ).to.be.revertedWith("Invalid nonce");
    });

    it("should handle nonce increment correctly", async function () {
      // Initiate two transfers (nonce is emitted but nonces mapping is unchanged)
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Nonce is 0 because initiateTransfer doesn't consume the process nonce
      expect(await bridge.nonces(user.address)).to.equal(0);

      // Process first transfer (nonce 0)
      const sig0 = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 0,
        signer: validator,
      });
      await bridge.processTransfer(user.address, AMOUNT, 0, sig0);

      // After processing nonce 0, nonce should be 1
      expect(await bridge.nonces(user.address)).to.equal(1);

      // Process second transfer (nonce 1)
      const sig1 = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 1,
        signer: validator,
      });
      await bridge.processTransfer(user.address, AMOUNT, 1, sig1);

      // Now nonce should be 2
      expect(await bridge.nonces(user.address)).to.equal(2);
    });

    it("should reject signature from non-validator", async function () {
      // Initiate transfer
      await bridge.connect(user).initiateTransfer(AMOUNT, TARGET_CHAIN);

      // Sign with attacker's key (not the validator)
      const signature = await signTransfer({
        recipient: user.address,
        amount: AMOUNT,
        nonce: 0,
        signer: attacker,
      });

      // Should revert
      await expect(
        bridge.processTransfer(user.address, AMOUNT, 0, signature)
      ).to.be.revertedWith("Invalid signature");
    });
  });
});
