// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Burnable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Royalty.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title StandardERC721
 * @dev A comprehensive ERC721 NFT implementation with advanced features
 * 
 * Features:
 * - Enumerable tokens with supply tracking
 * - Individual token URI storage
 * - Pausable minting and transfers
 * - Burnable tokens
 * - EIP-2981 royalty support
 * - Batch minting capabilities
 * - Whitelist minting phases
 * - Reveal mechanism for metadata
 * - Max supply cap
 * - Per-wallet mint limits
 * 
 * Security Features:
 * - Access control with roles
 * - Reentrancy protection
 * - Emergency pause
 * - Owner and minter role separation
 */
contract StandardERC721 is 
    ERC721,
    ERC721Enumerable,
    ERC721URIStorage,
    ERC721Pausable,
    ERC721Burnable,
    ERC721Royalty,
    Ownable,
    AccessControl,
    ReentrancyGuard
{
    using Counters for Counters.Counter;

    /// @dev Role for addresses that can mint tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    
    /// @dev Role for addresses that can set URIs
    bytes32 public constant URI_SETTER_ROLE = keccak256("URI_SETTER_ROLE");

    /// @dev Token ID counter
    Counters.Counter private _tokenIdCounter;

    /// @dev Maximum supply of tokens
    uint256 public immutable MAX_SUPPLY;
    
    /// @dev Maximum tokens per wallet during public mint
    uint256 public maxPerWallet = 10;
    
    /// @dev Mint price in wei
    uint256 public mintPrice = 0.01 ether;
    
    /// @dev Base URI for token metadata
    string private _baseTokenURI;
    
    /// @dev Placeholder URI before reveal
    string private _placeholderURI;
    
    /// @dev Whether metadata is revealed
    bool public revealed = false;
    
    /// @dev Whether public minting is active
    bool public publicMintActive = false;
    
    /// @dev Whether whitelist minting is active
    bool public whitelistMintActive = false;
    
    /// @dev Mapping of whitelist addresses
    mapping(address => bool) public whitelist;
    
    /// @dev Mapping of addresses to number of tokens minted
    mapping(address => uint256) public mintedTokens;

    event MintPriceUpdated(uint256 oldPrice, uint256 newPrice);
    event MaxPerWalletUpdated(uint256 oldMax, uint256 newMax);
    event BaseURIUpdated(string oldURI, string newURI);
    event PlaceholderURIUpdated(string oldURI, string newURI);
    event Revealed(string baseURI);
    event PublicMintToggled(bool active);
    event WhitelistMintToggled(bool active);
    event WhitelistUpdated(address[] addresses, bool status);
    event BatchMinted(address indexed to, uint256 startTokenId, uint256 quantity);

    /**
     * @dev Constructor
     * @param name_ Token name
     * @param symbol_ Token symbol
     * @param maxSupply_ Maximum supply of tokens
     * @param baseURI_ Base URI for token metadata
     * @param placeholderURI_ Placeholder URI before reveal
     * @param owner_ Initial owner address
     */
    constructor(
        string memory name_,
        string memory symbol_,
        uint256 maxSupply_,
        string memory baseURI_,
        string memory placeholderURI_,
        address owner_
    ) 
        ERC721(name_, symbol_) 
        Ownable(owner_)
    {
        require(maxSupply_ > 0, "Max supply must be greater than 0");
        require(owner_ != address(0), "Owner cannot be zero address");
        
        MAX_SUPPLY = maxSupply_;
        _baseTokenURI = baseURI_;
        _placeholderURI = placeholderURI_;
        
        // Grant roles to owner
        _grantRole(DEFAULT_ADMIN_ROLE, owner_);
        _grantRole(MINTER_ROLE, owner_);
        _grantRole(URI_SETTER_ROLE, owner_);
        
        // Start token IDs at 1
        _tokenIdCounter.increment();
    }

    /**
     * @dev Mint a single token to specified address
     * @param to Address to mint token to
     */
    function mint(address to) external onlyRole(MINTER_ROLE) {
        require(totalSupply() < MAX_SUPPLY, "Max supply reached");
        
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        _safeMint(to, tokenId);
    }

    /**
     * @dev Batch mint multiple tokens to specified address
     * @param to Address to mint tokens to
     * @param quantity Number of tokens to mint
     */
    function batchMint(address to, uint256 quantity) external onlyRole(MINTER_ROLE) {
        require(quantity > 0, "Quantity must be greater than 0");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        
        uint256 startTokenId = _tokenIdCounter.current();
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(to, tokenId);
        }
        
        emit BatchMinted(to, startTokenId, quantity);
    }

    /**
     * @dev Public mint function
     * @param quantity Number of tokens to mint
     */
    function publicMint(uint256 quantity) external payable nonReentrant {
        require(publicMintActive, "Public mint not active");
        require(quantity > 0, "Quantity must be greater than 0");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        require(mintedTokens[msg.sender] + quantity <= maxPerWallet, "Exceeds max per wallet");
        require(msg.value >= mintPrice * quantity, "Insufficient payment");
        
        mintedTokens[msg.sender] += quantity;
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(msg.sender, tokenId);
        }
    }

    /**
     * @dev Whitelist mint function
     * @param quantity Number of tokens to mint
     */
    function whitelistMint(uint256 quantity) external payable nonReentrant {
        require(whitelistMintActive, "Whitelist mint not active");
        require(whitelist[msg.sender], "Not whitelisted");
        require(quantity > 0, "Quantity must be greater than 0");
        require(totalSupply() + quantity <= MAX_SUPPLY, "Exceeds max supply");
        require(mintedTokens[msg.sender] + quantity <= maxPerWallet, "Exceeds max per wallet");
        require(msg.value >= mintPrice * quantity, "Insufficient payment");
        
        mintedTokens[msg.sender] += quantity;
        
        for (uint256 i = 0; i < quantity; i++) {
            uint256 tokenId = _tokenIdCounter.current();
            _tokenIdCounter.increment();
            _safeMint(msg.sender, tokenId);
        }
    }

    /**
     * @dev Set mint price (only owner)
     * @param newPrice New mint price in wei
     */
    function setMintPrice(uint256 newPrice) external onlyOwner {
        uint256 oldPrice = mintPrice;
        mintPrice = newPrice;
        emit MintPriceUpdated(oldPrice, newPrice);
    }

    /**
     * @dev Set max tokens per wallet (only owner)
     * @param newMax New maximum tokens per wallet
     */
    function setMaxPerWallet(uint256 newMax) external onlyOwner {
        require(newMax > 0, "Max per wallet must be greater than 0");
        uint256 oldMax = maxPerWallet;
        maxPerWallet = newMax;
        emit MaxPerWalletUpdated(oldMax, newMax);
    }

    /**
     * @dev Set base URI for token metadata
     * @param newBaseURI New base URI
     */
    function setBaseURI(string calldata newBaseURI) external onlyRole(URI_SETTER_ROLE) {
        string memory oldURI = _baseTokenURI;
        _baseTokenURI = newBaseURI;
        emit BaseURIUpdated(oldURI, newBaseURI);
    }

    /**
     * @dev Set placeholder URI
     * @param newPlaceholderURI New placeholder URI
     */
    function setPlaceholderURI(string calldata newPlaceholderURI) external onlyRole(URI_SETTER_ROLE) {
        string memory oldURI = _placeholderURI;
        _placeholderURI = newPlaceholderURI;
        emit PlaceholderURIUpdated(oldURI, newPlaceholderURI);
    }

    /**
     * @dev Reveal metadata
     */
    function reveal() external onlyOwner {
        require(!revealed, "Already revealed");
        revealed = true;
        emit Revealed(_baseTokenURI);
    }

    /**
     * @dev Toggle public mint status
     */
    function togglePublicMint() external onlyOwner {
        publicMintActive = !publicMintActive;
        emit PublicMintToggled(publicMintActive);
    }

    /**
     * @dev Toggle whitelist mint status
     */
    function toggleWhitelistMint() external onlyOwner {
        whitelistMintActive = !whitelistMintActive;
        emit WhitelistMintToggled(whitelistMintActive);
    }

    /**
     * @dev Add/remove addresses from whitelist
     * @param addresses Array of addresses to update
     * @param status Whether to add (true) or remove (false) from whitelist
     */
    function updateWhitelist(address[] calldata addresses, bool status) external onlyOwner {
        for (uint256 i = 0; i < addresses.length; i++) {
            whitelist[addresses[i]] = status;
        }
        emit WhitelistUpdated(addresses, status);
    }

    /**
     * @dev Set default royalty for all tokens
     * @param receiver Royalty recipient address
     * @param feeNumerator Royalty fee in basis points (10000 = 100%)
     */
    function setDefaultRoyalty(address receiver, uint96 feeNumerator) external onlyOwner {
        _setDefaultRoyalty(receiver, feeNumerator);
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
     * @dev Withdraw contract balance (only owner)
     */
    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }

    /**
     * @dev Get token URI
     */
    function tokenURI(uint256 tokenId) public view override(ERC721, ERC721URIStorage) returns (string memory) {
        _requireMinted(tokenId);
        
        if (!revealed) {
            return _placeholderURI;
        }
        
        string memory storedURI = super.tokenURI(tokenId);
        if (bytes(storedURI).length > 0) {
            return storedURI;
        }
        
        return bytes(_baseTokenURI).length > 0 
            ? string(abi.encodePacked(_baseTokenURI, _toString(tokenId)))
            : "";
    }

    /**
     * @dev Get base URI
     */
    function _baseURI() internal view override returns (string memory) {
        return _baseTokenURI;
    }

    /**
     * @dev Convert uint256 to string
     */
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Required overrides
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Enumerable, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function _increaseBalance(address account, uint128 value)
        internal
        override(ERC721, ERC721Enumerable)
    {
        super._increaseBalance(account, value);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721, ERC721Enumerable, ERC721URIStorage, ERC721Royalty, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
