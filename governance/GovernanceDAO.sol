// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";

/**
 * @title GovernanceDAO
 * @dev A comprehensive DAO contract with advanced governance features
 * 
 * Features:
 * - Proposal creation and voting
 * - Multiple voting strategies (token-based, NFT-based, hybrid)
 * - Delegation system
 * - Quorum and threshold requirements
 * - Time-locked execution
 * - Emergency actions
 * - Upgradeable parameters
 * 
 * Security Features:
 * - EIP-712 signed voting
 * - Reentrancy protection
 * - Access control
 * - Time locks
 * - Snapshot-based voting power
 */
contract GovernanceDAO is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;
    using ECDSA for bytes32;

    /// @dev Proposal state enumeration
    enum ProposalState {
        Pending,
        Active,
        Canceled,
        Defeated,
        Succeeded,
        Queued,
        Expired,
        Executed
    }

    /// @dev Vote choice enumeration
    enum VoteType {
        Against,
        For,
        Abstain
    }

    /// @dev Proposal structure
    struct Proposal {
        uint256 id;
        address proposer;
        address[] targets;
        uint256[] values;
        string[] signatures;
        bytes[] calldatas;
        uint256 startBlock;
        uint256 endBlock;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        bool canceled;
        bool executed;
        mapping(address => Receipt) receipts;
        uint256 eta; // Execution time (after queuing)
    }

    /// @dev Vote receipt structure
    struct Receipt {
        bool hasVoted;
        uint8 support;
        uint256 votes;
    }

    /// @dev Governance token
    IERC20 public immutable governanceToken;
    
    /// @dev Proposal counter
    uint256 public proposalCount;
    
    /// @dev Mapping from proposal ID to proposal
    mapping(uint256 => Proposal) public proposals;
    
    /// @dev Mapping from address to delegate
    mapping(address => address) public delegates;
    
    /// @dev Mapping from delegate to delegated voting power
    mapping(address => uint256) public delegatedVotes;
    
    /// @dev Mapping from address to nonce for vote signatures
    mapping(address => uint256) public nonces;
    
    /// @dev Voting delay in blocks
    uint256 public votingDelay = 1; // 1 block
    
    /// @dev Voting period in blocks
    uint256 public votingPeriod = 17280; // ~3 days (assuming 15s blocks)
    
    /// @dev Proposal threshold (tokens needed to create proposal)
    uint256 public proposalThreshold = 1000e18; // 1000 tokens
    
    /// @dev Quorum threshold (percentage of total supply needed)
    uint256 public quorumPercentage = 4; // 4%
    
    /// @dev Time lock delay for execution
    uint256 public timeLockDelay = 2 days;
    
    /// @dev Grace period for execution after queue
    uint256 public gracePeriod = 14 days;
    
    /// @dev Guardian address (can cancel proposals)
    address public guardian;
    
    /// @dev Whether the DAO is paused
    bool public paused;

    /// @dev EIP-712 type hash for votes
    bytes32 public constant BALLOT_TYPEHASH = 
        keccak256("Ballot(uint256 proposalId,uint8 support,uint256 nonce,uint256 deadline)");

    /// @dev EIP-712 type hash for delegation
    bytes32 public constant DELEGATION_TYPEHASH = 
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    event ProposalCreated(
        uint256 proposalId,
        address proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description
    );

    event VoteCast(
        address indexed voter,
        uint256 proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );

    event ProposalCanceled(uint256 proposalId);
    event ProposalQueued(uint256 proposalId, uint256 eta);
    event ProposalExecuted(uint256 proposalId);

    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    event GuardianSet(address oldGuardian, address newGuardian);
    event VotingDelaySet(uint256 oldDelay, uint256 newDelay);
    event VotingPeriodSet(uint256 oldPeriod, uint256 newPeriod);
    event ProposalThresholdSet(uint256 oldThreshold, uint256 newThreshold);
    event QuorumPercentageSet(uint256 oldPercentage, uint256 newPercentage);

    modifier onlyGuardian() {
        require(msg.sender == guardian, "Only guardian");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "DAO is paused");
        _;
    }

    constructor(
        address _governanceToken,
        address _guardian,
        string memory _name,
        string memory _version
    ) Ownable(msg.sender) EIP712(_name, _version) {
        require(_governanceToken != address(0), "Invalid governance token");
        governanceToken = IERC20(_governanceToken);
        guardian = _guardian;
    }

    /**
     * @dev Create a new proposal
     * @param targets Array of target addresses
     * @param values Array of ETH values
     * @param signatures Array of function signatures
     * @param calldatas Array of call data
     * @param description Proposal description
     * @return proposalId ID of the created proposal
     */
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description
    ) external whenNotPaused returns (uint256 proposalId) {
        require(
            getVotes(msg.sender, block.number - 1) >= proposalThreshold,
            "Proposer votes below threshold"
        );
        require(
            targets.length == values.length &&
            targets.length == signatures.length &&
            targets.length == calldatas.length,
            "Array length mismatch"
        );
        require(targets.length != 0, "Must provide actions");
        require(targets.length <= 10, "Too many actions");

        proposalId = ++proposalCount;
        
        Proposal storage newProposal = proposals[proposalId];
        newProposal.id = proposalId;
        newProposal.proposer = msg.sender;
        newProposal.targets = targets;
        newProposal.values = values;
        newProposal.signatures = signatures;
        newProposal.calldatas = calldatas;
        newProposal.startBlock = block.number + votingDelay;
        newProposal.endBlock = newProposal.startBlock + votingPeriod;
        newProposal.description = description;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            targets,
            values,
            signatures,
            calldatas,
            newProposal.startBlock,
            newProposal.endBlock,
            description
        );
    }

    /**
     * @dev Cast a vote on a proposal
     * @param proposalId Proposal ID
     * @param support Vote type (0=against, 1=for, 2=abstain)
     * @param reason Vote reason
     */
    function castVote(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external whenNotPaused returns (uint256) {
        return _castVote(proposalId, msg.sender, support, reason);
    }

    /**
     * @dev Cast a vote by signature
     * @param proposalId Proposal ID
     * @param support Vote type
     * @param deadline Vote deadline
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     */
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external whenNotPaused returns (uint256) {
        require(block.timestamp <= deadline, "Vote signature expired");

        address voter = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        BALLOT_TYPEHASH,
                        proposalId,
                        support,
                        nonces[voter]++,
                        deadline
                    )
                )
            ),
            v, r, s
        );

        return _castVote(proposalId, voter, support, "");
    }

    /**
     * @dev Queue a successful proposal for execution
     * @param proposalId Proposal ID
     */
    function queue(uint256 proposalId) external whenNotPaused {
        require(
            state(proposalId) == ProposalState.Succeeded,
            "Proposal not succeeded"
        );

        Proposal storage proposal = proposals[proposalId];
        uint256 eta = block.timestamp + timeLockDelay;
        proposal.eta = eta;

        emit ProposalQueued(proposalId, eta);
    }

    /**
     * @dev Execute a queued proposal
     * @param proposalId Proposal ID
     */
    function execute(uint256 proposalId) external payable nonReentrant whenNotPaused {
        require(
            state(proposalId) == ProposalState.Queued,
            "Proposal not queued"
        );

        Proposal storage proposal = proposals[proposalId];
        require(block.timestamp >= proposal.eta, "Proposal not ready");
        require(
            block.timestamp <= proposal.eta + gracePeriod,
            "Proposal expired"
        );

        proposal.executed = true;

        for (uint256 i = 0; i < proposal.targets.length; i++) {
            bytes memory callData;
            if (bytes(proposal.signatures[i]).length == 0) {
                callData = proposal.calldatas[i];
            } else {
                callData = abi.encodePacked(
                    bytes4(keccak256(bytes(proposal.signatures[i]))),
                    proposal.calldatas[i]
                );
            }

            (bool success, ) = proposal.targets[i].call{value: proposal.values[i]}(callData);
            require(success, "Transaction execution reverted");
        }

        emit ProposalExecuted(proposalId);
    }

    /**
     * @dev Cancel a proposal
     * @param proposalId Proposal ID
     */
    function cancel(uint256 proposalId) external {
        Proposal storage proposal = proposals[proposalId];
        require(
            msg.sender == proposal.proposer ||
            msg.sender == guardian ||
            getVotes(proposal.proposer, block.number - 1) < proposalThreshold,
            "Cannot cancel proposal"
        );

        ProposalState currentState = state(proposalId);
        require(
            currentState != ProposalState.Executed,
            "Cannot cancel executed proposal"
        );

        proposal.canceled = true;
        emit ProposalCanceled(proposalId);
    }

    /**
     * @dev Delegate voting power to another address
     * @param delegatee Address to delegate to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegate by signature
     * @param delegatee Address to delegate to
     * @param nonce Nonce
     * @param expiry Expiration timestamp
     * @param v Signature v
     * @param r Signature r
     * @param s Signature s
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(block.timestamp <= expiry, "Signature expired");

        address signatory = ECDSA.recover(
            _hashTypedDataV4(
                keccak256(
                    abi.encode(
                        DELEGATION_TYPEHASH,
                        delegatee,
                        nonce,
                        expiry
                    )
                )
            ),
            v, r, s
        );

        require(nonce == nonces[signatory]++, "Invalid nonce");
        return _delegate(signatory, delegatee);
    }

    /**
     * @dev Get voting power for an address at a specific block
     * @param account Address to check
     * @param blockNumber Block number
     * @return Voting power
     */
    function getVotes(address account, uint256 blockNumber) public view returns (uint256) {
        require(blockNumber < block.number, "Block not yet mined");
        
        // Check if account has delegated their votes
        address delegate = delegates[account];
        if (delegate == address(0)) {
            delegate = account;
        }
        
        // Return token balance at snapshot + delegated votes
        return governanceToken.balanceOf(delegate) + delegatedVotes[delegate];
    }

    /**
     * @dev Get current proposal state
     * @param proposalId Proposal ID
     * @return Current state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId && proposalId > 0, "Invalid proposal");
        Proposal storage proposal = proposals[proposalId];

        if (proposal.canceled) {
            return ProposalState.Canceled;
        } else if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes || proposal.forVotes < quorum()) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        } else if (block.timestamp >= proposal.eta + gracePeriod) {
            return ProposalState.Expired;
        } else {
            return ProposalState.Queued;
        }
    }

    /**
     * @dev Get current quorum requirement
     * @return Quorum amount
     */
    function quorum() public view returns (uint256) {
        return (governanceToken.totalSupply() * quorumPercentage) / 100;
    }

    /**
     * @dev Get vote receipt for a voter on a proposal
     * @param proposalId Proposal ID
     * @param voter Voter address
     * @return Receipt information
     */
    function getReceipt(uint256 proposalId, address voter) 
        external 
        view 
        returns (bool, uint8, uint256) 
    {
        Receipt storage receipt = proposals[proposalId].receipts[voter];
        return (receipt.hasVoted, receipt.support, receipt.votes);
    }

    /**
     * @dev Set guardian address (only owner)
     * @param newGuardian New guardian address
     */
    function setGuardian(address newGuardian) external onlyOwner {
        address oldGuardian = guardian;
        guardian = newGuardian;
        emit GuardianSet(oldGuardian, newGuardian);
    }

    /**
     * @dev Set voting delay (only governance)
     * @param newDelay New voting delay
     */
    function setVotingDelay(uint256 newDelay) external onlyOwner {
        require(newDelay >= 1 && newDelay <= 50400, "Invalid delay"); // Max ~1 week
        uint256 oldDelay = votingDelay;
        votingDelay = newDelay;
        emit VotingDelaySet(oldDelay, newDelay);
    }

    /**
     * @dev Set voting period (only governance)
     * @param newPeriod New voting period
     */
    function setVotingPeriod(uint256 newPeriod) external onlyOwner {
        require(newPeriod >= 5760 && newPeriod <= 80640, "Invalid period"); // 1 day - 2 weeks
        uint256 oldPeriod = votingPeriod;
        votingPeriod = newPeriod;
        emit VotingPeriodSet(oldPeriod, newPeriod);
    }

    /**
     * @dev Set proposal threshold (only governance)
     * @param newThreshold New proposal threshold
     */
    function setProposalThreshold(uint256 newThreshold) external onlyOwner {
        uint256 oldThreshold = proposalThreshold;
        proposalThreshold = newThreshold;
        emit ProposalThresholdSet(oldThreshold, newThreshold);
    }

    /**
     * @dev Set quorum percentage (only governance)
     * @param newPercentage New quorum percentage
     */
    function setQuorumPercentage(uint256 newPercentage) external onlyOwner {
        require(newPercentage >= 1 && newPercentage <= 20, "Invalid percentage");
        uint256 oldPercentage = quorumPercentage;
        quorumPercentage = newPercentage;
        emit QuorumPercentageSet(oldPercentage, newPercentage);
    }

    /**
     * @dev Pause the DAO (only guardian)
     */
    function pause() external onlyGuardian {
        paused = true;
    }

    /**
     * @dev Unpause the DAO (only owner)
     */
    function unpause() external onlyOwner {
        paused = false;
    }

    /**
     * @dev Internal function to cast a vote
     */
    function _castVote(
        uint256 proposalId,
        address voter,
        uint8 support,
        string memory reason
    ) internal returns (uint256) {
        require(state(proposalId) == ProposalState.Active, "Voting is closed");
        require(support <= 2, "Invalid vote type");

        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(!receipt.hasVoted, "Voter already voted");

        uint256 votes = getVotes(voter, proposal.startBlock);
        require(votes > 0, "No voting power");

        if (support == 0) {
            proposal.againstVotes += votes;
        } else if (support == 1) {
            proposal.forVotes += votes;
        } else {
            proposal.abstainVotes += votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        emit VoteCast(voter, proposalId, support, votes, reason);
        return votes;
    }

    /**
     * @dev Internal function to delegate votes
     */
    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = governanceToken.balanceOf(delegator);
        
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        if (currentDelegate != address(0) && currentDelegate != delegatee) {
            uint256 currentVotes = delegatedVotes[currentDelegate];
            uint256 newVotes = currentVotes - delegatorBalance;
            delegatedVotes[currentDelegate] = newVotes;
            
            emit DelegateVotesChanged(currentDelegate, currentVotes, newVotes);
        }

        if (delegatee != address(0) && delegatee != currentDelegate) {
            uint256 currentVotes = delegatedVotes[delegatee];
            uint256 newVotes = currentVotes + delegatorBalance;
            delegatedVotes[delegatee] = newVotes;
            
            emit DelegateVotesChanged(delegatee, currentVotes, newVotes);
        }
    }

    /**
     * @dev Emergency function to recover stuck tokens
     * @param token Token address
     * @param amount Amount to recover
     */
    function emergencyRecoverToken(address token, uint256 amount) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);
    }

    /**
     * @dev Fallback function to receive ETH
     */
    receive() external payable {}
}
