// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VestingContract is Ownable, ReentrancyGuard {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    struct VestingSchedule {
        uint cliff; // Cliff period in seconds
        uint startTime; // Start time of the vesting schedule
        uint duration; // Total vesting duration in seconds
        uint amount; // Total amount of tokens to be vested
        uint claimed; // Amount of tokens claimed so far
    }

    mapping(address => VestingSchedule) public vestingSchedules;
    address public tokenAddress;
    uint public constant CLIFF_PERIOD = 90 days;
    uint public constant VESTING_DURATION = 270 days;

    event TokensClaimed(address indexed beneficiary, uint amount);
    event TokensDeposited(address indexed depositor, uint amount);
    event VestingScheduleCreated(address indexed beneficiary, uint amount);

    constructor(address _tokenAddress) {
        tokenAddress = _tokenAddress;
    }

    // Owner-only function to create a vesting schedule
    function createVestingSchedule(address beneficiary, uint amount) external onlyOwner {
        require(vestingSchedules[beneficiary].startTime == 0, "Vesting schedule already exists for this beneficiary");
        require(amount > 0, "Amount must be greater than 0");
        require(beneficiary != address(0), "Beneficiary cannot be the zero address");
        require(IERC20(tokenAddress).balanceOf(address(this)) >= amount, "Not enough tokens in the contract");

        uint startTime = block.timestamp;
        vestingSchedules[beneficiary] = VestingSchedule(CLIFF_PERIOD, startTime, VESTING_DURATION, amount, 0);

        emit VestingScheduleCreated(beneficiary, amount);
    }

    // Public function to claim vested tokens
    function claimTokens() external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[msg.sender];
        require(schedule.startTime > 0, "No vesting schedule found for the caller");

        uint vestedTokens = calculateVestedTokens(schedule);
        uint tokensToClaim = vestedTokens.sub(schedule.claimed);
        require(tokensToClaim > 0, "No tokens to claim");

        schedule.claimed = schedule.claimed.add(tokensToClaim);

        // Check-Effects-Interactions pattern to prevent reentrancy
        uint contractBalance = IERC20(tokenAddress).balanceOf(address(this));
        require(contractBalance >= tokensToClaim, "Not enough tokens in the contract");

        IERC20(tokenAddress).safeTransfer(msg.sender, tokensToClaim);

        emit TokensClaimed(msg.sender, tokensToClaim);
    }

    // Owner-only function to deposit tokens into the contract
    function depositTokens(uint amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");
        IERC20(tokenAddress).safeTransferFrom(msg.sender, address(this), amount);

        emit TokensDeposited(msg.sender, amount);
    }

    function calculateVestedTokens(VestingSchedule memory schedule) internal view returns (uint) {
        uint elapsedTime = block.timestamp.sub(schedule.startTime);
        if (elapsedTime < schedule.cliff) {
            return 0;
        } else if (elapsedTime >= schedule.duration) {
            return schedule.amount;
        } else {
            return schedule.amount.mul(elapsedTime).div(schedule.duration);
        }
    }
}
