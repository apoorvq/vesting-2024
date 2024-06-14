// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/utils/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/release-v4.9/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title VestingContract
 * @dev This contract handles the vesting of ERC20 tokens for beneficiaries.
 */
contract VestingContract is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        uint256 cliff; // Cliff period in seconds
        uint256 startTime; // Start time of the vesting schedule
        uint256 duration; // Total vesting duration in seconds
        uint256 amount; // Total amount of tokens to be vested
        uint256 claimed; // Amount of tokens claimed so far
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    IERC20 public token;
    uint256 public totalVestedAmount;

    event TokensClaimed(address indexed beneficiary, uint256 amount);
    event TokensDeposited(address indexed depositor, uint256 amount);
    event VestingScheduleCreated(address indexed beneficiary, uint256 amount);

    /**
     * @dev Sets the token to be vested.
     * @param _tokenAddress The address of the ERC20 token.
     */
    constructor(address _tokenAddress) Ownable() {
        require(_tokenAddress != address(0), "Token address cannot be zero");
        token = IERC20(_tokenAddress);
    }

    /**
     * @dev Creates a vesting schedule for a beneficiary.
     * @param beneficiary The address of the beneficiary.
     * @param amount The amount of tokens to be vested.
     * @param cliff The cliff period in seconds.
     * @param duration The total duration of the vesting schedule in seconds.
     */
    function createVestingSchedule(
        address beneficiary,
        uint256 amount,
        uint256 cliff,
        uint256 duration
    ) external onlyOwner {
        require(vestingSchedules[beneficiary].startTime == 0, "Vesting schedule already exists for this beneficiary");
        require(amount > 0, "Amount must be greater than 0");
        require(beneficiary != address(0), "Beneficiary cannot be the zero address");
        require(cliff <= duration, "Cliff period cannot be longer than vesting duration");
        
        uint256 availableTokens = token.balanceOf(address(this)).sub(totalVestedAmount);
        require(availableTokens >= amount, "Not enough tokens available for the new vesting schedule");

        uint256 startTime = block.timestamp;
        vestingSchedules[beneficiary] = VestingSchedule(cliff, startTime, duration, amount, 0);
        totalVestedAmount = totalVestedAmount.add(amount);

        emit VestingScheduleCreated(beneficiary, amount);
    }

    /**
     * @dev Claims the vested tokens for the caller.
     */
    function claimTokens() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.startTime > 0, "No vesting schedule found for the caller");

        uint256 vestedTokens = calculateVestedTokens(schedule);
        uint256 tokensToClaim = vestedTokens.sub(schedule.claimed);
        require(tokensToClaim > 0, "No tokens to claim");

        schedule.claimed = schedule.claimed.add(tokensToClaim);

        // Check-Effects-Interactions pattern to prevent reentrancy
        uint256 contractBalance = token.balanceOf(address(this));
        require(contractBalance >= tokensToClaim, "Not enough tokens in the contract");

        token.safeTransfer(msg.sender, tokensToClaim);

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    /**
     * @dev Deposits tokens into the contract for future vesting.
     * @param amount The amount of tokens to deposit.
     */
    function depositTokens(uint256 amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        token.safeTransferFrom(msg.sender, address(this), amount);

        emit TokensDeposited(msg.sender, amount);
    }

    /**
     * @dev Calculates the number of vested tokens for a given schedule.
     * @param schedule The vesting schedule to calculate for.
     * @return The number of vested tokens.
     */
    function calculateVestedTokens(VestingSchedule memory schedule) internal view returns (uint256) {
        uint256 elapsedTime = block.timestamp.sub(schedule.startTime);
        if (elapsedTime < schedule.cliff) {
            return 0;
        } else if (elapsedTime >= schedule.duration) {
            return schedule.amount;
        } else {
            return schedule.amount.mul(elapsedTime).div(schedule.duration);
        }
    }
}
