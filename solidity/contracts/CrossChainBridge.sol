// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainBridge {
    IERC20 public bridgeToken;
    address public validator;

    // Nonce per sender to prevent same-chain replay
    mapping(address => uint256) public senderNonces;

    // Used for EIP-712 typed data signing
    string private constant SIGNING_DOMAIN = "CrossChainBridge";
    string private constant SIGNING_VERSION = "1";

    // EIP-712 type hashes
    bytes32 private constant TRANSFER_TYPEHASH = keccak256(
        "Transfer(address recipient,uint256 amount,uint256 nonce)"
    );

    mapping(bytes32 => bool) public processedTransfers;

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    constructor(address _bridgeToken, address _validator) {
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;
    }

    /// @notice Returns the EIP-712 domain separator
    function domainSeparator() public view returns (bytes32) {
        return keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes(SIGNING_DOMAIN)),
            keccak256(bytes(SIGNING_VERSION)),
            block.chainid,
            address(this)
        ));
    }

    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, senderNonces[msg.sender]++);
    }

    /// @notice Processes a signed transfer with full replay protection
    /// @dev Uses EIP-712 typed data signing with chain ID, nonce, and contract address
    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 senderNonce,
        bytes calldata signature
    ) external {
        // Build EIP-712 typed data hash
        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            senderNonce
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator(),
            structHash
        ));

        // Compute unique transfer hash (includes chain ID and contract address via domain separator)
        require(senderNonce >= senderNonces[recipient], "Nonce too low");
        require(!processedTransfers[digest], "Already processed");

        require(verifySignature(digest, signature), "Invalid signature");

        processedTransfers[digest] = true;
        senderNonces[recipient] = senderNonce + 1;
        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(digest, recipient, amount);
    }

    /// @notice Verifies an EIP-712 signature against the validator address
    /// @dev Explicitly checks for zero-address return from ecrecover
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

        // Critical: reject zero-address (invalid signature)
        require(recovered != address(0), "Invalid signature: zero address");

        return recovered == validator;
    }

    /// @notice Returns the current nonce for a sender (for frontend integration)
    function getSenderNonce(address sender) external view returns (uint256) {
        return senderNonces[sender];
    }

    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
