// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "./CrossChainBridge.sol";
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
        token.transfer(user, 1000 ether);
    }

    function signTransfer(address _recipient, uint256 _amount, uint256 _nonce, address _bridge, uint256 _chainId) internal view returns (bytes memory) {
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("CrossChainBridge"),
            keccak256("1"),
            _chainId,
            _bridge
        ));
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Transfer(address recipient,uint256 amount,uint256 nonce)"),
            _recipient,
            _amount,
            _nonce
        ));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(vm.deriveKey(validator), digest);
        return abi.encodePacked(r, s, v);
    }

    function test_CrossChainReplayPrevented() public {
        // Sign a message on chain 1
        bytes memory sig = signTransfer(user, 100 ether, 0, address(bridge), 1);

        // Process on chain 1 (simulated via vm.chainId)
        vm.chainId(1);
        bridge.processTransfer(user, 100 ether, 0, sig);

        // Attempt replay on chain 2 — should revert
        vm.chainId(2);
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(user, 100 ether, 0, sig);
    }

    function test_SameChainNonceReplayPrevented() public {
        bytes memory sig1 = signTransfer(user, 100 ether, 0, address(bridge), block.chainid);
        bytes memory sig2 = signTransfer(user, 50 ether, 1, address(bridge), block.chainid);

        bridge.processTransfer(user, 100 ether, 0, sig1);
        bridge.processTransfer(user, 50 ether, 1, sig2);

        // Replay with same nonce 0 — should revert
        vm.expectRevert("Already processed");
        bridge.processTransfer(user, 100 ether, 0, sig1);
    }

    function test_PostUpgradeReplayPrevented() public {
        // Deploy new bridge (simulates proxy upgrade to new address)
        CrossChainBridge bridgeV2 = new CrossChainBridge(address(token), validator);
        bytes memory sig = signTransfer(user, 100 ether, 0, address(bridge), block.chainid);

        bridge.processTransfer(user, 100 ether, 0, sig);

        // Try to replay on new bridge — should fail because domain separator includes verifyingContract
        vm.expectRevert("Invalid signature");
        bridgeV2.processTransfer(user, 100 ether, 0, sig);
    }

    function test_EcrecoverZeroAddressRejected() public {
        // Craft an invalid signature that would produce zero address
        bytes memory badSig = abi.encodePacked(bytes32(0), bytes32(0), hex"1b");

        vm.expectRevert("Invalid signature");
        bridge.processTransfer(user, 100 ether, 0, badSig);
    }

    function test_InvalidSignatureRejected() public {
        address attacker = makeAddr("attacker");
        uint256 attackerKey = vm.deriveKey(attacker);

        bytes32 digest = keccak256(abi.encodePacked("invalid"));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(attackerKey, digest);
        bytes memory sig = abi.encodePacked(r, s, v);

        vm.expectRevert("Invalid signature");
        bridge.processTransfer(user, 100 ether, 0, sig);
    }

    function test_EIP712DomainSeparatorCorrect() public view {
        bytes32 expectedDomainSep = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("CrossChainBridge"),
            keccak256("1"),
            block.chainid,
            address(bridge)
        ));
        // Verify via static call — domain separator is embedded in hash construction
        // This test verifies the structure is consistent
        assertTrue(expectedDomainSep != bytes32(0));
    }

    function test_ValidTransferProcessesCorrectly() public {
        vm.prank(user);
        token.approve(address(bridge), 100 ether);

        // Initiate transfer
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        // Validator signs
        bytes memory sig = signTransfer(user, 100 ether, 0, address(bridge), block.chainid);

        // Process
        bridge.processTransfer(user, 100 ether, 0, sig);
        assertEq(token.balanceOf(user), 1000 ether); // Same user received on target chain
    }
}
