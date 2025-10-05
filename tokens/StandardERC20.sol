// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title StandardERC20
 * @dev A comprehensive ERC20 token implementation with advanced features
 * 
 * Features:
 * - Mintable by owner
 * - Burnable by token holders
 * - Pausable by owner
 * - Permit functionality (EIP-2612)
 * - Voting functionality (EIP-5805)
 * - Max supply cap
 * - Transfer fees (optional)
 * - Anti-whale protection
 * 
 * Security Features:
 * - Reentrancy protection
 * - Access control
 * - Emergency pause
 * - Maximum transaction limits
 */
contract StandardERC20 is 
    ERC20, 
    ERC20Burnable, 
    ERC20Pausable, 
    ERC20Permit, 
    ERC20Votes, 
    Ownable, 
    ReentrancyGuard 
{
    /// @dev Maximum supply of tokens (18 decimals)
    uint256 public immutable MAX_SUPPLY;
    
    /// @dev Transfer fee in basis points (100 = 1%)
    uint256 public transferFee = 0;
    
    /// @dev Maximum transaction amount (anti-whale)
    uint256 public maxTransactionAmount;
    
    /// @dev Fee recipient address
    address public feeRecipient;
    
    /// @dev Mapping of addresses exempt from fees
    mapping(address => bool) public feeExempt;
    
    /// @dev Mapping of addresses exempt from max transaction limit
    mapping(address => bool) public maxTxExempt;

    event TransferFeeUpdated(uint256 oldFee, uint256 newFee);
    event MaxTransactionAmountUpdated(uint256 oldAmount, uint256 newAmount);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event FeeExemptStatusUpdated(address account, bool exempt);
    event MaxTxExemptStatusUpdated(address account, bool exempt);

    /**
     * @dev Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param maxSupply_ Maximum supply (in wei, 18 decimals)
     * @param initialSupply_ Initial supply to mint to deployer
     * @param owner_ Initial owner address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        uint256 initialSupply_,
        address owner_
    ) 
        ERC20(name_, symbol_) 
        ERC20Permit(name_)
        Ownable(owner_)
    {
        require(maxSupply_ > 0, "Max supply must be greater than 0");
        require(initialSupply_ <= maxSupply_, "Initial supply exceeds max supply");
        require(owner_ != address(0), "Owner cannot be zero address");
        
        MAX_SUPPLY = maxSupply_;
        maxTransactionAmount = maxSupply_ / 100; // 1% of max supply
        feeRecipient = owner_;
        
        // Exempt owner from fees and max tx limits
        feeExempt[owner_] = true;
        maxTxExempt[owner_] = true;
        
        if (initialSupply_ > 0) {
            _mint(owner_, initialSupply_);
        }
    }

    /**
     * @dev Mint tokens to specified address
     * @param to Address to mint tokens to
     * @param amount Amount of tokens to mint
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(totalSupply() + amount <= MAX_SUPPLY, "Exceeds maximum supply");
        _mint(to, amount);
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
     * @dev Set maximum transaction amount
     * @param newMaxTxAmount New maximum transaction amount
     */
    function setMaxTransactionAmount(uint256 newMaxTxAmount) external onlyOwner {
        require(newMaxTxAmount >= totalSupply() / 1000, "Max tx amount too low");
        uint256 oldAmount = maxTransactionAmount;
        maxTransactionAmount = newMaxTxAmount;
        emit MaxTransactionAmountUpdated(oldAmount, newMaxTxAmount);
    }

    /**
     * @dev Set fee recipient address
     * @param newFeeRecipient New fee recipient address
     */
    function setFeeRecipient(address newFeeRecipient) external onlyOwner {
        require(newFeeRecipient != address(0), "Fee recipient cannot be zero address");
        address oldRecipient = feeRecipient;
        feeRecipient = newFeeRecipient;
        emit FeeRecipientUpdated(oldRecipient, newFeeRecipient);
    }

    /**
     * @dev Set fee exempt status for an address
     * @param account Address to update
     * @param exempt Whether the address is exempt from fees
     */
    function setFeeExempt(address account, bool exempt) external onlyOwner {
        feeExempt[account] = exempt;
        emit FeeExemptStatusUpdated(account, exempt);
    }

    /**
     * @dev Set max transaction exempt status for an address
     * @param account Address to update
     * @param exempt Whether the address is exempt from max tx limits
     */
    function setMaxTxExempt(address account, bool exempt) external onlyOwner {
        maxTxExempt[account] = exempt;
        emit MaxTxExemptStatusUpdated(account, exempt);
    }

    /**
     * @dev Pause all token transfers (emergency function)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @dev Unpause all token transfers
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @dev Override transfer to include fees and limits
     */
    function _update(
        address from,
        address to,
        uint256 value
    ) internal override(ERC20, ERC20Pausable, ERC20Votes) {
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
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC20) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev Emergency function to recover accidentally sent tokens
     * @param token Address of the token to recover
     * @param amount Amount to recover
     */
    function recoverToken(address token, uint256 amount) external onlyOwner nonReentrant {
        require(token != address(this), "Cannot recover own token");
        IERC20(token).transfer(owner(), amount);
    }

    /**
     * @dev Emergency function to recover accidentally sent ETH
     */
    function recoverETH() external onlyOwner nonReentrant {
        payable(owner()).transfer(address(this).balance);
    }
}
