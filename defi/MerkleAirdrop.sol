// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title MerkleAirdrop
 * @dev A comprehensive airdrop contract using Merkle trees for efficient distribution
 * 
 * Features:
 * - Merkle tree-based whitelist verification
 * - Multiple airdrop campaigns
 * - Configurable claim windows
 * - Anti-sybil protection
 * - Batch claim functionality
 * - Emergency pause and recovery
 * 
 * Security Features:
 * - Reentrancy protection
 * - Access control
 * - Merkle proof verification
 * - Double-claim prevention
 */
contract MerkleAirdrop is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Airdrop campaign structure
    struct AirdropCampaign {
        IERC20 token;           // Token being airdropped
        bytes32 merkleRoot;     // Merkle root of the airdrop
        uint256 startTime;      // Start time of the airdrop
        uint256 endTime;        // End time of the airdrop
        uint256 totalAmount;    // Total amount allocated for this campaign
        uint256 claimedAmount;  // Amount already claimed
        bool paused;            // Whether the campaign is paused
        bool exists;            // Whether the campaign exists
    }

    /// @dev Campaign ID counter
    uint256 private nextCampaignId = 1;
    
    /// @dev Mapping from campaign ID to airdrop campaign
    mapping(uint256 => AirdropCampaign) public campaigns;
    
    /// @dev Mapping from campaign ID to claimed status (campaign => user => claimed)
    mapping(uint256 => mapping(address => bool)) public claimed;
    
    /// @dev Mapping from campaign ID to claimed amounts (campaign => user => amount)
    mapping(uint256 => mapping(address => uint256)) public claimedAmounts;

    event CampaignCreated(
        uint256 indexed campaignId,
        address indexed token,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    );
    
    event Claimed(
        uint256 indexed campaignId,
        address indexed user,
        uint256 amount
    );
    
    event CampaignPaused(uint256 indexed campaignId);
    event CampaignUnpaused(uint256 indexed campaignId);
    
    event CampaignUpdated(
        uint256 indexed campaignId,
        bytes32 newMerkleRoot,
        uint256 newEndTime
    );
    
    event TokensRecovered(
        uint256 indexed campaignId,
        address indexed token,
        uint256 amount
    );

    modifier campaignExists(uint256 campaignId) {
        require(campaigns[campaignId].exists, "Campaign does not exist");
        _;
    }

    modifier campaignActive(uint256 campaignId) {
        AirdropCampaign storage campaign = campaigns[campaignId];
        require(!campaign.paused, "Campaign is paused");
        require(block.timestamp >= campaign.startTime, "Campaign not started");
        require(block.timestamp <= campaign.endTime, "Campaign ended");
        _;
    }

    constructor() Ownable(msg.sender) {}

    /**
     * @dev Create a new airdrop campaign
     * @param token Token to be airdropped
     * @param merkleRoot Merkle root of eligible addresses and amounts
     * @param totalAmount Total amount of tokens allocated for this campaign
     * @param startTime Start time of the campaign
     * @param endTime End time of the campaign
     * @return campaignId The ID of the created campaign
     */
    function createCampaign(
        address token,
        bytes32 merkleRoot,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner returns (uint256 campaignId) {
        require(token != address(0), "Invalid token address");
        require(merkleRoot != bytes32(0), "Invalid merkle root");
        require(totalAmount > 0, "Total amount must be greater than 0");
        require(startTime < endTime, "Invalid time range");
        require(endTime > block.timestamp, "End time must be in the future");

        campaignId = nextCampaignId++;
        
        campaigns[campaignId] = AirdropCampaign({
            token: IERC20(token),
            merkleRoot: merkleRoot,
            startTime: startTime,
            endTime: endTime,
            totalAmount: totalAmount,
            claimedAmount: 0,
            paused: false,
            exists: true
        });

        // Transfer tokens to this contract
        IERC20(token).safeTransferFrom(msg.sender, address(this), totalAmount);

        emit CampaignCreated(
            campaignId,
            token,
            merkleRoot,
            totalAmount,
            startTime,
            endTime
        );
    }

    /**
     * @dev Claim tokens from an airdrop campaign
     * @param campaignId Campaign ID to claim from
     * @param amount Amount of tokens to claim
     * @param merkleProof Merkle proof for verification
     */
    function claim(
        uint256 campaignId,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external nonReentrant campaignExists(campaignId) campaignActive(campaignId) {
        require(!claimed[campaignId][msg.sender], "Already claimed");
        require(amount > 0, "Amount must be greater than 0");

        AirdropCampaign storage campaign = campaigns[campaignId];
        
        // Verify merkle proof
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender, amount));
        require(
            MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf),
            "Invalid merkle proof"
        );

        // Check if there are enough tokens left
        require(
            campaign.claimedAmount + amount <= campaign.totalAmount,
            "Insufficient tokens in campaign"
        );

        // Mark as claimed
        claimed[campaignId][msg.sender] = true;
        claimedAmounts[campaignId][msg.sender] = amount;
        campaign.claimedAmount += amount;

        // Transfer tokens
        campaign.token.safeTransfer(msg.sender, amount);

        emit Claimed(campaignId, msg.sender, amount);
    }

    /**
     * @dev Batch claim from multiple campaigns
     * @param campaignIds Array of campaign IDs
     * @param amounts Array of amounts to claim
     * @param merkleProofs Array of merkle proofs
     */
    function batchClaim(
        uint256[] calldata campaignIds,
        uint256[] calldata amounts,
        bytes32[][] calldata merkleProofs
    ) external nonReentrant {
        require(
            campaignIds.length == amounts.length && 
            amounts.length == merkleProofs.length,
            "Array lengths must match"
        );

        for (uint256 i = 0; i < campaignIds.length; i++) {
            claim(campaignIds[i], amounts[i], merkleProofs[i]);
        }
    }

    /**
     * @dev Check if a user has claimed from a campaign
     * @param campaignId Campaign ID
     * @param user User address
     * @return Whether the user has claimed
     */
    function hasClaimed(uint256 campaignId, address user) external view returns (bool) {
        return claimed[campaignId][user];
    }

    /**
     * @dev Get claimed amount for a user in a campaign
     * @param campaignId Campaign ID
     * @param user User address
     * @return Amount claimed by the user
     */
    function getClaimedAmount(uint256 campaignId, address user) external view returns (uint256) {
        return claimedAmounts[campaignId][user];
    }

    /**
     * @dev Verify if a claim is valid without executing it
     * @param campaignId Campaign ID
     * @param user User address
     * @param amount Amount to claim
     * @param merkleProof Merkle proof
     * @return Whether the claim is valid
     */
    function verifyClaim(
        uint256 campaignId,
        address user,
        uint256 amount,
        bytes32[] calldata merkleProof
    ) external view campaignExists(campaignId) returns (bool) {
        if (claimed[campaignId][user]) return false;
        if (amount == 0) return false;
        
        AirdropCampaign storage campaign = campaigns[campaignId];
        if (campaign.claimedAmount + amount > campaign.totalAmount) return false;
        
        bytes32 leaf = keccak256(abi.encodePacked(user, amount));
        return MerkleProof.verify(merkleProof, campaign.merkleRoot, leaf);
    }

    /**
     * @dev Update campaign merkle root and end time (only owner)
     * @param campaignId Campaign ID to update
     * @param newMerkleRoot New merkle root
     * @param newEndTime New end time
     */
    function updateCampaign(
        uint256 campaignId,
        bytes32 newMerkleRoot,
        uint256 newEndTime
    ) external onlyOwner campaignExists(campaignId) {
        require(newMerkleRoot != bytes32(0), "Invalid merkle root");
        require(newEndTime > block.timestamp, "End time must be in the future");
        
        AirdropCampaign storage campaign = campaigns[campaignId];
        require(block.timestamp < campaign.startTime, "Campaign already started");
        
        campaign.merkleRoot = newMerkleRoot;
        campaign.endTime = newEndTime;
        
        emit CampaignUpdated(campaignId, newMerkleRoot, newEndTime);
    }

    /**
     * @dev Pause a campaign (only owner)
     * @param campaignId Campaign ID to pause
     */
    function pauseCampaign(uint256 campaignId) external onlyOwner campaignExists(campaignId) {
        campaigns[campaignId].paused = true;
        emit CampaignPaused(campaignId);
    }

    /**
     * @dev Unpause a campaign (only owner)
     * @param campaignId Campaign ID to unpause
     */
    function unpauseCampaign(uint256 campaignId) external onlyOwner campaignExists(campaignId) {
        campaigns[campaignId].paused = false;
        emit CampaignUnpaused(campaignId);
    }

    /**
     * @dev Recover unclaimed tokens after campaign ends (only owner)
     * @param campaignId Campaign ID
     */
    function recoverTokens(uint256 campaignId) external onlyOwner campaignExists(campaignId) nonReentrant {
        AirdropCampaign storage campaign = campaigns[campaignId];
        require(block.timestamp > campaign.endTime, "Campaign not ended");
        
        uint256 unclaimedAmount = campaign.totalAmount - campaign.claimedAmount;
        require(unclaimedAmount > 0, "No tokens to recover");
        
        campaign.totalAmount = campaign.claimedAmount;
        campaign.token.safeTransfer(owner(), unclaimedAmount);
        
        emit TokensRecovered(campaignId, address(campaign.token), unclaimedAmount);
    }

    /**
     * @dev Emergency function to recover accidentally sent tokens
     * @param token Token address to recover
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner nonReentrant {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Get campaign information
     * @param campaignId Campaign ID
     * @return Campaign information
     */
    function getCampaign(uint256 campaignId) external view returns (AirdropCampaign memory) {
        require(campaigns[campaignId].exists, "Campaign does not exist");
        return campaigns[campaignId];
    }

    /**
     * @dev Get current campaign ID
     * @return Current campaign ID
     */
    function getCurrentCampaignId() external view returns (uint256) {
        return nextCampaignId - 1;
    }

    /**
     * @dev Get remaining tokens in a campaign
     * @param campaignId Campaign ID
     * @return Remaining tokens
     */
    function getRemainingTokens(uint256 campaignId) external view campaignExists(campaignId) returns (uint256) {
        AirdropCampaign storage campaign = campaigns[campaignId];
        return campaign.totalAmount - campaign.claimedAmount;
    }

    /**
     * @dev Check if a campaign is active
     * @param campaignId Campaign ID
     * @return Whether the campaign is active
     */
    function isCampaignActive(uint256 campaignId) external view campaignExists(campaignId) returns (bool) {
        AirdropCampaign storage campaign = campaigns[campaignId];
        return !campaign.paused && 
               block.timestamp >= campaign.startTime && 
               block.timestamp <= campaign.endTime;
    }
}
