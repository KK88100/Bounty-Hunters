// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YieldVault {
    IERC20 public rewardToken;
    IERC20 public stakingToken;

    uint256 public rewardRate;
    uint256 public periodFinish;
    uint256 public lastUpdateTime;
    uint256 public rewardPerTokenStored;
    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public userRewardPerTokenPaid;
    mapping(address => uint256) public rewards;

    address public rewardDistributor;

    // Precision multiplier for reward rate calculation
    uint256 public constant PRECISION = 1e18;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardDistributorUpdated(address indexed oldDistributor, address indexed newDistributor);

    modifier onlyRewardDistributor() {
        require(msg.sender == rewardDistributor, "Not authorized");
        _;
    }

    constructor(address _stakingToken, address _rewardToken) {
        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        rewardDistributor = msg.sender;
    }

    /// @notice Returns the current reward per token, capped at periodFinish
    /// @dev After the reward period ends, no additional rewards accrue
    /// @dev rewardRate is stored with PRECISION (1e18) multiplier for precision
    function rewardPerToken() public view returns (uint256) {
        if (totalSupply == 0) return rewardPerTokenStored;

        uint256 timeElapsed = block.timestamp < periodFinish
            ? block.timestamp - lastUpdateTime
            : (periodFinish > lastUpdateTime ? periodFinish - lastUpdateTime : 0);

        // rewardRate already has PRECISION multiplier, no need to multiply again
        return rewardPerTokenStored + (
            timeElapsed * rewardRate / totalSupply
        );
    }

    /// @notice Returns the earned rewards for an account using the capped rewardPerToken
    function earned(address account) public view returns (uint256) {
        return balanceOf[account] * (rewardPerToken() - userRewardPerTokenPaid[account]) / PRECISION + rewards[account];
    }

    modifier updateReward(address account) {
        rewardPerTokenStored = rewardPerToken();
        // Cap lastUpdateTime at periodFinish to prevent phantom accrual
        lastUpdateTime = block.timestamp < periodFinish ? block.timestamp : periodFinish;
        if (account != address(0)) {
            rewards[account] = earned(account);
            userRewardPerTokenPaid[account] = rewardPerTokenStored;
        }
        _;
    }

    function deposit(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot deposit 0");
        totalSupply += amount;
        balanceOf[msg.sender] += amount;
        stakingToken.transferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    function withdraw(uint256 amount) external updateReward(msg.sender) {
        require(amount > 0, "Cannot withdraw 0");
        totalSupply -= amount;
        balanceOf[msg.sender] -= amount;
        stakingToken.transfer(msg.sender, amount);
        emit Withdrawn(msg.sender, amount);
    }

    function claimReward() external updateReward(msg.sender) {
        uint256 reward = rewards[msg.sender];
        if (reward > 0) {
            rewards[msg.sender] = 0;
            rewardToken.transfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    /// @notice Notifies the contract of a new reward amount
    /// @dev Only the authorized rewardDistributor can call this
    /// @dev Uses PRECISION multiplier to minimize precision loss
    function notifyRewardAmount(uint256 reward, uint256 duration) external onlyRewardDistributor updateReward(address(0)) {
        require(duration > 0, "Duration must be > 0");
        require(reward > 0, "Reward must be > 0");

        // Add any unclaimed remaining rewards to the new reward
        if (block.timestamp < periodFinish) {
            uint256 remaining = periodFinish - block.timestamp;
            uint256 leftover = remaining * rewardRate;
            reward += leftover;
        }

        // Use high-precision reward rate: store as (reward * PRECISION) / duration
        // This minimizes truncation error compared to raw division
        rewardRate = (reward * PRECISION) / duration;
        lastUpdateTime = block.timestamp;
        periodFinish = block.timestamp + duration;
    }

    /// @notice Updates the reward distributor address
    function setRewardDistributor(address newDistributor) external onlyRewardDistributor {
        require(newDistributor != address(0), "Invalid address");
        emit RewardDistributorUpdated(rewardDistributor, newDistributor);
        rewardDistributor = newDistributor;
    }
}
