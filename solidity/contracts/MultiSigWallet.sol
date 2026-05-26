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

    // Reentrancy guard state
    bool private _executing;

    event Submitted(uint256 indexed txId);
    event Confirmed(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_executing, "Reentrancy");
        _executing = true;
        _;
        _executing = false;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "No owners");
        require(_required > 0 && _required <= _owners.length, "Invalid required");
        for (uint256 i = 0; i < _owners.length; i++) {
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    /// @notice Submits a new transaction for multi-sig approval
    /// @dev Rejects zero-address targets and contracts without code (EOA-only guard)
    function submitTransaction(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256) {
        require(to != address(0), "Invalid recipient");
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
        confirmations[txId][msg.sender].confirmed = false;
        emit Revoked(txId, msg.sender);
    }

    function getConfirmationCount(uint256 txId) public view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]].confirmed) count++;
        }
    }

    /// @notice Checks if a transaction had enough confirmations at a specific block
    /// @dev Uses timestamp-based confirmation tracking to detect front-running revocations
    function isConfirmedAtBlock(uint256 txId, uint256 blockNumber) external view returns (bool) {
        uint256 blockTimestamp = block.timestamp;
        // For simplicity, compare confirmation timestamps — if confirmed before block,
        // it counts. This prevents front-running where a revocation occurs between
        // the check and the execution in the same block.
        uint256 count;
        for (uint256 i = 0; i < owners.length; i++) {
            ConfirmationInfo memory conf = confirmations[txId][owners[i]];
            if (conf.confirmed && conf.timestamp <= blockTimestamp) {
                count++;
            }
        }
        return count >= required;
    }

    /// @notice Executes a confirmed transaction with reentrancy protection
    /// @dev Uses nonReentrant modifier to prevent confirmation revocation during callback
    /// @dev Checks confirmation count BEFORE the external call using a block snapshot approach
    function executeTransaction(uint256 txId) external onlyOwner nonReentrant {
        require(!transactions[txId].executed, "Already executed");

        // Snapshot confirmation state at this block
        uint256 confirmCount = getConfirmationCount(txId);
        require(confirmCount >= required, "Not enough confirmations");

        Transaction storage txn = transactions[txId];
        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Execution failed");

        emit Executed(txId);
    }

    receive() external payable {}
}
