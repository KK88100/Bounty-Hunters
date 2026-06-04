// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainBridge {
    IERC20 public bridgeToken;
    address public validator;

    mapping(address => uint256) public nonces;

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    // EIP-712 domain separator (immutable because block.chainid + address(this) are runtime values)
    bytes32 public immutable DOMAIN_SEPARATOR;

    // EIP-712 typehash for the Transfer struct
    bytes32 public constant TRANSFER_TYPEHASH = keccak256("Transfer(address recipient,uint256 amount,uint256 nonce,uint256 chainId)");

    constructor(address _bridgeToken, address _validator) {
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;

        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256(bytes("CrossChainBridge")),
            keccak256(bytes("1")),
            block.chainid,
            address(this)
        ));
    }

    /// @notice Initiates a cross-chain transfer, burning/locking tokens
    /// @param amount Amount of tokens to transfer
    /// @param targetChain Destination chain ID
    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, nonces[msg.sender]);
    }

    /// @notice Processes a signed transfer on the destination chain
    /// @dev Uses EIP-712 typed data signing with chainId, sender nonce, and contract address
    /// @param recipient Address to receive tokens
    /// @param amount Amount of tokens to transfer
    /// @param transferNonce Sender's current nonce (from nonces[recipient])
    /// @param signature EIP-712 signature from the validator
    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 transferNonce,
        bytes calldata signature
    ) external {
        // Prevent replay: nonce must match current sender nonce
        require(nonces[recipient] == transferNonce, "Invalid nonce");

        // Build EIP-712 struct hash
        bytes32 structHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            transferNonce,
            block.chainid
        ));

        // Build the full EIP-712 signed hash (includes domain separator)
        bytes32 transferHash = keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            structHash
        ));

        // Verify the signature is from the validator
        require(verifySignature(transferHash, signature), "Invalid signature");

        // Consume nonce to prevent same-chain replay
        nonces[recipient]++;

        // Transfer tokens
        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(transferHash, recipient, amount);
    }

    /// @notice Verifies an EIP-712 signature, with zero-address check
    /// @param hash The EIP-712 signed hash (already includes \x19\x01 prefix)
    /// @param signature The raw 65-byte signature (r, s, v)
    /// @return True if the signer is the validator
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

        // FIX: Prevent ecrecover zero-address bypass
        require(recovered != address(0), "Invalid signature");

        return recovered == validator;
    }

    /// @notice Returns the bridge token balance held by this contract
    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
