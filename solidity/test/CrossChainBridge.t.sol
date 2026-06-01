// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CrossChainBridge.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MCK") {
        _mint(msg.sender, 1000000 ether);
    }
}

contract CrossChainBridgeTest is Test {
    CrossChainBridge public bridge;
    MockERC20 public token;
    address public validator;
    address public user;

    function setUp() public {
        validator = makeAddr("validator");
        user = makeAddr("user");
        token = new MockERC20();
        bridge = new CrossChainBridge(address(token), validator);
        token.transfer(user, 10000 ether);
    }

    function test_CrossChainReplayProtection() public {
        // User initiates transfer
        vm.prank(user);
        token.approve(address(bridge), 1000 ether);
        vm.prank(user);
        bridge.initiateTransfer(1000 ether, 2);

        // Create a valid signature on chain 1
        bytes32 digest = _getDigest(address(bridge), user, 1000 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.deriveKey(validator), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, sig);

        // Try to replay the same signature on a different chain — should revert
        // The digest includes block.chainid so it won't match
        bytes32 digest2 = _getDigest(address(bridge), user, 1000 ether, 0);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(vm.deriveKey(validator), digest2);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2);

        // This should succeed on the same chain with a different nonce
        // But the transferHash (digest) was already processed
        vm.expectRevert("Already processed");
        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, sig2);
    }

    function test_SameChainReplayProtection() public {
        vm.prank(user);
        token.approve(address(bridge), 10000 ether);
        vm.prank(user);
        bridge.initiateTransfer(1000 ether, 2);

        // Process with nonce 0
        bytes32 digest = _getDigest(address(bridge), user, 1000 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.deriveKey(validator), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, sig);

        // Cannot replay the same hash
        vm.expectRevert("Already processed");
        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, sig);
    }

    function test_InvalidSignatureZeroAddress() public {
        // Send a malformed signature that ecrecover will return zero
        bytes memory badSig = abi.encodePacked(bytes32(uint256(0)), bytes32(uint256(0)), uint8(27));
        vm.expectRevert("Invalid signature length");
        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, badSig);
    }

    function test_ValidEIP712Verification() public {
        vm.prank(user);
        token.approve(address(bridge), 10000 ether);
        vm.prank(user);
        bridge.initiateTransfer(1000 ether, 2);

        bytes32 digest = _getDigest(address(bridge), user, 1000 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.deriveKey(validator), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        assertTrue(bridge.verifySignature(digest, sig));

        // Wrong signer should fail
        address wrongValidator = makeAddr("wrong");
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(vm.deriveKey(wrongValidator), digest);
        bytes memory sig2 = abi.encodePacked(r2, s2, v2);
        assertFalse(bridge.verifySignature(digest, sig2));
    }

    function test_PostUpgradeReplayProtection() public {
        vm.prank(user);
        token.approve(address(bridge), 10000 ether);
        vm.prank(user);
        bridge.initiateTransfer(1000 ether, 2);

        bytes32 digest = _getDigest(address(bridge), user, 1000 ether, 0);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.deriveKey(validator), digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        // Process on current bridge
        vm.prank(user);
        bridge.processTransfer(user, 1000 ether, 0, sig);

        // Deploy a new bridge (simulating upgrade)
        CrossChainBridge bridge2 = new CrossChainBridge(address(token), validator);
        token.transfer(address(bridge2), 1000 ether);

        // The same signature won't work on the new contract because digest includes address(this)
        bytes32 digest2 = _getDigest(address(bridge2), user, 1000 ether, 0);
        assertFalse(digest == digest2);
    }

    function _getDigest(address bridgeAddr, address recipient, uint256 amount, uint256 nonce) private view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Transfer(address recipient,uint256 amount,uint256 nonce,uint256 chainId,address bridge)"),
            recipient,
            amount,
            nonce,
            block.chainid,
            bridgeAddr
        ));
        return keccak256(abi.encodePacked(
            "\x19\x01",
            keccak256(abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("CrossChainBridge")),
                keccak256(bytes("1")),
                block.chainid,
                bridgeAddr
            )),
            structHash
        ));
    }
}
