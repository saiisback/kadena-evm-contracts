// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Pausable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Burnable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/interfaces/IERC2981.sol";

/**
 * @title StandardERC1155
 * @dev A comprehensive ERC1155 multi-token implementation with advanced features
 * 
 * Features:
 * - Multi-token support with individual supplies
 * - Pausable minting and transfers
 * - Burnable tokens
 * - EIP-2981 royalty support
 * - Batch operations
 * - Per-token max supply limits
 * - Creator earnings distribution
 * - Metadata management per token
 * - Whitelist minting phases
 * 
 * Security Features:
 * - Access control with roles
 * - Reentrancy protection
 * - Emergency pause
 * - Creator and admin role separation
 */
contract StandardERC1155 is 
    ERC1155,
    ERC1155Pausable,
    ERC1155Burnable,
    ERC1155Supply,
    Ownable,
    AccessControl,
    ReentrancyGuard,
    IERC2981
{
    /// @dev Role for addresses that can mint tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @dev Role for addresses that can set URIs
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");
    
    /// @dev Role for token creators
    bytes32 public constant CREATOR_ROLE = keccak256("CREATOR_ROLE");

    /// @dev Token information structure
    struct TokenInfo {
        uint256 maxSupply;      // Maximum supply for this token (0 = unlimited)
        uint256 mintPrice;      // Price to mint this token
        address creator;        // Creator of this token
        uint96 royaltyFee;      // Royalty fee in basis points
        bool mintActive;        // Whether minting is active for this token
        bool whitelistOnly;     // Whether only whitelisted addresses can mint
        string uri;             // Individual URI for this token
    }

    /// @dev Mapping from token ID to token information
    mapping(uint256 => TokenInfo) public tokenInfo;
    
    /// @dev Mapping from token ID to whitelist addresses
    mapping(uint256 => mapping(address => bool)) public tokenWhitelist;
    
    /// @dev Mapping from token ID to per-wallet mint limits
    mapping(uint256 => uint256) public maxPerWallet;
    
    /// @dev Mapping from token ID to address to minted amount
    mapping(uint256 => mapping(address => uint256)) public mintedPerWallet;
    
    /// @dev Default royalty recipient (used if token doesn't have individual royalty)
    address public defaultRoyaltyRecipient;
    
    /// @dev Default royalty fee in basis points
    uint96 public defaultRoyaltyFee = 500; // 5%
    
    /// @dev Platform fee recipient
    address public platformFeeRecipient;
    
    /// @dev Platform fee in basis points
    uint96 public platformFee = 250; // 2.5%

    event TokenCreated(
        uint256 indexed tokenId,
        address indexed creator,
        uint256 maxSupply,
        uint256 mintPrice,
        string uri
    );
    event TokenInfoUpdated(uint256 indexed tokenId);
    event BatchMinted(address indexed to, uint256[] ids, uint256[] amounts);
    event RoyaltyUpdated(uint256 indexed tokenId, address recipient, uint96 fee);
    event DefaultRoyaltyUpdated(address recipient, uint96 fee);
    event PlatformFeeUpdated(address recipient, uint96 fee);
    event WhitelistUpdated(uint256 indexed tokenId, address[] addresses, bool status);

    /**
     * @dev Constructor
     * @param uri_ Base URI for all tokens
     * @param owner_ Initial owner address
     * @param platformFeeRecipient_ Platform fee recipient
     */
    constructor(
        string memory uri_,
        address owner_,
        address platformFeeRecipient_
    ) 
        ERC1155(uri_) 
        Ownable(owner_)
    {
        require(owner_ != address(0), "Owner cannot be zero address");
        require(platformFeeRecipient_ != address(0), "Platform fee recipient cannot be zero address");
        
        platformFeeRecipient = platformFeeRecipient_;
        defaultRoyaltyRecipient = owner_;
        
        // Grant roles to owner
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(MINTER_ROLE, owner_);
        _grantRole(URI_SETTER_ROLE, owner_);
        _grantRole(CREATOR_ROLE, owner_);
    }

    /**
     * @dev Create a new token type
     * @param tokenId Token ID to create
     * @param maxSupply Maximum supply (0 for unlimited)
     * @param mintPrice Price to mint one token
     * @param creator Creator address (receives royalties)
     * @param royaltyFee Royalty fee in basis points
     * @param tokenURI Individual URI for this token
     * @param maxPerWallet_ Maximum tokens per wallet
     */
    function createToken(
        uint256 tokenId,
        uint256 maxSupply,
        uint256 mintPrice,
        address creator,
        uint96 royaltyFee,
        string calldata tokenURI,
        uint256 maxPerWallet_
    ) external onlyRole(CREATOR_ROLE) {
        require(tokenInfo[tokenId].creator == address(0), "Token already exists");
        require(creator != address(0), "Creator cannot be zero address");
        require(royaltyFee <= 10000, "Royalty fee cannot exceed 100%");
        
        tokenInfo[tokenId] = TokenInfo({
            maxSupply: maxSupply,
            mintPrice: mintPrice,
            creator: creator,
            royaltyFee: royaltyFee,
            mintActive: true,
            whitelistOnly: false,
            uri: tokenURI
        });
        
        maxPerWallet[tokenId] = maxPerWallet_;
        
        emit TokenCreated(tokenId, creator, maxSupply, mintPrice, tokenURI);
    }

    /**
     * @dev Mint tokens to specified address
     * @param to Address to mint tokens to
     * @param tokenId Token ID to mint
     * @param amount Amount to mint
     * @param data Additional data
     */
    function mint(
        address to,
        uint256 tokenId,
        uint256 amount,
        bytes calldata data
    ) external onlyRole(MINTER_ROLE) {
        _validateMint(tokenId, amount);
        _mint(to, tokenId, amount, data);
    }

    /**
     * @dev Public mint function
     * @param tokenId Token ID to mint
     * @param amount Amount to mint
     */
    function publicMint(uint256 tokenId, uint256 amount) external payable nonReentrant {
        TokenInfo storage info = tokenInfo[tokenId];
        require(info.creator != address(0), "Token does not exist");
        require(info.mintActive, "Minting not active");
        require(!info.whitelistOnly, "Whitelist only mint");
        require(amount > 0, "Amount must be greater than 0");
        
        _validateMint(tokenId, amount);
        _validatePayment(tokenId, amount);
        _validateWalletLimit(tokenId, amount);
        
        mintedPerWallet[tokenId][msg.sender] += amount;
        _mint(msg.sender, tokenId, amount, "");
        
        _distributeFees(tokenId, amount);
    }

    /**
     * @dev Whitelist mint function
     * @param tokenId Token ID to mint
     * @param amount Amount to mint
     */
    function whitelistMint(uint256 tokenId, uint256 amount) external payable nonReentrant {
        TokenInfo storage info = tokenInfo[tokenId];
        require(info.creator != address(0), "Token does not exist");
        require(info.mintActive, "Minting not active");
        require(tokenWhitelist[tokenId][msg.sender], "Not whitelisted");
        require(amount > 0, "Amount must be greater than 0");
        
        _validateMint(tokenId, amount);
        _validatePayment(tokenId, amount);
        _validateWalletLimit(tokenId, amount);
        
        mintedPerWallet[tokenId][msg.sender] += amount;
        _mint(msg.sender, tokenId, amount, "");
        
        _distributeFees(tokenId, amount);
    }

    /**
     * @dev Batch mint multiple token types to specified address
     * @param to Address to mint tokens to
     * @param tokenIds Array of token IDs to mint
     * @param amounts Array of amounts to mint
     * @param data Additional data
     */
    function batchMint(
        address to,
        uint256[] calldata tokenIds,
        uint256[] calldata amounts,
        bytes calldata data
    ) external onlyRole(MINTER_ROLE) {
        require(tokenIds.length == amounts.length, "Arrays length mismatch");
        
        for (uint256 i = 0; i < tokenIds.length; i++) {
            _validateMint(tokenIds[i], amounts[i]);
        }
        
        _mintBatch(to, tokenIds, amounts, data);
        emit BatchMinted(to, tokenIds, amounts);
    }

    /**
     * @dev Update token information
     * @param tokenId Token ID to update
     * @param mintPrice New mint price
     * @param mintActive Whether minting is active
     * @param whitelistOnly Whether only whitelisted addresses can mint
     * @param maxPerWallet_ New max per wallet limit
     */
    function updateTokenInfo(
        uint256 tokenId,
        uint256 mintPrice,
        bool mintActive,
        bool whitelistOnly,
        uint256 maxPerWallet_
    ) external {
        TokenInfo storage info = tokenInfo[tokenId];
        require(info.creator == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
        
        info.mintPrice = mintPrice;
        info.mintActive = mintActive;
        info.whitelistOnly = whitelistOnly;
        maxPerWallet[tokenId] = maxPerWallet_;
        
        emit TokenInfoUpdated(tokenId);
    }

    /**
     * @dev Add/remove addresses from token whitelist
     * @param tokenId Token ID
     * @param addresses Array of addresses to update
     * @param status Whether to add (true) or remove (false) from whitelist
     */
    function updateTokenWhitelist(
        uint256 tokenId,
        address[] calldata addresses,
        bool status
    ) external {
        TokenInfo storage info = tokenInfo[tokenId];
        require(info.creator == msg.sender || hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Not authorized");
        
        for (uint256 i = 0; i < addresses.length; i++) {
            tokenWhitelist[tokenId][addresses[i]] = status;
        }
        
        emit WhitelistUpdated(tokenId, addresses, status);
    }

    /**
     * @dev Set URI for a specific token
     * @param tokenId Token ID
     * @param tokenURI New URI for the token
     */
    function setTokenURI(uint256 tokenId, string calldata tokenURI) external onlyRole(URI_SETTER_ROLE) {
        tokenInfo[tokenId].uri = tokenURI;
        emit URI(tokenURI, tokenId);
    }

    /**
     * @dev Set base URI for all tokens
     * @param newURI New base URI
     */
    function setURI(string calldata newURI) external onlyRole(URI_SETTER_ROLE) {
        _setURI(newURI);
    }

    /**
     * @dev Set default royalty information
     * @param recipient Royalty recipient address
     * @param fee Royalty fee in basis points
     */
    function setDefaultRoyalty(address recipient, uint96 fee) external onlyOwner {
        require(recipient != address(0), "Recipient cannot be zero address");
        require(fee <= 10000, "Fee cannot exceed 100%");
        
        defaultRoyaltyRecipient = recipient;
        defaultRoyaltyFee = fee;
        
        emit DefaultRoyaltyUpdated(recipient, fee);
    }

    /**
     * @dev Set platform fee information
     * @param recipient Platform fee recipient address
     * @param fee Platform fee in basis points
     */
    function setPlatformFee(address recipient, uint96 fee) external onlyOwner {
        require(recipient != address(0), "Recipient cannot be zero address");
        require(fee <= 1000, "Platform fee cannot exceed 10%");
        
        platformFeeRecipient = recipient;
        platformFee = fee;
        
        emit PlatformFeeUpdated(recipient, fee);
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
     * @dev Get URI for a specific token
     */
    function uri(uint256 tokenId) public view override returns (string memory) {
        string memory tokenURI = tokenInfo[tokenId].uri;
        if (bytes(tokenURI).length > 0) {
            return tokenURI;
        }
        return super.uri(tokenId);
    }

    /**
     * @dev EIP-2981 royalty information
     */
    function royaltyInfo(uint256 tokenId, uint256 salePrice)
        external
        view
        override
        returns (address receiver, uint256 royaltyAmount)
    {
        TokenInfo storage info = tokenInfo[tokenId];
        if (info.creator != address(0) && info.royaltyFee > 0) {
            return (info.creator, (salePrice * info.royaltyFee) / 10000);
        }
        
        if (defaultRoyaltyRecipient != address(0) && defaultRoyaltyFee > 0) {
            return (defaultRoyaltyRecipient, (salePrice * defaultRoyaltyFee) / 10000);
        }
        
        return (address(0), 0);
    }

    /**
     * @dev Validate mint operation
     */
    function _validateMint(uint256 tokenId, uint256 amount) internal view {
        TokenInfo storage info = tokenInfo[tokenId];
        require(info.creator != address(0), "Token does not exist");
        
        if (info.maxSupply > 0) {
            require(totalSupply(tokenId) + amount <= info.maxSupply, "Exceeds max supply");
        }
    }

    /**
     * @dev Validate payment for mint
     */
    function _validatePayment(uint256 tokenId, uint256 amount) internal view {
        TokenInfo storage info = tokenInfo[tokenId];
        require(msg.value >= info.mintPrice * amount, "Insufficient payment");
    }

    /**
     * @dev Validate wallet limit for mint
     */
    function _validateWalletLimit(uint256 tokenId, uint256 amount) internal view {
        uint256 limit = maxPerWallet[tokenId];
        if (limit > 0) {
            require(mintedPerWallet[tokenId][msg.sender] + amount <= limit, "Exceeds max per wallet");
        }
    }

    /**
     * @dev Distribute fees from minting
     */
    function _distributeFees(uint256 tokenId, uint256 amount) internal {
        TokenInfo storage info = tokenInfo[tokenId];
        uint256 totalFee = info.mintPrice * amount;
        
        if (totalFee > 0) {
            // Calculate platform fee
            uint256 platformFeeAmount = (totalFee * platformFee) / 10000;
            uint256 creatorAmount = totalFee - platformFeeAmount;
            
            // Transfer platform fee
            if (platformFeeAmount > 0) {
                payable(platformFeeRecipient).transfer(platformFeeAmount);
            }
            
            // Transfer remaining to creator
            if (creatorAmount > 0) {
                payable(info.creator).transfer(creatorAmount);
            }
        }
    }

    // Required overrides
    function _update(address from, address to, uint256[] memory ids, uint256[] memory values)
        internal
        override(ERC1155, ERC1155Pausable, ERC1155Supply)
    {
        super._update(from, to, ids, values);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC1155, AccessControl, IERC165)
        returns (bool)
    {
        return interfaceId == type(IERC2981).interfaceId || super.supportsInterface(interfaceId);
    }
}
