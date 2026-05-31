// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CrossChainBridge {
    IERC20 public bridgeToken;
    address public validator;
    uint256 public nonce;

    // EIP-712 domain separator
    bytes32 private constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private constant TRANSFER_TYPEHASH =
        keccak256("Transfer(address recipient,uint256 amount,uint256 nonce)");

    bytes32 public domainSeparator;
    string public constant NAME = "CrossChainBridge";
    string public constant VERSION = "1";

    mapping(bytes32 => bool) public processedTransfers;
    mapping(address => uint256) public senderNonces;

    event TransferInitiated(address indexed sender, uint256 amount, uint256 targetChain, uint256 nonce);
    event TransferProcessed(bytes32 indexed transferHash, address indexed recipient, uint256 amount);

    constructor(address _bridgeToken, address _validator) {
        bridgeToken = IERC20(_bridgeToken);
        validator = _validator;
        domainSeparator = keccak256(abi.encode(
            DOMAIN_TYPEHASH,
            keccak256(bytes(NAME)),
            keccak256(bytes(VERSION)),
            block.chainid,
            address(this)
        ));
    }

    function initiateTransfer(uint256 amount, uint256 targetChain) external {
        require(amount > 0, "Amount must be > 0");
        bridgeToken.transferFrom(msg.sender, address(this), amount);
        emit TransferInitiated(msg.sender, amount, targetChain, nonce++);
    }

    function processTransfer(
        address recipient,
        uint256 amount,
        uint256 transferNonce,
        bytes calldata signature
    ) external {
        require(senderNonces[msg.sender] == transferNonce, "Invalid nonce");
        bytes32 transferHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            transferNonce
        ));
        bytes32 digest = keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            transferHash
        ));

        require(!processedTransfers[digest], "Already processed");
        require(verifySignature(digest, signature), "Invalid signature");

        processedTransfers[digest] = true;
        senderNonces[msg.sender]++;
        bridgeToken.transfer(recipient, amount);

        emit TransferProcessed(digest, recipient, amount);
    }

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
        require(recovered != address(0), "Invalid signature: zero address");
        return recovered == validator;
    }

    function getTypedDataHash(
        address recipient,
        uint256 amount,
        uint256 _nonce
    ) external view returns (bytes32) {
        bytes32 transferHash = keccak256(abi.encode(
            TRANSFER_TYPEHASH,
            recipient,
            amount,
            _nonce
        ));
        return keccak256(abi.encodePacked(
            "\x19\x01",
            domainSeparator,
            transferHash
        ));
    }

    function getSenderNonce(address sender) external view returns (uint256) {
        return senderNonces[sender];
    }

    function getPoolBalance() external view returns (uint256) {
        return bridgeToken.balanceOf(address(this));
    }
}
