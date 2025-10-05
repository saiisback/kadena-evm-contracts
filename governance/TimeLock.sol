// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title TimeLock
 * @dev A timelock contract for delayed execution of governance proposals
 * 
 * Features:
 * - Configurable delay periods
 * - Transaction queuing and execution
 * - Grace period for execution
 * - Admin and executor roles
 * - Emergency cancellation
 * - Batch operations
 * 
 * Security Features:
 * - Time-locked execution
 * - Role-based access control
 * - Reentrancy protection
 * - Transaction validation
 */
contract TimeLock is Ownable, ReentrancyGuard {
    /// @dev Transaction structure
    struct Transaction {
        address target;
        uint256 value;
        string signature;
        bytes data;
        uint256 eta;
        bool executed;
        bool cancelled;
    }

    /// @dev Minimum delay (1 day)
    uint256 public constant MINIMUM_DELAY = 1 days;
    
    /// @dev Maximum delay (30 days)
    uint256 public constant MAXIMUM_DELAY = 30 days;
    
    /// @dev Grace period (14 days)
    uint256 public constant GRACE_PERIOD = 14 days;

    /// @dev Current delay
    uint256 public delay;
    
    /// @dev Admin address (can queue and cancel)
    address public admin;
    
    /// @dev Pending admin (for admin transfer)
    address public pendingAdmin;
    
    /// @dev Mapping of queued transaction hashes
    mapping(bytes32 => bool) public queuedTransactions;
    
    /// @dev Array of all transactions
    Transaction[] public transactions;
    
    /// @dev Mapping from transaction hash to transaction ID
    mapping(bytes32 => uint256) public transactionIds;

    event NewAdmin(address indexed newAdmin);
    event NewPendingAdmin(address indexed newPendingAdmin);
    event NewDelay(uint256 indexed newDelay);
    event CancelTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event ExecuteTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );
    event QueueTransaction(
        bytes32 indexed txHash,
        address indexed target,
        uint256 value,
        string signature,
        bytes data,
        uint256 eta
    );

    modifier onlyAdmin() {
        require(msg.sender == admin, "Call must come from admin");
        _;
    }

    modifier onlyTimelock() {
        require(msg.sender == address(this), "Call must come from timelock");
        _;
    }

    constructor(address admin_, uint256 delay_) Ownable(msg.sender) {
        require(delay_ >= MINIMUM_DELAY, "Delay must exceed minimum delay");
        require(delay_ <= MAXIMUM_DELAY, "Delay must not exceed maximum delay");

        admin = admin_;
        delay = delay_;
    }

    /**
     * @dev Set new delay (only via timelock)
     * @param delay_ New delay value
     */
    function setDelay(uint256 delay_) external onlyTimelock {
        require(delay_ >= MINIMUM_DELAY, "Delay must exceed minimum delay");
        require(delay_ <= MAXIMUM_DELAY, "Delay must not exceed maximum delay");
        delay = delay_;
        emit NewDelay(delay_);
    }

    /**
     * @dev Accept admin role (two-step process)
     */
    function acceptAdmin() external {
        require(msg.sender == pendingAdmin, "Call must come from pendingAdmin");
        admin = msg.sender;
        pendingAdmin = address(0);
        emit NewAdmin(admin);
    }

    /**
     * @dev Set pending admin (only via timelock)
     * @param pendingAdmin_ New pending admin address
     */
    function setPendingAdmin(address pendingAdmin_) external onlyTimelock {
        pendingAdmin = pendingAdmin_;
        emit NewPendingAdmin(pendingAdmin_);
    }

    /**
     * @dev Queue a transaction for delayed execution
     * @param target Target contract address
     * @param value ETH value to send
     * @param signature Function signature
     * @param data Call data
     * @param eta Earliest execution time
     * @return txHash Transaction hash
     */
    function queueTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyAdmin returns (bytes32 txHash) {
        require(eta >= getBlockTimestamp() + delay, "Estimated execution block must satisfy delay");

        txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(!queuedTransactions[txHash], "Transaction already queued");
        
        queuedTransactions[txHash] = true;
        
        // Store transaction details
        uint256 txId = transactions.length;
        transactions.push(Transaction({
            target: target,
            value: value,
            signature: signature,
            data: data,
            eta: eta,
            executed: false,
            cancelled: false
        }));
        
        transactionIds[txHash] = txId;

        emit QueueTransaction(txHash, target, value, signature, data, eta);
    }

    /**
     * @dev Cancel a queued transaction
     * @param target Target contract address
     * @param value ETH value
     * @param signature Function signature
     * @param data Call data
     * @param eta Execution time
     */
    function cancelTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external onlyAdmin {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction not queued");
        
        queuedTransactions[txHash] = false;
        
        // Mark transaction as cancelled
        uint256 txId = transactionIds[txHash];
        transactions[txId].cancelled = true;

        emit CancelTransaction(txHash, target, value, signature, data, eta);
    }

    /**
     * @dev Execute a queued transaction
     * @param target Target contract address
     * @param value ETH value
     * @param signature Function signature
     * @param data Call data
     * @param eta Execution time
     * @return Transaction result
     */
    function executeTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external payable onlyAdmin nonReentrant returns (bytes memory) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        require(queuedTransactions[txHash], "Transaction not queued");
        require(getBlockTimestamp() >= eta, "Transaction hasn't surpassed time lock");
        require(getBlockTimestamp() <= eta + GRACE_PERIOD, "Transaction is stale");

        queuedTransactions[txHash] = false;
        
        // Mark transaction as executed
        uint256 txId = transactionIds[txHash];
        transactions[txId].executed = true;

        bytes memory callData;
        if (bytes(signature).length == 0) {
            callData = data;
        } else {
            callData = abi.encodePacked(bytes4(keccak256(bytes(signature))), data);
        }

        (bool success, bytes memory returnData) = target.call{value: value}(callData);
        require(success, "Transaction execution reverted");

        emit ExecuteTransaction(txHash, target, value, signature, data, eta);

        return returnData;
    }

    /**
     * @dev Batch queue multiple transactions
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param signatures Array of function signatures
     * @param datas Array of call data
     * @param etas Array of execution times
     * @return txHashes Array of transaction hashes
     */
    function batchQueueTransactions(
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata datas,
        uint256[] calldata etas
    ) external onlyAdmin returns (bytes32[] memory txHashes) {
        require(
            targets.length == values.length &&
            values.length == signatures.length &&
            signatures.length == datas.length &&
            datas.length == etas.length,
            "Array lengths must match"
        );
        require(targets.length <= 10, "Too many transactions");

        txHashes = new bytes32[](targets.length);
        
        for (uint256 i = 0; i < targets.length; i++) {
            txHashes[i] = queueTransaction(
                targets[i],
                values[i],
                signatures[i],
                datas[i],
                etas[i]
            );
        }
    }

    /**
     * @dev Batch execute multiple transactions
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param signatures Array of function signatures
     * @param datas Array of call data
     * @param etas Array of execution times
     * @return results Array of transaction results
     */
    function batchExecuteTransactions(
        address[] calldata targets,
        uint256[] calldata values,
        string[] calldata signatures,
        bytes[] calldata datas,
        uint256[] calldata etas
    ) external payable onlyAdmin returns (bytes[] memory results) {
        require(
            targets.length == values.length &&
            values.length == signatures.length &&
            signatures.length == datas.length &&
            datas.length == etas.length,
            "Array lengths must match"
        );
        require(targets.length <= 10, "Too many transactions");

        results = new bytes[](targets.length);
        
        for (uint256 i = 0; i < targets.length; i++) {
            results[i] = executeTransaction(
                targets[i],
                values[i],
                signatures[i],
                datas[i],
                etas[i]
            );
        }
    }

    /**
     * @dev Check if a transaction is queued
     * @param target Target address
     * @param value ETH value
     * @param signature Function signature
     * @param data Call data
     * @param eta Execution time
     * @return Whether transaction is queued
     */
    function isTransactionQueued(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external view returns (bool) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        return queuedTransactions[txHash];
    }

    /**
     * @dev Get transaction details by hash
     * @param txHash Transaction hash
     * @return Transaction details
     */
    function getTransaction(bytes32 txHash) external view returns (Transaction memory) {
        uint256 txId = transactionIds[txHash];
        return transactions[txId];
    }

    /**
     * @dev Get transaction count
     * @return Number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Get current block timestamp
     * @return Current timestamp
     */
    function getBlockTimestamp() public view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Check if transaction can be executed
     * @param target Target address
     * @param value ETH value
     * @param signature Function signature
     * @param data Call data
     * @param eta Execution time
     * @return Whether transaction can be executed
     */
    function canExecuteTransaction(
        address target,
        uint256 value,
        string calldata signature,
        bytes calldata data,
        uint256 eta
    ) external view returns (bool) {
        bytes32 txHash = keccak256(abi.encode(target, value, signature, data, eta));
        
        if (!queuedTransactions[txHash]) return false;
        if (getBlockTimestamp() < eta) return false;
        if (getBlockTimestamp() > eta + GRACE_PERIOD) return false;
        
        uint256 txId = transactionIds[txHash];
        Transaction storage transaction = transactions[txId];
        
        return !transaction.executed && !transaction.cancelled;
    }

    /**
     * @dev Emergency function to recover stuck ETH
     */
    function emergencyRecoverETH() external onlyOwner {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner(), amount)
        );
        require(success, "Token recovery failed");
    }

    /**
     * @dev Receive function to accept ETH
     */
    receive() external payable {}

    /**
     * @dev Fallback function for external calls
     */
    fallback() external payable {}
}
