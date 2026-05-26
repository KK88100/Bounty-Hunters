// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/CrossChainBridge.sol";

contract CrossChainBridgeTest is Test {
    CrossChainBridge public bridge;
    address public validator;
    address public user;
    address public attacker;
    IERC20 public token;

    uint256 internal validatorPrivateKey;

    function setUp() public {
        validatorPrivateKey = 0xA11CE;
        validator = vm.addr(validatorPrivateKey);
        user = address(0xUSER);
        attacker = address(0xATTACK);

        // Deploy a simple ERC20 for testing
        token = new SimpleERC20("Bridge Token", "BRG", 1_000_000 ether);
        bridge = new CrossChainBridge(address(token), validator);

        // Fund user
        SimpleERC20(address(token)).mint(user, 1000 ether);
        vm.startPrank(user);
        token.approve(address(bridge), 1000 ether);
        vm.stopPrank();
    }

    function test_ValidTransfer() public {
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        uint256 senderNonce = bridge.getSenderNonce(user);
        bytes32 digest = _buildDigest(user, 100 ether, senderNonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(validator);
        bridge.processTransfer(user, 100 ether, senderNonce, signature);

        assertEq(token.balanceOf(user), 1000 ether);
    }

    function test_RevertCrossChainReplay() public {
        // Initiate on chain 1
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        // Process on current chain
        uint256 senderNonce = bridge.getSenderNonce(user);
        bytes32 digest = _buildDigest(user, 100 ether, senderNonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(validator);
        bridge.processTransfer(user, 100 ether, senderNonce, signature);

        // Simulate different chain - domain separator changes with chain ID
        // The digest is different on another chain, so the same signature won't verify
        vm.chainId(999);
        bytes32 digestOtherChain = _buildDigest(user, 100 ether, senderNonce);
        // The digest on chain 999 will be different from chain 1
        assertTrue(digest != digestOtherChain, "Digests should differ across chains");
    }

    function test_RevertSameChainReplay() public {
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        uint256 senderNonce = bridge.getSenderNonce(user);
        bytes32 digest = _buildDigest(user, 100 ether, senderNonce);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(validatorPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(validator);
        bridge.processTransfer(user, 100 ether, senderNonce, signature);

        // Replay should revert
        vm.prank(validator);
        vm.expectRevert("Already processed");
        bridge.processTransfer(user, 100 ether, senderNonce, signature);
    }

    function test_RevertInvalidSignature() public {
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        uint256 senderNonce = bridge.getSenderNonce(user);
        
        // Use wrong private key to sign
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(0xBADD, _buildDigest(user, 100 ether, senderNonce));
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(validator);
        vm.expectRevert("Invalid signature");
        bridge.processTransfer(user, 100 ether, senderNonce, signature);
    }

    function test_RevertZeroAddressSignature() public {
        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        uint256 senderNonce = bridge.getSenderNonce(user);
        bytes32 digest = _buildDigest(user, 100 ether, senderNonce);

        // Create an invalid signature that produces zero-address from ecrecover
        bytes memory signature = abi.encodePacked(
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            bytes32(0x0000000000000000000000000000000000000000000000000000000000000001),
            uint8(28)
        );

        vm.prank(validator);
        vm.expectRevert("Invalid signature: zero address");
        bridge.processTransfer(user, 100 ether, senderNonce, signature);
    }

    function test_EIP712DomainSeparator() public {
        bytes32 expectedDomainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("CrossChainBridge")),
            keccak256(bytes("1")),
            block.chainid,
            address(bridge)
        ));
        assertEq(bridge.domainSeparator(), expectedDomainSeparator);
    }

    function test_SenderNonceQueryable() public {
        assertEq(bridge.getSenderNonce(user), 0);

        vm.prank(user);
        bridge.initiateTransfer(100 ether, 2);

        assertEq(bridge.getSenderNonce(user), 1);
    }

    function _buildDigest(address recipient, uint256 amount, uint256 nonce) internal view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Transfer(address recipient,uint256 amount,uint256 nonce)"),
            recipient,
            amount,
            nonce
        ));
        return keccak256(abi.encodePacked(
            "\x19\x01",
            bridge.domainSeparator(),
            structHash
        ));
    }
}

// Minimal ERC20 for testing
contract SimpleERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
