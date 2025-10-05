// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title MultiSigWallet
 * @dev A multi-signature wallet with advanced access control features
 * 
 * Features:
 * - Multi-signature transaction approval
 * - Owner management
 * - Daily spending limits
 * - Emergency recovery
 * - Transaction queuing
 * - Whitelisted addresses
 * 
 * Security Features:
 * - M-of-N signature requirements
 * - Time-locked operations
 * - Spending limits
 * - Emergency controls
 */
contract MultiSigWallet is Ownable, ReentrancyGuard {
    /// @dev Transaction structure
    struct Transaction {
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 confirmations;
        uint256 createdAt;
    }

    /// @dev Owner structure
    struct Owner {
        bool isOwner;
        uint256 index;
        uint256 addedAt;
        bool active;
    }

    /// @dev Daily limit structure
    struct DailyLimit {
        uint256 limit;
        uint256 spent;
        uint256 lastResetTime;
    }

    /// @dev Array of owner addresses
    address[] public owners;
    
    /// @dev Mapping of owner information
    mapping(address => Owner) public ownerInfo;
    
    /// @dev Required number of confirmations
    uint256 public requiredConfirmations;
    
    /// @dev Array of all transactions
    Transaction[] public transactions;
    
    /// @dev Mapping from transaction ID to owner confirmations
    mapping(uint256 => mapping(address => bool)) public confirmations;
    
    /// @dev Daily spending limit
    DailyLimit public dailyLimit;
    
    /// @dev Whitelist for instant transfers (no multi-sig required)
    mapping(address => bool) public whitelist;
    
    /// @dev Maximum amount for instant whitelist transfers
    uint256 public whitelistLimit = 1 ether;
    
    /// @dev Emergency recovery mode
    bool public emergencyMode;
    
    /// @dev Emergency recovery address
    address public emergencyRecovery;
    
    /// @dev Time lock for owner changes
    uint256 public ownerChangeLock = 1 days;
    
    /// @dev Pending owner changes
    mapping(address => uint256) public pendingOwnerAdditions;
    mapping(address => uint256) public pendingOwnerRemovals;

    event OwnerAdded(address indexed owner);
    event OwnerRemoved(address indexed owner);
    event RequirementChanged(uint256 required);
    event TransactionSubmitted(uint256 indexed transactionId, address indexed owner);
    event TransactionConfirmed(uint256 indexed transactionId, address indexed owner);
    event TransactionRevoked(uint256 indexed transactionId, address indexed owner);
    event TransactionExecuted(uint256 indexed transactionId);
    event Deposit(address indexed sender, uint256 value);
    event WhitelistUpdated(address indexed account, bool whitelisted);
    event DailyLimitChanged(uint256 limit);
    event EmergencyModeToggled(bool enabled);
    event EmergencyRecoveryChanged(address indexed newRecovery);

    modifier onlyOwner() override {
        require(ownerInfo[msg.sender].isOwner && ownerInfo[msg.sender].active, "Not an active owner");
        _;
    }

    modifier ownerExists(address owner) {
        require(ownerInfo[owner].isOwner, "Owner does not exist");
        _;
    }

    modifier ownerDoesNotExist(address owner) {
        require(!ownerInfo[owner].isOwner, "Owner already exists");
        _;
    }

    modifier transactionExists(uint256 transactionId) {
        require(transactionId < transactions.length, "Transaction does not exist");
        _;
    }

    modifier confirmed(uint256 transactionId, address owner) {
        require(confirmations[transactionId][owner], "Transaction not confirmed");
        _;
    }

    modifier notConfirmed(uint256 transactionId, address owner) {
        require(!confirmations[transactionId][owner], "Transaction already confirmed");
        _;
    }

    modifier notExecuted(uint256 transactionId) {
        require(!transactions[transactionId].executed, "Transaction already executed");
        _;
    }

    modifier inEmergencyMode() {
        require(emergencyMode, "Not in emergency mode");
        _;
    }

    modifier notInEmergencyMode() {
        require(!emergencyMode, "In emergency mode");
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

    constructor(
        address[] memory _owners,
        uint256 _required,
        uint256 _dailyLimit,
        address _emergencyRecovery
    ) 
        validRequirement(_owners.length, _required)
        Ownable(msg.sender)
    {
        require(_emergencyRecovery != address(0), "Invalid emergency recovery address");
        
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != address(0), "Invalid owner address");
            require(!ownerInfo[_owners[i]].isOwner, "Duplicate owner");
            
            ownerInfo[_owners[i]] = Owner({
                isOwner: true,
                index: i,
                addedAt: block.timestamp,
                active: true
            });
            owners.push(_owners[i]);
        }
        
        requiredConfirmations = _required;
        dailyLimit = DailyLimit({
            limit: _dailyLimit,
            spent: 0,
            lastResetTime: block.timestamp
        });
        emergencyRecovery = _emergencyRecovery;
    }

    /**
     * @dev Receive ETH deposits
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
     * @return transactionId ID of the submitted transaction
     */
    function submitTransaction(
        address to,
        uint256 value,
        bytes calldata data
    ) external onlyOwner notInEmergencyMode returns (uint256 transactionId) {
        transactionId = addTransaction(to, value, data);
        confirmTransaction(transactionId);
    }

    /**
     * @dev Confirm a transaction
     * @param transactionId Transaction ID to confirm
     */
    function confirmTransaction(uint256 transactionId)
        public
        onlyOwner
        transactionExists(transactionId)
        notConfirmed(transactionId, msg.sender)
        notInEmergencyMode
    {
        confirmations[transactionId][msg.sender] = true;
        transactions[transactionId].confirmations++;
        
        emit TransactionConfirmed(transactionId, msg.sender);
        
        executeTransaction(transactionId);
    }

    /**
     * @dev Revoke confirmation for a transaction
     * @param transactionId Transaction ID to revoke confirmation for
     */
    function revokeConfirmation(uint256 transactionId)
        external
        onlyOwner
        confirmed(transactionId, msg.sender)
        notExecuted(transactionId)
        notInEmergencyMode
    {
        confirmations[transactionId][msg.sender] = false;
        transactions[transactionId].confirmations--;
        
        emit TransactionRevoked(transactionId, msg.sender);
    }

    /**
     * @dev Execute a confirmed transaction
     * @param transactionId Transaction ID to execute
     */
    function executeTransaction(uint256 transactionId)
        public
        nonReentrant
        transactionExists(transactionId)
        notExecuted(transactionId)
        notInEmergencyMode
    {
        Transaction storage txn = transactions[transactionId];
        
        if (isConfirmed(transactionId)) {
            // Check daily limit for ETH transfers
            if (txn.value > 0) {
                _checkDailyLimit(txn.value);
                _updateDailyLimit(txn.value);
            }
            
            txn.executed = true;
            (bool success, ) = txn.to.call{value: txn.value}(txn.data);
            
            if (success) {
                emit TransactionExecuted(transactionId);
            } else {
                txn.executed = false;
                revert("Transaction execution failed");
            }
        }
    }

    /**
     * @dev Instant transfer to whitelisted address (single signature)
     * @param to Whitelisted destination address
     * @param value Amount to transfer
     */
    function instantTransfer(address to, uint256 value) 
        external 
        onlyOwner 
        nonReentrant 
        notInEmergencyMode 
    {
        require(whitelist[to], "Address not whitelisted");
        require(value <= whitelistLimit, "Exceeds whitelist limit");
        require(address(this).balance >= value, "Insufficient balance");
        
        _checkDailyLimit(value);
        _updateDailyLimit(value);
        
        payable(to).transfer(value);
    }

    /**
     * @dev Add owner (with time lock)
     * @param owner New owner address
     */
    function proposeAddOwner(address owner) external onlyOwner ownerDoesNotExist(owner) {
        require(owner != address(0), "Invalid owner address");
        pendingOwnerAdditions[owner] = block.timestamp + ownerChangeLock;
    }

    /**
     * @dev Execute pending owner addition
     * @param owner Owner address to add
     */
    function addOwner(address owner) 
        external 
        onlyOwner 
        ownerDoesNotExist(owner) 
        validRequirement(owners.length + 1, requiredConfirmations) 
    {
        require(pendingOwnerAdditions[owner] != 0, "No pending addition");
        require(block.timestamp >= pendingOwnerAdditions[owner], "Time lock not expired");
        
        ownerInfo[owner] = Owner({
            isOwner: true,
            index: owners.length,
            addedAt: block.timestamp,
            active: true
        });
        owners.push(owner);
        
        delete pendingOwnerAdditions[owner];
        emit OwnerAdded(owner);
    }

    /**
     * @dev Remove owner (with time lock)
     * @param owner Owner address to remove
     */
    function proposeRemoveOwner(address owner) external onlyOwner ownerExists(owner) {
        require(owners.length > 1, "Cannot remove last owner");
        pendingOwnerRemovals[owner] = block.timestamp + ownerChangeLock;
    }

    /**
     * @dev Execute pending owner removal
     * @param owner Owner address to remove
     */
    function removeOwner(address owner) external onlyOwner ownerExists(owner) {
        require(pendingOwnerRemovals[owner] != 0, "No pending removal");
        require(block.timestamp >= pendingOwnerRemovals[owner], "Time lock not expired");
        
        Owner storage ownerData = ownerInfo[owner];
        ownerData.isOwner = false;
        ownerData.active = false;
        
        // Move last owner to the removed owner's position
        uint256 ownerIndex = ownerData.index;
        address lastOwner = owners[owners.length - 1];
        owners[ownerIndex] = lastOwner;
        ownerInfo[lastOwner].index = ownerIndex;
        owners.pop();
        
        // Adjust required confirmations if necessary
        if (requiredConfirmations > owners.length) {
            changeRequirement(owners.length);
        }
        
        delete pendingOwnerRemovals[owner];
        emit OwnerRemoved(owner);
    }

    /**
     * @dev Change required confirmations
     * @param _required New required confirmations
     */
    function changeRequirement(uint256 _required) 
        public 
        onlyOwner 
        validRequirement(owners.length, _required) 
    {
        requiredConfirmations = _required;
        emit RequirementChanged(_required);
    }

    /**
     * @dev Update whitelist status
     * @param account Address to update
     * @param whitelisted Whether to whitelist the address
     */
    function updateWhitelist(address account, bool whitelisted) external onlyOwner {
        whitelist[account] = whitelisted;
        emit WhitelistUpdated(account, whitelisted);
    }

    /**
     * @dev Set daily spending limit
     * @param limit New daily limit
     */
    function setDailyLimit(uint256 limit) external onlyOwner {
        dailyLimit.limit = limit;
        emit DailyLimitChanged(limit);
    }

    /**
     * @dev Set whitelist transfer limit
     * @param limit New whitelist limit
     */
    function setWhitelistLimit(uint256 limit) external onlyOwner {
        whitelistLimit = limit;
    }

    /**
     * @dev Toggle emergency mode
     */
    function toggleEmergencyMode() external {
        require(msg.sender == emergencyRecovery || ownerInfo[msg.sender].isOwner, "Unauthorized");
        emergencyMode = !emergencyMode;
        emit EmergencyModeToggled(emergencyMode);
    }

    /**
     * @dev Emergency withdrawal (only in emergency mode)
     * @param to Destination address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(address to, uint256 amount) 
        external 
        inEmergencyMode 
        nonReentrant 
    {
        require(msg.sender == emergencyRecovery, "Only emergency recovery");
        require(address(this).balance >= amount, "Insufficient balance");
        payable(to).transfer(amount);
    }

    /**
     * @dev Set emergency recovery address
     * @param newRecovery New emergency recovery address
     */
    function setEmergencyRecovery(address newRecovery) external onlyOwner {
        require(newRecovery != address(0), "Invalid recovery address");
        emergencyRecovery = newRecovery;
        emit EmergencyRecoveryChanged(newRecovery);
    }

    /**
     * @dev Check if transaction is confirmed
     * @param transactionId Transaction ID
     * @return Whether transaction has enough confirmations
     */
    function isConfirmed(uint256 transactionId) public view returns (bool) {
        return transactions[transactionId].confirmations >= requiredConfirmations;
    }

    /**
     * @dev Get transaction count
     * @return Number of transactions
     */
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /**
     * @dev Get owners array
     * @return Array of owner addresses
     */
    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    /**
     * @dev Get confirmations for a transaction
     * @param transactionId Transaction ID
     * @return Array of addresses that confirmed the transaction
     */
    function getConfirmations(uint256 transactionId) 
        external 
        view 
        returns (address[] memory _confirmations) 
    {
        address[] memory confirmationsTemp = new address[](owners.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < owners.length; i++) {
            if (confirmations[transactionId][owners[i]]) {
                confirmationsTemp[count] = owners[i];
                count++;
            }
        }
        
        _confirmations = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            _confirmations[i] = confirmationsTemp[i];
        }
    }

    /**
     * @dev Internal function to add transaction
     */
    function addTransaction(address to, uint256 value, bytes memory data) 
        internal 
        returns (uint256 transactionId) 
    {
        transactionId = transactions.length;
        transactions.push(Transaction({
            to: to,
            value: value,
            data: data,
            executed: false,
            confirmations: 0,
            createdAt: block.timestamp
        }));
        
        emit TransactionSubmitted(transactionId, msg.sender);
    }

    /**
     * @dev Check daily spending limit
     */
    function _checkDailyLimit(uint256 amount) internal view {
        if (dailyLimit.limit == 0) return; // No limit set
        
        DailyLimit memory limit = dailyLimit;
        
        // Reset if a day has passed
        if (block.timestamp >= limit.lastResetTime + 1 days) {
            require(amount <= limit.limit, "Exceeds daily limit");
        } else {
            require(limit.spent + amount <= limit.limit, "Exceeds daily limit");
        }
    }

    /**
     * @dev Update daily spending
     */
    function _updateDailyLimit(uint256 amount) internal {
        if (dailyLimit.limit == 0) return; // No limit set
        
        // Reset if a day has passed
        if (block.timestamp >= dailyLimit.lastResetTime + 1 days) {
            dailyLimit.spent = amount;
            dailyLimit.lastResetTime = block.timestamp;
        } else {
            dailyLimit.spent += amount;
        }
    }
}
