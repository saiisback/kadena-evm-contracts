// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title TokenVesting
 * @dev A comprehensive token vesting contract with multiple vesting schedules
 * 
 * Features:
 * - Multiple vesting schedules per beneficiary
 * - Linear and cliff vesting options
 * - Revocable vesting schedules
 * - Emergency pause functionality
 * - Multiple token support
 * - Batch operations for efficiency
 * 
 * Security Features:
 * - Reentrancy protection
 * - Access control
 * - Emergency pause
 * - Safe token transfers
 */
contract TokenVesting is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @dev Vesting schedule structure
    struct VestingSchedule {
        bool initialized;       // Whether the schedule is initialized
        address beneficiary;    // Address of the beneficiary
        uint256 cliff;          // Cliff period in seconds
        uint256 start;          // Start time of the vesting period
        uint256 duration;       // Duration of the vesting period
        uint256 slicePeriodSeconds; // Duration of a slice period for the vesting
        bool revocable;         // Whether the vesting is revocable
        uint256 amountTotal;    // Total amount of tokens to be released at the end of vesting
        uint256 released;       // Amount of token released
        bool revoked;           // Whether the vesting has been revoked
    }

    /// @dev ERC20 token being vested
    IERC20 public immutable token;
    
    /// @dev Current vesting schedule count
    uint256 private vestingSchedulesCount;
    
    /// @dev Total amount of token locked in vesting schedules
    uint256 private vestingSchedulesTotalAmount;
    
    /// @dev Mapping from vesting schedule id to vesting schedule
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    
    /// @dev Mapping from beneficiary to list of vesting schedule ids
    mapping(address => bytes32[]) private beneficiaryVestingSchedules;
    
    /// @dev Whether the contract is paused
    bool public paused;

    event VestingScheduleCreated(
        bytes32 indexed vestingScheduleId,
        address indexed beneficiary,
        uint256 amount,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        bool revocable
    );
    
    event TokensReleased(
        bytes32 indexed vestingScheduleId,
        address indexed beneficiary,
        uint256 amount
    );
    
    event VestingScheduleRevoked(
        bytes32 indexed vestingScheduleId,
        address indexed beneficiary,
        uint256 unreleased
    );
    
    event Paused();
    event Unpaused();

    modifier onlyWhenNotPaused() {
        require(!paused, "Contract is paused");
        _;
    }

    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].initialized, "Vesting schedule does not exist");
        _;
    }

    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(!vestingSchedules[vestingScheduleId].revoked, "Vesting schedule revoked");
        _;
    }

    /**
     * @dev Constructor
     * @param token_ Address of the ERC20 token contract
     */
    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "Token address cannot be zero");
        token = IERC20(token_);
    }

    /**
     * @dev Creates a new vesting schedule for a beneficiary
     * @param beneficiary Address of the beneficiary to whom vested tokens are transferred
     * @param start Start time of the vesting period
     * @param cliff Duration in seconds of the cliff in which tokens will begin to vest
     * @param duration Duration in seconds of the period in which the tokens will vest
     * @param slicePeriodSeconds Duration of a slice period for the vesting in seconds
     * @param revocable Whether the vesting is revocable or not
     * @param amount Total amount of tokens to be released at the end of vesting
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 start,
        uint256 cliff,
        uint256 duration,
        uint256 slicePeriodSeconds,
        bool revocable,
        uint256 amount
    ) external onlyOwner onlyWhenNotPaused {
        require(beneficiary != address(0), "Beneficiary cannot be zero address");
        require(duration > 0, "Duration must be > 0");
        require(amount > 0, "Amount must be > 0");
        require(slicePeriodSeconds >= 1, "Slice period must be >= 1");
        require(duration >= cliff, "Duration must be >= cliff");
        require(getWithdrawableAmount() >= amount, "Cannot create vesting schedule: insufficient tokens");

        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(beneficiary);
        uint256 currentVestingAmount = vestingSchedulesTotalAmount;
        vestingSchedulesTotalAmount = currentVestingAmount + amount;

        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            beneficiary,
            cliff,
            start,
            duration,
            slicePeriodSeconds,
            revocable,
            amount,
            0,
            false
        );

        vestingSchedulesCount = vestingSchedulesCount + 1;
        beneficiaryVestingSchedules[beneficiary].push(vestingScheduleId);

        emit VestingScheduleCreated(
            vestingScheduleId,
            beneficiary,
            amount,
            start,
            cliff,
            duration,
            revocable
        );
    }

    /**
     * @dev Batch create vesting schedules
     * @param beneficiaries Array of beneficiary addresses
     * @param starts Array of start times
     * @param cliffs Array of cliff durations
     * @param durations Array of vesting durations
     * @param slicePeriodSeconds Slice period for all schedules
     * @param revocable Whether all schedules are revocable
     * @param amounts Array of vesting amounts
     */
    function batchCreateVestingSchedules(
        address[] calldata beneficiaries,
        uint256[] calldata starts,
        uint256[] calldata cliffs,
        uint256[] calldata durations,
        uint256 slicePeriodSeconds,
        bool revocable,
        uint256[] calldata amounts
    ) external onlyOwner onlyWhenNotPaused {
        require(
            beneficiaries.length == starts.length &&
            starts.length == cliffs.length &&
            cliffs.length == durations.length &&
            durations.length == amounts.length,
            "Array lengths must match"
        );

        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        require(getWithdrawableAmount() >= totalAmount, "Insufficient tokens for batch creation");

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            createVestingSchedule(
                beneficiaries[i],
                starts[i],
                cliffs[i],
                durations[i],
                slicePeriodSeconds,
                revocable,
                amounts[i]
            );
        }
    }

    /**
     * @dev Revokes the vesting schedule for given identifier
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(bytes32 vestingScheduleId)
        external
        onlyOwner
        onlyIfVestingScheduleExists(vestingScheduleId)
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revocable, "Vesting is not revocable");
        
        uint256 vestedAmount = _computeReleasableAmount(vestingScheduleId);
        if (vestedAmount > 0) {
            release(vestingScheduleId, vestedAmount);
        }
        
        uint256 unreleased = vestingSchedule.amountTotal - vestingSchedule.released;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - unreleased;
        vestingSchedule.revoked = true;
        
        emit VestingScheduleRevoked(vestingScheduleId, vestingSchedule.beneficiary, unreleased);
    }

    /**
     * @dev Release vested tokens for a vesting schedule
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(bytes32 vestingScheduleId, uint256 amount)
        public
        nonReentrant
        onlyWhenNotPaused
        onlyIfVestingScheduleExists(vestingScheduleId)
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "Only beneficiary and owner can release vested tokens");
        
        uint256 vestedAmount = _computeReleasableAmount(vestingScheduleId);
        require(vestedAmount >= amount, "Cannot release more than vested amount");
        
        vestingSchedule.released = vestingSchedule.released + amount;
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount - amount;
        
        token.safeTransfer(vestingSchedule.beneficiary, amount);
        
        emit TokensReleased(vestingScheduleId, vestingSchedule.beneficiary, amount);
    }

    /**
     * @dev Release all available vested tokens for a beneficiary
     * @param beneficiary the beneficiary address
     */
    function releaseAvailableTokensForBeneficiary(address beneficiary)
        external
        nonReentrant
        onlyWhenNotPaused
    {
        bytes32[] memory schedules = beneficiaryVestingSchedules[beneficiary];
        require(schedules.length > 0, "No vesting schedules for beneficiary");
        
        for (uint256 i = 0; i < schedules.length; i++) {
            bytes32 scheduleId = schedules[i];
            if (!vestingSchedules[scheduleId].revoked) {
                uint256 releasableAmount = _computeReleasableAmount(scheduleId);
                if (releasableAmount > 0) {
                    release(scheduleId, releasableAmount);
                }
            }
        }
    }

    /**
     * @dev Computes the vested amount of tokens for the given vesting schedule identifier
     * @param vestingScheduleId the vesting schedule identifier
     */
    function computeReleasableAmount(bytes32 vestingScheduleId)
        external
        view
        onlyIfVestingScheduleExists(vestingScheduleId)
        returns (uint256)
    {
        return _computeReleasableAmount(vestingScheduleId);
    }

    /**
     * @dev Returns the vesting schedule information for a given identifier
     * @param vestingScheduleId the vesting schedule identifier
     */
    function getVestingSchedule(bytes32 vestingScheduleId)
        external
        view
        returns (VestingSchedule memory)
    {
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return token.balanceOf(address(this)) - vestingSchedulesTotalAmount;
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address
     * @param holder the holder address
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, beneficiaryVestingSchedules[holder].length);
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address
     * @param holder the holder address
     */
    function getLastVestingScheduleForHolder(address holder) external view returns (bytes32) {
        return beneficiaryVestingSchedules[holder][beneficiaryVestingSchedules[holder].length - 1];
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index
     * @param holder the holder address
     * @param index the index
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index)
        public
        pure
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary
     * @param beneficiary the beneficiary address
     */
    function getVestingSchedulesCountByBeneficiary(address beneficiary) external view returns (uint256) {
        return beneficiaryVestingSchedules[beneficiary].length;
    }

    /**
     * @dev Returns the vesting schedule id at the given index for a beneficiary
     * @param beneficiary the beneficiary address
     * @param index the index
     */
    function getVestingIdAtIndex(address beneficiary, uint256 index) external view returns (bytes32) {
        require(index < beneficiaryVestingSchedules[beneficiary].length, "Index out of bounds");
        return beneficiaryVestingSchedules[beneficiary][index];
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract
     */
    function getVestingSchedulesCount() external view returns (uint256) {
        return vestingSchedulesCount;
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule
     * @param vestingScheduleId the vesting schedule identifier
     */
    function _computeReleasableAmount(bytes32 vestingScheduleId) internal view returns (uint256) {
        VestingSchedule memory vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule
     * @param vestingSchedule the vesting schedule
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        if ((currentTime < vestingSchedule.start + vestingSchedule.cliff) || vestingSchedule.revoked) {
            return 0;
        } else if (currentTime >= vestingSchedule.start + vestingSchedule.duration) {
            return vestingSchedule.amountTotal - vestingSchedule.released;
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.start;
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart / secondsPerSlice;
            uint256 vestedSeconds = vestedSlicePeriods * secondsPerSlice;
            uint256 vestedAmount = (vestingSchedule.amountTotal * vestedSeconds) / vestingSchedule.duration;
            vestedAmount = vestedAmount - vestingSchedule.released;
            return vestedAmount;
        }
    }

    /**
     * @dev Returns the current time
     */
    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     * @dev Withdraw tokens that are not part of any vesting schedule
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(getWithdrawableAmount() >= amount, "Not enough withdrawable funds");
        token.safeTransfer(owner(), amount);
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
     * @dev Emergency function to recover accidentally sent tokens
     * @param tokenAddress Address of the token to recover
     * @param amount Amount to recover
     */
    function recoverToken(address tokenAddress, uint256 amount) external onlyOwner nonReentrant {
        require(tokenAddress != address(token), "Cannot recover vesting token");
        IERC20(tokenAddress).safeTransfer(owner(), amount);
    }
}
