// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/YieldVault.sol";

contract YieldVaultTest is Test {
    YieldVault public vault;
    IERC20 public stakingToken;
    IERC20 public rewardToken;
    address public user;
    address public attacker;
    address public distributor;

    function setUp() public {
        user = address(0xUSER);
        attacker = address(0xATTACK);
        distributor = address(0xDIST);

        // Deploy mock tokens
        stakingToken = new SimpleERC20("Staking Token", "STK", 1_000_000 ether);
        rewardToken = new SimpleERC20("Reward Token", "RWD", 1_000_000 ether);

        // Deploy vault (msg.sender = rewardDistributor)
        vm.prank(distributor);
        vault = new YieldVault(address(stakingToken), address(rewardToken));

        // Fund user with staking tokens
        SimpleERC20(address(stakingToken)).mint(user, 10000 ether);
        vm.startPrank(user);
        stakingToken.approve(address(vault), 10000 ether);
        vm.stopPrank();

        // Fund vault with reward tokens
        vm.prank(distributor);
        rewardToken.transfer(address(vault), 10000 ether);
    }

    function test_RewardAccrualDuringPeriod() public {
        // Setup: 1000 reward over 1000 seconds
        _setupRewards(1000 ether, 1000);

        // User deposits
        vm.prank(user);
        vault.deposit(100 ether);

        // Warp forward 500 seconds
        vm.warp(block.timestamp + 500);

        uint256 earned = vault.earned(user);
        assertTrue(earned > 0, "Should earn rewards during period");
        assertTrue(earned <= 500 ether, "Should not exceed proportional reward");
    }

    function test_NoPhantomRewardsAfterPeriod() public {
        _setupRewards(1000 ether, 1000);

        vm.prank(user);
        vault.deposit(100 ether);

        // Warp past the reward period
        vm.warp(block.timestamp + 2000);

        uint256 earnedDuring = vault.earned(user);

        // Warp even further — should NOT increase
        vm.warp(block.timestamp + 5000);

        uint256 earnedLater = vault.earned(user);

        assertEq(earnedDuring, earnedLater, "Rewards should not increase after period ends");
    }

    function test_RewardFreezeAfterPeriodExpiry() public {
        _setupRewards(1000 ether, 1000);

        vm.prank(user);
        vault.deposit(100 ether);

        vm.warp(block.timestamp + 1000); // Period ends

        uint256 earnedAtEnd = vault.earned(user);

        // Deposit more after period ends
        vm.prank(user);
        vault.deposit(100 ether);

        uint256 earnedAfterDeposit = vault.earned(user);

        // Rewards should be same — no accrual after period
        assertEq(earnedAtEnd, earnedAfterDeposit, "No new rewards after period");
    }

    function test_RevertUnauthorizedNotifyRewardAmount() public {
        vm.prank(attacker);
        vm.expectRevert("Not authorized");
        vault.notifyRewardAmount(1000 ether, 1000);
    }

    function test_AuthorizedNotifyRewardAmount() public {
        vm.prank(distributor);
        vault.notifyRewardAmount(1000 ether, 1000);
        assertEq(vault.periodFinish(), block.timestamp + 1000);
    }

    function test_ClaimRewards() public {
        _setupRewards(1000 ether, 1000);

        vm.prank(user);
        vault.deposit(100 ether);

        vm.warp(block.timestamp + 1000);

        uint256 balanceBefore = SimpleERC20(address(rewardToken)).balanceOf(user);

        vm.prank(user);
        vault.claimReward();

        uint256 balanceAfter = SimpleERC20(address(rewardToken)).balanceOf(user);
        assertTrue(balanceAfter > balanceBefore, "User should receive rewards");
    }

    function test_WithdrawAfterPeriod() public {
        _setupRewards(1000 ether, 1000);

        vm.prank(user);
        vault.deposit(100 ether);

        vm.warp(block.timestamp + 2000);

        uint256 balanceBefore = SimpleERC20(address(stakingToken)).balanceOf(user);
        assertEq(vault.balanceOf(user), 100 ether);

        vm.prank(user);
        vault.withdraw(100 ether);

        uint256 balanceAfter = SimpleERC20(address(stakingToken)).balanceOf(user);
        assertEq(balanceAfter - balanceBefore, 100 ether, "Should withdraw all stake");
    }

    function test_PrecisionReducedBelowThreshold() public {
        // Test with small reward and short duration to check precision
        _setupRewards(1000 ether, 3); // Can't divide 1000 by 3 evenly

        vm.prank(user);
        vault.deposit(100 ether);

        vm.warp(block.timestamp + 3);

        uint256 earnedAmount = vault.earned(user);

        // With 1000 / 3 precision, expect at most 0.01% error
        // Expected: 100 * 1000 / 100 = 1000 (since user has 100 of 100 total supply)
        uint256 expected = 1000 ether;
        uint256 error = expected > earnedAmount ? expected - earnedAmount : earnedAmount - expected;
        assertTrue(error <= expected / 10000, "Precision error should be < 0.01%");
    }

    function test_DepositAndWithdrawFlow() public {
        vm.prank(user);
        vault.deposit(50 ether);

        assertEq(vault.balanceOf(user), 50 ether);
        assertEq(vault.totalSupply(), 50 ether);

        vm.prank(user);
        vault.withdraw(25 ether);

        assertEq(vault.balanceOf(user), 25 ether);
        assertEq(vault.totalSupply(), 25 ether);
    }

    function test_UpdateRewardDistributor() public {
        vm.prank(distributor);
        vault.setRewardDistributor(address(0xNEW));

        vm.prank(address(0xNEW));
        vault.notifyRewardAmount(100 ether, 100);

        assertEq(vault.periodFinish(), block.timestamp + 100);
    }

    function _setupRewards(uint256 rewardAmount, uint256 duration) internal {
        vm.prank(distributor);
        vault.notifyRewardAmount(rewardAmount, duration);
    }
}

// Minimal ERC20 for testing
contract SimpleERC20 is IERC20 {
    string public name;
    string public symbol;
    uint8 public decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory _name, string memory _symbol, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        _mint(msg.sender, _initialSupply);
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        emit Transfer(from, to, amount);
        return true;
    }
}
