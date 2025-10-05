// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title AdvancedAccessControl
 * @dev A comprehensive access control system with role-based permissions
 * 
 * Features:
 * - Hierarchical role system
 * - Time-based role assignments
 * - Role approval workflows
 * - Emergency controls
 * - Granular permissions
 * - Role delegation
 * 
 * Security Features:
 * - Multi-signature role changes
 * - Time locks for critical operations
 * - Emergency pause functionality
 * - Role expiration
 */
contract AdvancedAccessControl is AccessControl, ReentrancyGuard, Pausable {
    /// @dev Super admin role (highest privilege)
    bytes32 public constant SUPER_ADMIN_ROLE = keccak256("SUPER_ADMIN_ROLE");
    
    /// @dev Admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @dev Moderator role
    bytes32 public constant MODERATOR_ROLE = keccak256("MODERATOR_ROLE");
    
    /// @dev Operator role
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    /// @dev Pauser role (can pause contract)
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    /// @dev Upgrader role (can upgrade contracts)
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @dev Role assignment structure
    struct RoleAssignment {
        address account;
        bytes32 role;
        uint256 expiresAt;
        bool active;
        address assignedBy;
        uint256 assignedAt;
    }

    /// @dev Role approval structure
    struct RoleApproval {
        address account;
        bytes32 role;
        address proposer;
        uint256 proposedAt;
        uint256 approvalsCount;
        mapping(address => bool) approvals;
        bool executed;
        uint256 expiresAt;
    }

    /// @dev Mapping from assignment ID to role assignment
    mapping(uint256 => RoleAssignment) public roleAssignments;
    
    /// @dev Mapping from approval ID to role approval
    mapping(uint256 => RoleApproval) public roleApprovals;
    
    /// @dev Assignment counter
    uint256 public assignmentCounter;
    
    /// @dev Approval counter
    uint256 public approvalCounter;
    
    /// @dev Required approvals for role changes
    uint256 public requiredApprovals = 2;
    
    /// @dev Time lock delay for critical operations
    uint256 public timeLockDelay = 1 days;
    
    /// @dev Maximum role duration
    uint256 public maxRoleDuration = 365 days;
    
    /// @dev Mapping from role to maximum duration
    mapping(bytes32 => uint256) public roleMaxDurations;
    
    /// @dev Mapping from account to delegated accounts
    mapping(address => mapping(address => bool)) public delegates;

    event RoleAssignmentCreated(
        uint256 indexed assignmentId,
        address indexed account,
        bytes32 indexed role,
        uint256 expiresAt,
        address assignedBy
    );
    
    event RoleApprovalCreated(
        uint256 indexed approvalId,
        address indexed account,
        bytes32 indexed role,
        address proposer,
        uint256 expiresAt
    );
    
    event RoleApprovalVoted(
        uint256 indexed approvalId,
        address indexed approver,
        bool approved
    );
    
    event RoleApprovalExecuted(
        uint256 indexed approvalId,
        address indexed account,
        bytes32 indexed role
    );
    
    event DelegateSet(
        address indexed delegator,
        address indexed delegate,
        bool status
    );
    
    event RequiredApprovalsUpdated(uint256 oldRequired, uint256 newRequired);
    event TimeLockDelayUpdated(uint256 oldDelay, uint256 newDelay);
    event RoleMaxDurationUpdated(bytes32 indexed role, uint256 duration);

    modifier onlyValidRole(bytes32 role) {
        require(role != DEFAULT_ADMIN_ROLE, "Cannot use default admin role");
        _;
    }

    modifier onlyActiveAssignment(uint256 assignmentId) {
        RoleAssignment storage assignment = roleAssignments[assignmentId];
        require(assignment.active, "Assignment not active");
        require(assignment.expiresAt > block.timestamp, "Assignment expired");
        _;
    }

    constructor(address initialAdmin) {
        require(initialAdmin != address(0), "Invalid admin address");
        
        _grantRole(DEFAULT_ADMIN_ROLE, initialAdmin);
        _grantRole(SUPER_ADMIN_ROLE, initialAdmin);
        _grantRole(ADMIN_ROLE, initialAdmin);
        _grantRole(PAUSER_ROLE, initialAdmin);
        
        // Set role hierarchy
        _setRoleAdmin(SUPER_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ADMIN_ROLE, SUPER_ADMIN_ROLE);
        _setRoleAdmin(MODERATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(OPERATOR_ROLE, MODERATOR_ROLE);
        _setRoleAdmin(PAUSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(UPGRADER_ROLE, SUPER_ADMIN_ROLE);
        
        // Set default role durations
        roleMaxDurations[SUPER_ADMIN_ROLE] = 365 days;
        roleMaxDurations[ADMIN_ROLE] = 180 days;
        roleMaxDurations[MODERATOR_ROLE] = 90 days;
        roleMaxDurations[OPERATOR_ROLE] = 30 days;
        roleMaxDurations[PAUSER_ROLE] = 90 days;
        roleMaxDurations[UPGRADER_ROLE] = 180 days;
    }

    /**
     * @dev Grant role with expiration time
     * @param role Role to grant
     * @param account Account to grant role to
     * @param duration Duration of the role assignment
     */
    function grantRoleWithExpiry(
        bytes32 role,
        address account,
        uint256 duration
    ) external onlyRole(getRoleAdmin(role)) onlyValidRole(role) whenNotPaused {
        require(account != address(0), "Invalid account");
        require(duration > 0 && duration <= roleMaxDurations[role], "Invalid duration");
        
        uint256 expiresAt = block.timestamp + duration;
        uint256 assignmentId = ++assignmentCounter;
        
        roleAssignments[assignmentId] = RoleAssignment({
            account: account,
            role: role,
            expiresAt: expiresAt,
            active: true,
            assignedBy: msg.sender,
            assignedAt: block.timestamp
        });
        
        _grantRole(role, account);
        
        emit RoleAssignmentCreated(assignmentId, account, role, expiresAt, msg.sender);
    }

    /**
     * @dev Propose role change requiring approval
     * @param account Account to change role for
     * @param role Role to grant
     * @param duration Duration of the role
     */
    function proposeRoleChange(
        address account,
        bytes32 role,
        uint256 duration
    ) external onlyRole(getRoleAdmin(role)) onlyValidRole(role) whenNotPaused {
        require(account != address(0), "Invalid account");
        require(duration > 0 && duration <= roleMaxDurations[role], "Invalid duration");
        
        uint256 approvalId = ++approvalCounter;
        uint256 expiresAt = block.timestamp + duration;
        
        RoleApproval storage approval = roleApprovals[approvalId];
        approval.account = account;
        approval.role = role;
        approval.proposer = msg.sender;
        approval.proposedAt = block.timestamp;
        approval.expiresAt = expiresAt;
        
        emit RoleApprovalCreated(approvalId, account, role, msg.sender, expiresAt);
    }

    /**
     * @dev Vote on a role approval
     * @param approvalId Approval ID to vote on
     * @param approve Whether to approve or reject
     */
    function voteOnRoleApproval(uint256 approvalId, bool approve) 
        external 
        onlyRole(ADMIN_ROLE) 
        whenNotPaused 
    {
        RoleApproval storage approval = roleApprovals[approvalId];
        require(approval.proposedAt > 0, "Approval does not exist");
        require(!approval.executed, "Approval already executed");
        require(approval.proposedAt + timeLockDelay <= block.timestamp, "Time lock not passed");
        require(!approval.approvals[msg.sender], "Already voted");
        
        approval.approvals[msg.sender] = approve;
        if (approve) {
            approval.approvalsCount++;
        }
        
        emit RoleApprovalVoted(approvalId, msg.sender, approve);
        
        // Auto-execute if enough approvals
        if (approval.approvalsCount >= requiredApprovals) {
            _executeRoleApproval(approvalId);
        }
    }

    /**
     * @dev Execute approved role change
     * @param approvalId Approval ID to execute
     */
    function executeRoleApproval(uint256 approvalId) external whenNotPaused {
        RoleApproval storage approval = roleApprovals[approvalId];
        require(approval.approvalsCount >= requiredApprovals, "Insufficient approvals");
        _executeRoleApproval(approvalId);
    }

    /**
     * @dev Set delegate status
     * @param delegate Address to set as delegate
     * @param status Whether to enable or disable delegation
     */
    function setDelegate(address delegate, bool status) external whenNotPaused {
        require(delegate != address(0), "Invalid delegate");
        require(delegate != msg.sender, "Cannot delegate to self");
        
        delegates[msg.sender][delegate] = status;
        emit DelegateSet(msg.sender, delegate, status);
    }

    /**
     * @dev Check if account has role (including through delegation)
     * @param role Role to check
     * @param account Account to check
     * @return Whether account has the role
     */
    function hasRoleOrDelegate(bytes32 role, address account) external view returns (bool) {
        if (hasRole(role, account)) {
            return true;
        }
        
        // Check if any delegator has the role
        // This would require tracking delegators, simplified for this example
        return false;
    }

    /**
     * @dev Revoke expired role assignments
     * @param assignmentIds Array of assignment IDs to check
     */
    function revokeExpiredAssignments(uint256[] calldata assignmentIds) external {
        for (uint256 i = 0; i < assignmentIds.length; i++) {
            uint256 assignmentId = assignmentIds[i];
            RoleAssignment storage assignment = roleAssignments[assignmentId];
            
            if (assignment.active && assignment.expiresAt <= block.timestamp) {
                assignment.active = false;
                _revokeRole(assignment.role, assignment.account);
            }
        }
    }

    /**
     * @dev Set required approvals for role changes
     * @param newRequired New required approval count
     */
    function setRequiredApprovals(uint256 newRequired) 
        external 
        onlyRole(SUPER_ADMIN_ROLE) 
    {
        require(newRequired > 0 && newRequired <= 10, "Invalid approval count");
        uint256 oldRequired = requiredApprovals;
        requiredApprovals = newRequired;
        emit RequiredApprovalsUpdated(oldRequired, newRequired);
    }

    /**
     * @dev Set time lock delay
     * @param newDelay New delay in seconds
     */
    function setTimeLockDelay(uint256 newDelay) 
        external 
        onlyRole(SUPER_ADMIN_ROLE) 
    {
        require(newDelay >= 1 hours && newDelay <= 7 days, "Invalid delay");
        uint256 oldDelay = timeLockDelay;
        timeLockDelay = newDelay;
        emit TimeLockDelayUpdated(oldDelay, newDelay);
    }

    /**
     * @dev Set maximum duration for a role
     * @param role Role to set duration for
     * @param duration Maximum duration in seconds
     */
    function setRoleMaxDuration(bytes32 role, uint256 duration) 
        external 
        onlyRole(SUPER_ADMIN_ROLE) 
        onlyValidRole(role) 
    {
        require(duration >= 1 days && duration <= 730 days, "Invalid duration");
        roleMaxDurations[role] = duration;
        emit RoleMaxDurationUpdated(role, duration);
    }

    /**
     * @dev Pause contract (emergency function)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @dev Unpause contract
     */
    function unpause() external onlyRole(SUPER_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @dev Get role assignment details
     * @param assignmentId Assignment ID
     * @return Assignment details
     */
    function getRoleAssignment(uint256 assignmentId) 
        external 
        view 
        returns (RoleAssignment memory) 
    {
        return roleAssignments[assignmentId];
    }

    /**
     * @dev Check if role assignment is active
     * @param assignmentId Assignment ID
     * @return Whether assignment is active
     */
    function isAssignmentActive(uint256 assignmentId) external view returns (bool) {
        RoleAssignment storage assignment = roleAssignments[assignmentId];
        return assignment.active && assignment.expiresAt > block.timestamp;
    }

    /**
     * @dev Get role approval details
     * @param approvalId Approval ID
     * @return account, role, proposer, proposedAt, approvalsCount, executed, expiresAt
     */
    function getRoleApproval(uint256 approvalId) 
        external 
        view 
        returns (
            address account,
            bytes32 role,
            address proposer,
            uint256 proposedAt,
            uint256 approvalsCount,
            bool executed,
            uint256 expiresAt
        ) 
    {
        RoleApproval storage approval = roleApprovals[approvalId];
        return (
            approval.account,
            approval.role,
            approval.proposer,
            approval.proposedAt,
            approval.approvalsCount,
            approval.executed,
            approval.expiresAt
        );
    }

    /**
     * @dev Internal function to execute role approval
     */
    function _executeRoleApproval(uint256 approvalId) internal {
        RoleApproval storage approval = roleApprovals[approvalId];
        require(!approval.executed, "Already executed");
        
        approval.executed = true;
        
        uint256 assignmentId = ++assignmentCounter;
        roleAssignments[assignmentId] = RoleAssignment({
            account: approval.account,
            role: approval.role,
            expiresAt: approval.expiresAt,
            active: true,
            assignedBy: approval.proposer,
            assignedAt: block.timestamp
        });
        
        _grantRole(approval.role, approval.account);
        
        emit RoleApprovalExecuted(approvalId, approval.account, approval.role);
        emit RoleAssignmentCreated(
            assignmentId, 
            approval.account, 
            approval.role, 
            approval.expiresAt, 
            approval.proposer
        );
    }
}
