// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title EnglishAuction
 * @dev A comprehensive English auction contract for NFTs and tokens
 * 
 * Features:
 * - Support for ERC721 NFTs and ERC20 tokens
 * - Configurable auction duration and reserve prices
 * - Automatic refunds for outbid participants
 * - Fee collection for platform
 * - Emergency pause functionality
 * - Bid extensions for last-minute activity
 * 
 * Security Features:
 * - Reentrancy protection
 * - Access control
 * - Emergency pause
 * - Safe token transfers
 */
contract EnglishAuction is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Auction structure
    struct Auction {
        address seller;         // Address of the seller
        address nftContract;    // Address of the NFT contract
        uint256 tokenId;        // Token ID of the NFT
        address paymentToken;   // Payment token (address(0) for ETH)
        uint256 startingBid;    // Starting bid amount
        uint256 reservePrice;   // Reserve price (minimum acceptable bid)
        uint256 currentBid;     // Current highest bid
        address currentBidder;  // Address of current highest bidder
        uint256 startTime;      // Auction start time
        uint256 endTime;        // Auction end time
        bool active;            // Whether auction is active
        bool ended;             // Whether auction has ended
        bool cancelled;         // Whether auction was cancelled
        uint256 bidCount;       // Number of bids placed
        uint256 bidIncrement;   // Minimum bid increment
    }

    /// @dev Auction ID counter
    uint256 private nextAuctionId = 1;
    
    /// @dev Mapping from auction ID to auction
    mapping(uint256 => Auction) public auctions;
    
    /// @dev Mapping from auction ID to bidder to bid amount
    mapping(uint256 => mapping(address => uint256)) public bids;
    
    /// @dev Platform fee in basis points (100 = 1%)
    uint256 public platformFee = 250; // 2.5%
    
    /// @dev Maximum platform fee (10%)
    uint256 public constant MAX_PLATFORM_FEE = 1000;
    
    /// @dev Minimum auction duration (1 hour)
    uint256 public constant MIN_AUCTION_DURATION = 1 hours;
    
    /// @dev Bid extension time (10 minutes)
    uint256 public bidExtensionTime = 10 minutes;
    
    /// @dev Platform fee recipient
    address public feeRecipient;
    
    /// @dev Whether the contract is paused
    bool public paused;

    event AuctionCreated(
        uint256 indexed auctionId,
        address indexed seller,
        address indexed nftContract,
        uint256 tokenId,
        uint256 startingBid,
        uint256 reservePrice,
        uint256 duration
    );
    
    event BidPlaced(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );
    
    event AuctionEnded(
        uint256 indexed auctionId,
        address indexed winner,
        uint256 winningBid
    );
    
    event AuctionCancelled(uint256 indexed auctionId);
    
    event BidRefunded(
        uint256 indexed auctionId,
        address indexed bidder,
        uint256 amount
    );
    
    event PlatformFeeUpdated(uint256 oldFee, uint256 newFee);
    event FeeRecipientUpdated(address oldRecipient, address newRecipient);
    event BidExtensionTimeUpdated(uint256 oldTime, uint256 newTime);

    modifier onlyWhenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier auctionExists(uint256 auctionId) {
        require(auctionId < nextAuctionId, "Auction does not exist");
        _;
    }

    modifier auctionActive(uint256 auctionId) {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(!auction.ended, "Auction has ended");
        require(!auction.cancelled, "Auction was cancelled");
        require(block.timestamp >= auction.startTime, "Auction not started");
        require(block.timestamp <= auction.endTime, "Auction has expired");
        _;
    }

    constructor(address _feeRecipient) Ownable(msg.sender) {
        require(_feeRecipient != address(0), "Invalid fee recipient");
        feeRecipient = _feeRecipient;
    }

    /**
     * @dev Create a new auction
     * @param nftContract Address of the NFT contract
     * @param tokenId Token ID of the NFT
     * @param paymentToken Payment token address (address(0) for ETH)
     * @param startingBid Starting bid amount
     * @param reservePrice Reserve price
     * @param duration Auction duration in seconds
     * @param bidIncrement Minimum bid increment
     * @return auctionId The ID of the created auction
     */
    function createAuction(
        address nftContract,
        uint256 tokenId,
        address paymentToken,
        uint256 startingBid,
        uint256 reservePrice,
        uint256 duration,
        uint256 bidIncrement
    ) external onlyWhenNotPaused returns (uint256 auctionId) {
        require(nftContract != address(0), "Invalid NFT contract");
        require(duration >= MIN_AUCTION_DURATION, "Duration too short");
        require(startingBid > 0, "Starting bid must be greater than 0");
        require(reservePrice >= startingBid, "Reserve price must be >= starting bid");
        require(bidIncrement > 0, "Bid increment must be greater than 0");

        // Verify ownership and get approval
        IERC721 nft = IERC721(nftContract);
        require(nft.ownerOf(tokenId) == msg.sender, "Not token owner");
        require(
            nft.getApproved(tokenId) == address(this) || 
            nft.isApprovedForAll(msg.sender, address(this)),
            "Contract not approved"
        );

        auctionId = nextAuctionId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + duration;

        auctions[auctionId] = Auction({
            seller: msg.sender,
            nftContract: nftContract,
            tokenId: tokenId,
            paymentToken: paymentToken,
            startingBid: startingBid,
            reservePrice: reservePrice,
            currentBid: 0,
            currentBidder: address(0),
            startTime: startTime,
            endTime: endTime,
            active: true,
            ended: false,
            cancelled: false,
            bidCount: 0,
            bidIncrement: bidIncrement
        });

        // Transfer NFT to contract
        nft.transferFrom(msg.sender, address(this), tokenId);

        emit AuctionCreated(
            auctionId,
            msg.sender,
            nftContract,
            tokenId,
            startingBid,
            reservePrice,
            duration
        );
    }

    /**
     * @dev Place a bid on an auction
     * @param auctionId Auction ID to bid on
     * @param bidAmount Bid amount (for ERC20 tokens)
     */
    function placeBid(uint256 auctionId, uint256 bidAmount) 
        external 
        payable 
        nonReentrant 
        onlyWhenNotPaused 
        auctionExists(auctionId) 
        auctionActive(auctionId) 
    {
        Auction storage auction = auctions[auctionId];
        require(msg.sender != auction.seller, "Seller cannot bid");

        uint256 totalBid;
        
        if (auction.paymentToken == address(0)) {
            // ETH auction
            require(msg.value > 0, "Must send ETH");
            totalBid = bids[auctionId][msg.sender] + msg.value;
        } else {
            // ERC20 token auction
            require(bidAmount > 0, "Bid amount must be greater than 0");
            require(msg.value == 0, "Do not send ETH for token auction");
            
            IERC20 token = IERC20(auction.paymentToken);
            require(
                token.allowance(msg.sender, address(this)) >= bidAmount,
                "Insufficient token allowance"
            );
            
            totalBid = bids[auctionId][msg.sender] + bidAmount;
            token.safeTransferFrom(msg.sender, address(this), bidAmount);
        }

        // Check minimum bid requirements
        if (auction.currentBid == 0) {
            require(totalBid >= auction.startingBid, "Bid below starting price");
        } else {
            require(
                totalBid >= auction.currentBid + auction.bidIncrement,
                "Bid increment too low"
            );
        }

        // Update bid tracking
        if (auction.paymentToken == address(0)) {
            bids[auctionId][msg.sender] += msg.value;
        } else {
            bids[auctionId][msg.sender] += bidAmount;
        }

        // Refund previous highest bidder if outbid
        if (auction.currentBidder != address(0) && auction.currentBidder != msg.sender) {
            _refundBidder(auctionId, auction.currentBidder);
        }

        // Update auction state
        auction.currentBid = totalBid;
        auction.currentBidder = msg.sender;
        auction.bidCount++;

        // Extend auction if bid placed in last minutes
        if (block.timestamp + bidExtensionTime > auction.endTime) {
            auction.endTime = block.timestamp + bidExtensionTime;
        }

        emit BidPlaced(auctionId, msg.sender, totalBid, block.timestamp);
    }

    /**
     * @dev End an auction
     * @param auctionId Auction ID to end
     */
    function endAuction(uint256 auctionId) 
        external 
        nonReentrant 
        onlyWhenNotPaused 
        auctionExists(auctionId) 
    {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(!auction.ended, "Auction already ended");
        require(!auction.cancelled, "Auction was cancelled");
        require(block.timestamp > auction.endTime, "Auction not finished");

        auction.ended = true;
        auction.active = false;

        if (auction.currentBid >= auction.reservePrice && auction.currentBidder != address(0)) {
            // Successful auction
            _transferNFT(auctionId, auction.currentBidder);
            _distributeFunds(auctionId);
            
            emit AuctionEnded(auctionId, auction.currentBidder, auction.currentBid);
        } else {
            // Failed auction - return NFT to seller
            IERC721(auction.nftContract).transferFrom(
                address(this),
                auction.seller,
                auction.tokenId
            );
            
            // Refund highest bidder if any
            if (auction.currentBidder != address(0)) {
                _refundBidder(auctionId, auction.currentBidder);
            }
            
            emit AuctionEnded(auctionId, address(0), 0);
        }
    }

    /**
     * @dev Cancel an auction (only seller, before any bids)
     * @param auctionId Auction ID to cancel
     */
    function cancelAuction(uint256 auctionId) 
        external 
        nonReentrant 
        onlyWhenNotPaused 
        auctionExists(auctionId) 
    {
        Auction storage auction = auctions[auctionId];
        require(msg.sender == auction.seller, "Only seller can cancel");
        require(auction.active, "Auction not active");
        require(!auction.ended, "Auction has ended");
        require(auction.bidCount == 0, "Cannot cancel auction with bids");

        auction.cancelled = true;
        auction.active = false;

        // Return NFT to seller
        IERC721(auction.nftContract).transferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );

        emit AuctionCancelled(auctionId);
    }

    /**
     * @dev Emergency cancel auction (only owner)
     * @param auctionId Auction ID to cancel
     */
    function emergencyCancel(uint256 auctionId) 
        external 
        onlyOwner 
        nonReentrant 
        auctionExists(auctionId) 
    {
        Auction storage auction = auctions[auctionId];
        require(auction.active, "Auction not active");
        require(!auction.ended, "Auction has ended");

        auction.cancelled = true;
        auction.active = false;

        // Return NFT to seller
        IERC721(auction.nftContract).transferFrom(
            address(this),
            auction.seller,
            auction.tokenId
        );

        // Refund current bidder if any
        if (auction.currentBidder != address(0)) {
            _refundBidder(auctionId, auction.currentBidder);
        }

        emit AuctionCancelled(auctionId);
    }

    /**
     * @dev Set platform fee (only owner)
     * @param newFee New platform fee in basis points
     */
    function setPlatformFee(uint256 newFee) external onlyOwner {
        require(newFee <= MAX_PLATFORM_FEE, "Fee exceeds maximum");
        uint256 oldFee = platformFee;
        platformFee = newFee;
        emit PlatformFeeUpdated(oldFee, newFee);
    }

    /**
     * @dev Set fee recipient (only owner)
     * @param newRecipient New fee recipient address
     */
    function setFeeRecipient(address newRecipient) external onlyOwner {
        require(newRecipient != address(0), "Invalid recipient");
        address oldRecipient = feeRecipient;
        feeRecipient = newRecipient;
        emit FeeRecipientUpdated(oldRecipient, newRecipient);
    }

    /**
     * @dev Set bid extension time (only owner)
     * @param newTime New bid extension time in seconds
     */
    function setBidExtensionTime(uint256 newTime) external onlyOwner {
        require(newTime >= 1 minutes && newTime <= 1 hours, "Invalid extension time");
        uint256 oldTime = bidExtensionTime;
        bidExtensionTime = newTime;
        emit BidExtensionTimeUpdated(oldTime, newTime);
    }

    /**
     * @dev Pause the contract
     */
    function pause() external onlyOwner {
        paused = true;
    }

    /**
     * @dev Unpause the contract
     */
    function unpause() external onlyOwner {
        paused = false;
    }

    /**
     * @dev Get auction information
     * @param auctionId Auction ID
     * @return Auction information
     */
    function getAuction(uint256 auctionId) external view returns (Auction memory) {
        require(auctionId < nextAuctionId, "Auction does not exist");
        return auctions[auctionId];
    }

    /**
     * @dev Get current auction count
     * @return Current auction count
     */
    function getCurrentAuctionId() external view returns (uint256) {
        return nextAuctionId - 1;
    }

    /**
     * @dev Get bid amount for a bidder in an auction
     * @param auctionId Auction ID
     * @param bidder Bidder address
     * @return Bid amount
     */
    function getBidAmount(uint256 auctionId, address bidder) external view returns (uint256) {
        return bids[auctionId][bidder];
    }

    /**
     * @dev Check if auction is active
     * @param auctionId Auction ID
     * @return Whether auction is active
     */
    function isAuctionActive(uint256 auctionId) external view returns (bool) {
        if (auctionId >= nextAuctionId) return false;
        
        Auction storage auction = auctions[auctionId];
        return auction.active && 
               !auction.ended && 
               !auction.cancelled &&
               block.timestamp >= auction.startTime && 
               block.timestamp <= auction.endTime;
    }

    /**
     * @dev Internal function to transfer NFT to winner
     */
    function _transferNFT(uint256 auctionId, address winner) internal {
        Auction storage auction = auctions[auctionId];
        IERC721(auction.nftContract).transferFrom(
            address(this),
            winner,
            auction.tokenId
        );
    }

    /**
     * @dev Internal function to distribute funds
     */
    function _distributeFunds(uint256 auctionId) internal {
        Auction storage auction = auctions[auctionId];
        uint256 totalAmount = auction.currentBid;
        
        // Calculate platform fee
        uint256 feeAmount = (totalAmount * platformFee) / 10000;
        uint256 sellerAmount = totalAmount - feeAmount;

        if (auction.paymentToken == address(0)) {
            // ETH transfer
            if (feeAmount > 0) {
                payable(feeRecipient).transfer(feeAmount);
            }
            payable(auction.seller).transfer(sellerAmount);
        } else {
            // ERC20 token transfer
            IERC20 token = IERC20(auction.paymentToken);
            if (feeAmount > 0) {
                token.safeTransfer(feeRecipient, feeAmount);
            }
            token.safeTransfer(auction.seller, sellerAmount);
        }

        // Clear winning bidder's recorded bid
        bids[auctionId][auction.currentBidder] = 0;
    }

    /**
     * @dev Internal function to refund a bidder
     */
    function _refundBidder(uint256 auctionId, address bidder) internal {
        uint256 bidAmount = bids[auctionId][bidder];
        if (bidAmount == 0) return;

        bids[auctionId][bidder] = 0;
        Auction storage auction = auctions[auctionId];

        if (auction.paymentToken == address(0)) {
            // ETH refund
            payable(bidder).transfer(bidAmount);
        } else {
            // ERC20 token refund
            IERC20(auction.paymentToken).safeTransfer(bidder, bidAmount);
        }

        emit BidRefunded(auctionId, bidder, bidAmount);
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address (address(0) for ETH)
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(amount);
        } else {
            IERC20(token).safeTransfer(owner(), amount);
        }
    }
}
