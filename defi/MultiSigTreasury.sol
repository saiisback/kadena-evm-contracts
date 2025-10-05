// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiSigTreasury
 * @dev A comprehensive multi-signature treasury contract for DAO fund management
 * 
 * Features:
 * - Multi-signature approval for transactions
 * - Configurable approval thresholds
 * - Support for ETH and ERC20 token transfers
 * - Transaction queuing and execution
 * - Emergency pause functionality
 * - Owner management
 * - Spending limits and budgets
 * 
 * Security Features:
 * - Multi-signature verification
 * - Reentrancy protection
 * - Access control
 * - Emergency pause
 * - Time-locked execution for large amounts
 */
contract MultiSigTreasury is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Transaction structure
    struct Transaction {
        address to;             // Destination address
        uint256 value;          // ETH value to send
        bytes data;             // Transaction data
        bool executed;          // Whether transaction is executed
        uint256 confirmations;  // Number of confirmations
        uint256 createdAt;      // Timestamp when transaction was created
        address token;          // Token address (address(0) for ETH)
        uint256 amount;         // Token amount
        string description;     // Transaction description
    }

    /// @dev Budget structure for spending limits
    struct Budget {
        uint256 limit;          // Maximum spending limit
        uint256 spent;          // Amount already spent
        uint256 period;         // Time period for the budget (in seconds)
        uint256 lastReset;      // Last time the budget was reset
        bool active;            // Whether the budget is active
    }

    /// @dev Array of owners
    address[] public owners;
    
    /// @dev Mapping of owner addresses
    mapping(address => bool) public isOwner;
    
    /// @dev Number of required confirmations
    uint256 public required;
    
    /// @dev Array of all transactions
    Transaction[] public transactions;
    
    /// @dev Mapping from transaction ID to owner to confirmation status
    mapping(uint256 => mapping(address => bool)) public confirmations;
    
    /// @dev Mapping from token to budget information
    mapping(address => Budget) public budgets;
    
    /// @dev Minimum time delay for large transactions (in seconds)
    uint256 public timeDelay = 24 hours;
    
    /// @dev Threshold for time-locked transactions
    uint256 public timeLockThreshold = 100 ether;
    
    /// @dev Whether the contract is paused
    bool public paused;

    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);
    event TransactionSubmitted(uint256 indexed txId, address indexed owner);
    event TransactionConfirmed(uint256 indexed txId, address indexed owner);
    event TransactionRevoked(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId);
    event Deposit(address indexed sender, uint256 value);
    event TokenDeposit(address indexed token, address indexed sender, uint256 amount);
    event BudgetSet(address indexed token, uint256 limit, uint256 period);
    event BudgetReset(address indexed token);
    event TimeLockThresholdChanged(uint256 threshold);
    event TimeDelayChanged(uint256 delay);
    event Paused();
    event Unpaused();

    modifier onlyOwner() override {
        require(isOwner[msg.sender], "Not an owner");
        _;
    }

    modifier ownerExists(address owner) {
        require(isOwner[owner], "Owner does not exist");
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!isOwner[owner], "Owner already exists");
        _;
    }

    modifier transactionExists(uint256 txId) {
        require(txId < transactions.length, "Transaction does not exist");
        _;
    }

    modifier confirmed(uint256 txId, address owner) {
        require(confirmations[txId][owner], "Transaction not confirmed");
        _;
    }

    modifier notConfirmed(uint256 txId, address owner) {
        require(!confirmations[txId][owner], "Transaction already confirmed");
        _;
    }

    modifier notExecuted(uint256 txId) {
        require(!transactions[txId].executed, "Transaction already executed");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier validRequirement(uint256 ownerCount, uint256 _required) {
        require(
            ownerCount <= 50 &&
            _required <= ownerCount &&
            _required != 0 &&
            ownerCount != 0,
            "Invalid requirement"
        );
        _;
    }

    /**
     * @dev Constructor
     * @param _owners Array of initial owners
     * @param _required Number of required confirmations
     */
    constructor(address[] memory _owners, uint256 _required) 
        validRequirement(_owners.length, _required)
        Ownable(msg.sender)
    {
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Invalid owner address");
            require(!isOwner[_owners[i]], "Duplicate owner");
            
            isOwner[_owners[i]] = true;
            owners.push(_owners[i]);
        }
        required = _required;
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {
        if (msg.value > 0) {
            emit Deposit(msg.sender, msg.value);
        }
    }

    /**
     * @dev Submit a transaction for approval
     * @param to Destination address
     * @param value ETH value to send
     * @param data Transaction data
     * @param description Transaction description
     * @return txId Transaction ID
     */
    function submitTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        string calldata description
    ) external onlyOwner whenNotPaused returns (uint256 txId) {
        txId = _addTransaction(to, value, data, address(0), 0, description);
        _confirmTransaction(txId);
    }

    /**
     * @dev Submit a token transfer transaction
     * @param to Destination address
     * @param token Token contract address
     * @param amount Amount of tokens to transfer
     * @param description Transaction description
     * @return txId Transaction ID
     */
    function submitTokenTransaction(
        address to,
        address token,
        uint256 amount,
        string calldata description
    ) external onlyOwner whenNotPaused returns (uint256 txId) {
        require(token != address(0), "Invalid token address");
        require(amount > 0, "Amount must be greater than 0");
        
        bytes memory data = abi.encodeWithSelector(
            IERC20.transfer.selector,
            to,
            amount
        );
        
        txId = _addTransaction(token, 0, data, token, amount, description);
        _confirmTransaction(txId);
    }

    /**
     * @dev Confirm a transaction
     * @param txId Transaction ID
     */
    function confirmTransaction(uint256 txId)
        external
        onlyOwner
        transactionExists(txId)
        notConfirmed(txId, msg.sender)
        whenNotPaused
    {
        _confirmTransaction(txId);
        _executeTransaction(txId);
    }

    /**
     * @dev Revoke confirmation for a transaction
     * @param txId Transaction ID
     */
    function revokeConfirmation(uint256 txId)
        external
        onlyOwner
        confirmed(txId, msg.sender)
        notExecuted(txId)
        whenNotPaused
    {
        confirmations[txId][msg.sender] = false;
        transactions[txId].confirmations -= 1;
        emit TransactionRevoked(txId, msg.sender);
    }

    /**
     * @dev Execute a transaction
     * @param txId Transaction ID
     */
    function executeTransaction(uint256 txId)
        external
        onlyOwner
        confirmed(txId, msg.sender)
        notExecuted(txId)
        whenNotPaused
    {
        _executeTransaction(txId);
    }

    /**
     * @dev Check if a transaction is confirmed
     * @param txId Transaction ID
     * @return Whether the transaction is confirmed
     */
    function isConfirmed(uint256 txId) public view returns (bool) {
        return transactions[txId].confirmations >= required;
    }

    /**
     * @dev Check if time lock has passed for a transaction
     * @param txId Transaction ID
     * @return Whether time lock has passed
     */
    function isTimeLockPassed(uint256 txId) public view returns (bool) {
        Transaction storage txn = transactions[txId];
        
        // Check if transaction requires time lock
        bool requiresTimeLock = false;
        if (txn.token == address(0) && txn.value >= timeLockThreshold) {
            requiresTimeLock = true;
        } else if (txn.token != address(0)) {
            // For token transfers, convert to ETH equivalent (simplified)
            requiresTimeLock = txn.amount >= timeLockThreshold;
        }
        
        if (!requiresTimeLock) return true;
        
        return block.timestamp >= txn.createdAt + timeDelay;
    }

    /**
     * @dev Add a new owner
     * @param owner New owner address
     */
    function addOwner(address owner)
        external
        onlyOwner
        ownerDoesNotExist(owner)
        validRequirement(owners.length + 1, required)
    {
        require(owner != address(0), "Invalid owner address");
        
        isOwner[owner] = true;
        owners.push(owner);
        emit OwnerAdded(owner);
    }

    /**
     * @dev Remove an owner
     * @param owner Owner address to remove
     */
    function removeOwner(address owner) external onlyOwner ownerExists(owner) {
        require(owners.length > 1, "Cannot remove last owner");
        
        isOwner[owner] = false;
        for (uint256 i = 0; i < owners.length - 1; i++) {
            if (owners[i] == owner) {
                owners[i] = owners[owners.length - 1];
                break;
            }
        }
        owners.pop();
        
        if (required > owners.length) {
            changeRequirement(owners.length);
        }
        
        emit OwnerRemoved(owner);
    }

    /**
     * @dev Change the number of required confirmations
     * @param _required New requirement
     */
    function changeRequirement(uint256 _required)
        public
        onlyOwner
        validRequirement(owners.length, _required)
    {
        required = _required;
        emit RequirementChanged(_required);
    }

    /**
     * @dev Set budget for a token
     * @param token Token address (address(0) for ETH)
     * @param limit Spending limit
     * @param period Time period in seconds
     */
    function setBudget(address token, uint256 limit, uint256 period) external onlyOwner {
        require(limit > 0, "Limit must be greater than 0");
        require(period > 0, "Period must be greater than 0");
        
        budgets[token] = Budget({
            limit: limit,
            spent: 0,
            period: period,
            lastReset: block.timestamp,
            active: true
        });
        
        emit BudgetSet(token, limit, period);
    }

    /**
     * @dev Reset budget for a token
     * @param token Token address
     */
    function resetBudget(address token) external onlyOwner {
        Budget storage budget = budgets[token];
        require(budget.active, "Budget not active");
        
        budget.spent = 0;
        budget.lastReset = block.timestamp;
        
        emit BudgetReset(token);
    }

    /**
     * @dev Set time lock threshold
     * @param threshold New threshold
     */
    function setTimeLockThreshold(uint256 threshold) external onlyOwner {
        timeLockThreshold = threshold;
        emit TimeLockThresholdChanged(threshold);
    }

    /**
     * @dev Set time delay for large transactions
     * @param delay New delay in seconds
     */
    function setTimeDelay(uint256 delay) external onlyOwner {
        require(delay >= 1 hours && delay <= 7 days, "Invalid delay");
        timeDelay = delay;
        emit TimeDelayChanged(delay);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    /**
     * @dev Get transaction count
     * @return Number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Get owners
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev Get transaction confirmations count
     * @param txId Transaction ID
     * @return Number of confirmations
     */
    function getConfirmationCount(uint256 txId) external view returns (uint256) {
        return transactions[txId].confirmations;
    }

    /**
     * @dev Get transaction information
     * @param txId Transaction ID
     * @return Transaction details
     */
    function getTransaction(uint256 txId)
        external
        view
        returns (
            address to,
            uint256 value,
            bytes memory data,
            bool executed,
            uint256 confirmations,
            uint256 createdAt,
            address token,
            uint256 amount,
            string memory description
        )
    {
        Transaction storage txn = transactions[txId];
        return (
            txn.to,
            txn.value,
            txn.data,
            txn.executed,
            txn.confirmations,
            txn.createdAt,
            txn.token,
            txn.amount,
            txn.description
        );
    }

    /**
     * @dev Internal function to add a transaction
     */
    function _addTransaction(
        address to,
        uint256 value,
        bytes memory data,
        address token,
        uint256 amount,
        string memory description
    ) internal returns (uint256 txId) {
        txId = transactions.length;
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmations: 0,
            createdAt: block.timestamp,
            token: token,
            amount: amount,
            description: description
        }));
        
        emit TransactionSubmitted(txId, msg.sender);
    }

    /**
     * @dev Internal function to confirm a transaction
     */
    function _confirmTransaction(uint256 txId) internal {
        confirmations[txId][msg.sender] = true;
        transactions[txId].confirmations += 1;
        emit TransactionConfirmed(txId, msg.sender);
    }

    /**
     * @dev Internal function to execute a transaction
     */
    function _executeTransaction(uint256 txId) internal nonReentrant {
        Transaction storage txn = transactions[txId];
        
        require(isConfirmed(txId), "Transaction not confirmed");
        require(isTimeLockPassed(txId), "Time lock not passed");
        
        // Check budget if applicable
        _checkBudget(txn.token, txn.token == address(0) ? txn.value : txn.amount);
        
        txn.executed = true;
        
        if (txn.token == address(0)) {
            // ETH transfer
            require(address(this).balance >= txn.value, "Insufficient ETH balance");
            (bool success,) = txn.to.call{value: txn.value}(txn.data);
            require(success, "Transaction failed");
        } else {
            // Token transfer
            IERC20(txn.token).safeTransfer(txn.to, txn.amount);
        }
        
        // Update budget
        _updateBudget(txn.token, txn.token == address(0) ? txn.value : txn.amount);
        
        emit TransactionExecuted(txId);
    }

    /**
     * @dev Check if spending is within budget
     */
    function _checkBudget(address token, uint256 amount) internal view {
        Budget storage budget = budgets[token];
        if (!budget.active) return;
        
        // Reset budget if period has passed
        if (block.timestamp >= budget.lastReset + budget.period) {
            // Budget would be reset, so check against full limit
            require(amount <= budget.limit, "Exceeds budget limit");
        } else {
            require(budget.spent + amount <= budget.limit, "Exceeds budget limit");
        }
    }

    /**
     * @dev Update budget spending
     */
    function _updateBudget(address token, uint256 amount) internal {
        Budget storage budget = budgets[token];
        if (!budget.active) return;
        
        // Reset budget if period has passed
        if (block.timestamp >= budget.lastReset + budget.period) {
            budget.spent = amount;
            budget.lastReset = block.timestamp;
        } else {
            budget.spent += amount;
        }
    }
}
