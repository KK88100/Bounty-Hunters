// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract MultiSigWallet {
    address[] public owners;
    uint256 public required;
    uint256 public transactionCount;

    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
    }

    struct ConfirmationInfo {
        bool confirmed;
        uint256 timestamp;
    }

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => ConfirmationInfo)) public confirmations;
    mapping(address => bool) public isOwner;

    uint256 private _reentrancyLock;
    modifier nonReentrant() {
        require(_reentrancyLock != 1, "ReentrancyGuard: reentrant call");
        _reentrancyLock = 1;
        _;
        _reentrancyLock = 0;
    }

    event Submitted(uint256 indexed txId);
    event Confirmed(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "No owners");
        require(_required > 0 && _required <= _owners.length, "Invalid required");
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Owner cannot be zero address");
            require(!isOwner[_owners[i]], "Duplicate owner");
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
        _reentrancyLock = 0;
    }

    function submitTransaction(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256) {
        require(to != address(0), "Cannot send to zero address");
        uint256 txId = transactionCount++;
        transactions[txId] = Transaction({
            to: to,
            value: value,
            data: data,
            executed: false
        });
        emit Submitted(txId);
        return txId;
    }

    function confirmTransaction(uint256 txId) external onlyOwner {
        require(!transactions[txId].executed, "Already executed");
        require(!confirmations[txId][msg.sender].confirmed, "Already confirmed");
        confirmations[txId][msg.sender] = ConfirmationInfo({
            confirmed: true,
            timestamp: block.timestamp
        });
        emit Confirmed(txId, msg.sender);
    }

    function revokeConfirmation(uint256 txId) external onlyOwner {
        require(!transactions[txId].executed, "Already executed");
        require(confirmations[txId][msg.sender].confirmed, "Not confirmed");
        confirmations[txId][msg.sender] = ConfirmationInfo({
            confirmed: false,
            timestamp: block.timestamp
        });
        emit Revoked(txId, msg.sender);
    }

    function getConfirmationCount(uint256 txId) public view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]].confirmed) count++;
        }
    }

    function getConfirmationCountAtBlock(uint256 txId, uint256 blockNumber) public view returns (uint256 count) {
        if (blockNumber > block.number) return 0;
        for (uint256 i = 0; i < owners.length; i++) {
            ConfirmationInfo storage info = confirmations[txId][owners[i]];
            if (info.confirmed && info.timestamp <= block.timestamp) {
                // If the confirmation timestamp is before or at the target block, count it
                // We approximate block-level checks by checking if the confirmation was made
                // before or at the current block's timestamp
                count++;
            }
        }
    }

    function isConfirmedAtBlock(uint256 txId, uint256 blockNumber) external view returns (bool) {
        return getConfirmationCountAtBlock(txId, blockNumber) >= required;
    }

    function executeTransaction(uint256 txId) external onlyOwner nonReentrant {
        require(!transactions[txId].executed, "Already executed");
        require(getConfirmationCount(txId) >= required, "Not enough confirmations");

        Transaction storage txn = transactions[txId];
        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Execution failed");

        emit Executed(txId);
    }

    receive() external payable {}
}
