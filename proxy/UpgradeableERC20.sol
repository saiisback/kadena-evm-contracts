// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title UpgradeableERC20
 * @dev A comprehensive upgradeable ERC20 token implementation using UUPS pattern
 * 
 * Features:
 * - UUPS upgradeable pattern
 * - Mintable and burnable
 * - Pausable functionality
 * - Access control
 * - Fee mechanism
 * - Anti-whale protection
 * - Blacklist functionality
 * 
 * Security Features:
 * - UUPS upgrade authorization
 * - Reentrancy protection
 * - Owner-only upgrade capability
 * - Initialize once protection
 */
contract UpgradeableERC20 is 
    Initializable,
    ERC20Upgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /// @dev Version of the implementation
    uint256 public constant VERSION = 1;
    
    /// @dev Maximum supply
    uint256 public maxSupply;
    
    /// @dev Transfer fee in basis points (100 = 1%)
    uint256 public transferFee;
    
    /// @dev Maximum transaction amount (anti-whale)
    uint256 public maxTransactionAmount;
    
    /// @dev Fee recipient
    address public feeRecipient;
    
    /// @dev Contract paused state
    bool public paused;
    
    /// @dev Mapping of fee-exempt addresses
    mapping(address => bool) public feeExempt;
    
    /// @dev Mapping of max transaction exempt addresses
    mapping(address => bool) public maxTxExempt;
    
    /// @dev Mapping of blacklisted addresses
    mapping(address => bool) public blacklisted;

    event TransferFeeUpdated(uint256 oldFee, uint256 newFee);
    event MaxTransactionAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeeExemptStatusUpdated(address account, bool exempt);
    event MaxTxExemptStatusUpdated(address account, bool exempt);
    event BlacklistStatusUpdated(address account, bool blacklisted);
    event Paused();
    event Unpaused();
    event ContractUpgraded(address indexed newImplementation, uint256 version);

    modifier whenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier notBlacklisted(address account) {
        require(!blacklisted[account], "Address is blacklisted");
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @dev Initialize the contract (replaces constructor for upgradeable contracts)
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param maxSupply_ Maximum supply
     * @param initialSupply_ Initial supply to mint
     * @param owner_ Initial owner
     * @param feeRecipient_ Fee recipient address
     */
    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 initialSupply_,
        address owner_,
        address feeRecipient_
    ) public initializer {
        require(maxSupply_ > 0, "Max supply must be greater than 0");
        require(initialSupply_ <= maxSupply_, "Initial supply exceeds max supply");
        require(owner_ != address(0), "Owner cannot be zero address");
        require(feeRecipient_ != address(0), "Fee recipient cannot be zero address");

        __ERC20_init(name_, symbol_);
        __Ownable_init(owner_);
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        maxSupply = maxSupply_;
        feeRecipient = feeRecipient_;
        maxTransactionAmount = maxSupply_ / 100; // 1% of max supply
        transferFee = 0; // No fee initially

        // Exempt owner from fees and limits
        feeExempt[owner_] = true;
        maxTxExempt[owner_] = true;

        if (initialSupply_ > 0) {
            _mint(owner_, initialSupply_);
        }
    }

    /**
     * @dev Mint tokens (only owner)
     * @param to Address to mint to
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) 
        external 
        onlyOwner 
        whenNotPaused 
        notBlacklisted(to) 
    {
        require(totalSupply() + amount <= maxSupply, "Exceeds maximum supply");
        _mint(to, amount);
    }

    /**
     * @dev Burn tokens from caller's balance
     * @param amount Amount to burn
     */
    function burn(uint256 amount) external whenNotPaused {
        _burn(msg.sender, amount);
    }

    /**
     * @dev Burn tokens from specified address (requires allowance)
     * @param from Address to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address from, uint256 amount) external whenNotPaused {
        _spendAllowance(from, msg.sender, amount);
        _burn(from, amount);
    }

    /**
     * @dev Set transfer fee (only owner)
     * @param newFee New fee in basis points (max 1000 = 10%)
     */
    function setTransferFee(uint256 newFee) external onlyOwner {
        require(newFee <= 1000, "Fee cannot exceed 10%");
        uint256 oldFee = transferFee;
        transferFee = newFee;
        emit TransferFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Set maximum transaction amount (only owner)
     * @param newMaxTxAmount New maximum transaction amount
     */
    function setMaxTransactionAmount(uint256 newMaxTxAmount) external onlyOwner {
        require(newMaxTxAmount >= totalSupply() / 1000, "Max tx amount too low");
        uint256 oldAmount = maxTransactionAmount;
        maxTransactionAmount = newMaxTxAmount;
        emit MaxTransactionAmountUpdated(oldAmount, newMaxTxAmount);
    }

    /**
     * @dev Set fee recipient (only owner)
     * @param newFeeRecipient New fee recipient
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Fee recipient cannot be zero address");
        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(oldRecipient, newFeeRecipient);
    }

    /**
     * @dev Set fee exempt status (only owner)
     * @param account Account to update
     * @param exempt Whether account is exempt from fees
     */
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
        emit FeeExemptStatusUpdated(account, exempt);
    }

    /**
     * @dev Set max transaction exempt status (only owner)
     * @param account Account to update
     * @param exempt Whether account is exempt from max tx limits
     */
    function setMaxTxExempt(address account, bool exempt) external onlyOwner {
        maxTxExempt[account] = exempt;
        emit MaxTxExemptStatusUpdated(account, exempt);
    }

    /**
     * @dev Set blacklist status (only owner)
     * @param account Account to update
     * @param blacklist Whether to blacklist the account
     */
    function setBlacklisted(address account, bool blacklist) external onlyOwner {
        blacklisted[account] = blacklist;
        emit BlacklistStatusUpdated(account, blacklist);
    }

    /**
     * @dev Batch set blacklist status (only owner)
     * @param accounts Array of accounts to update
     * @param blacklist Whether to blacklist the accounts
     */
    function batchSetBlacklisted(address[] calldata accounts, bool blacklist) external onlyOwner {
        for (uint256 i = 0; i < accounts.length; i++) {
            blacklisted[accounts[i]] = blacklist;
            emit BlacklistStatusUpdated(accounts[i], blacklist);
        }
    }

    /**
     * @dev Pause contract (only owner)
     */
    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    /**
     * @dev Unpause contract (only owner)
     */
    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }

    /**
     * @dev Override transfer to include fees and restrictions
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override whenNotPaused notBlacklisted(from) notBlacklisted(to) {
        // Apply max transaction limit (except for exempted addresses)
        if (from != address(0) && to != address(0)) {
            if (!maxTxExempt[from] && !maxTxExempt[to]) {
                require(value <= maxTransactionAmount, "Transfer amount exceeds maximum");
            }
        }

        // Calculate and apply transfer fee
        if (from != address(0) && to != address(0) && transferFee > 0) {
            if (!feeExempt[from] && !feeExempt[to]) {
                uint256 feeAmount = (value * transferFee) / 10000;
                if (feeAmount > 0) {
                    super._update(from, feeRecipient, feeAmount);
                    value -= feeAmount;
                }
            }
        }

        super._update(from, to, value);
    }

    /**
     * @dev Authorize upgrade (only owner can upgrade)
     * @param newImplementation Address of new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
        emit ContractUpgraded(newImplementation, VERSION);
    }

    /**
     * @dev Get implementation version
     * @return Implementation version
     */
    function getVersion() external pure returns (uint256) {
        return VERSION;
    }

    /**
     * @dev Emergency function to recover accidentally sent tokens
     * @param token Address of token to recover
     * @param amount Amount to recover
     */
    function recoverToken(address token, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(this), "Cannot recover own token");
        (bool success, ) = token.call(
            abi.encodeWithSignature("transfer(address,uint256)", owner(), amount)
        );
        require(success, "Token recovery failed");
    }

    /**
     * @dev Emergency function to recover accidentally sent ETH
     */
    function recoverETH() external onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }

    /**
     * @dev Get current implementation address
     * @return Implementation address
     */
    function getImplementation() external view returns (address) {
        return _getImplementation();
    }

    /**
     * @dev Check if contract is initialized
     * @return Whether contract is initialized
     */
    function isInitialized() external view returns (bool) {
        return _getInitializedVersion() > 0;
    }

    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[50] private __gap;
}
