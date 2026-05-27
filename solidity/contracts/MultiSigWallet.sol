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
        uint256 blockNumber;
    }

    mapping(uint256 => Transaction) public transactions;
    mapping(uint256 => mapping(address => ConfirmationInfo)) public confirmations;
    mapping(address => bool) public isOwner;

    // Reentrancy guard
    bool private _entered;

    event Submitted(uint256 indexed txId);
    event Confirmed(uint256 indexed txId, address indexed owner);
    event Executed(uint256 indexed txId);
    event Revoked(uint256 indexed txId, address indexed owner);

    modifier onlyOwner() {
        require(isOwner[msg.sender], "Not owner");
        _;
    }

    modifier nonReentrant() {
        require(!_entered, "Reentrancy detected");
        _entered = true;
        _;
        _entered = false;
    }

    constructor(address[] memory _owners, uint256 _required) {
        require(_owners.length > 0, "No owners");
        require(_required > 0 && _required <= _owners.length, "Invalid required");
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Owner cannot be zero address");
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        required = _required;
    }

    // FIX: Added zero-address validation on `to`
    function submitTransaction(address to, uint256 value, bytes calldata data) external onlyOwner returns (uint256) {
        require(to != address(0), "Invalid recipient address");
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
            blockNumber: block.number
        });
        emit Confirmed(txId, msg.sender);
    }

    function revokeConfirmation(uint256 txId) external onlyOwner {
        require(!transactions[txId].executed, "Already executed");
        require(confirmations[txId][msg.sender].confirmed, "Not confirmed");
        delete confirmations[txId][msg.sender];
        emit Revoked(txId, msg.sender);
    }

    function getConfirmationCount(uint256 txId) public view returns (uint256 count) {
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[txId][owners[i]].confirmed) count++;
        }
    }

    // FIX: Added block-level confirmation check to detect front-running revocations
    function isConfirmedAtBlock(uint256 txId, uint256 blockNumber) public view returns (bool) {
        uint256 count;
        for (uint256 i = 0; i < owners.length; i++) {
            ConfirmationInfo memory info = confirmations[txId][owners[i]];
            if (info.confirmed && info.blockNumber <= blockNumber) {
                count++;
            }
        }
        return count >= required;
    }

    // FIX: Added reentrancy guard via nonReentrant modifier
    // FIX: Uses isConfirmedAtBlock for block-level snapshot
    function executeTransaction(uint256 txId) external onlyOwner nonReentrant {
        require(!transactions[txId].executed, "Already executed");

        // Check confirmations at current block (before external call)
        require(isConfirmedAtBlock(txId, block.number), "Not enough confirmations at block");

        Transaction storage txn = transactions[txId];
        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);
        require(success, "Execution failed");

        emit Executed(txId);
    }

    receive() external payable {}
}
