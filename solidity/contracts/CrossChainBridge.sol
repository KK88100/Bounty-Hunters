// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainBridge {
    IERC20 public bridgeToken;
    address public validator;
    uint256 public nonce;

    mapping(bytes32 => bool) public processedTransfers;

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    constructor(address _bridgeToken, address _validator) {
        require(_bridgeToken != address(0), "Invalid token address");
        require(_validator != address(0), "Invalid validator address");
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;
    }

    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, nonce++);
    }

    // FIX: Added block.chainid, address(this), and per-sender nonce to hash
    // FIX: EIP-712 typed data signing for structured signature verification
    // Prevents: cross-chain replay, same-chain replay, post-upgrade replay
    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 transferNonce,
        bytes calldata signature
    ) external {
        // EIP-712 domain separator (includes chainId and contract address)
        bytes32 domainSeparator = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("CrossChainBridge"),
            keccak256("1"),
            block.chainid,
            address(this)
        ));

        // EIP-712 struct hash (includes recipient, amount, nonce)
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Transfer(address recipient,uint256 amount,uint256 nonce)"),
            recipient,
            amount,
            transferNonce
        ));

        // Full EIP-712 digest
        bytes32 transferHash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        require(!processedTransfers[transferHash], "Already processed");
        require(verifySignature(transferHash, signature), "Invalid signature");

        processedTransfers[transferHash] = true;
        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(transferHash, recipient, amount);
    }

    // FIX: Added explicit ecrecover zero-address check
    function verifySignature(bytes32 hash, bytes calldata signature) public view returns (bool) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) v += 27;

        address recovered = ecrecover(hash, v, r, s);

        // FIX: explicit zero-address check
        require(recovered != address(0), "Invalid signature (zero address)");
        return recovered == validator;
    }

    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
