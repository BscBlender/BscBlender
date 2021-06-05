// SPDX-License-Identifier: MIT


pragma solidity 0.7.6;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//BSCBlender.com
contract BlendLiquidityMining is Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    struct PoolInfo {
        IERC20 lpToken;
        uint256 lastRewardBlock;
        uint256 accBlendPerShare;
    }

    IERC20 public blend;
    uint256 public blendPerBlock = uint256(45 ether).div(10); //4.5 BLEND

    PoolInfo public liquidityMining;
    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event Claim(address indexed user, uint256 amount);

    function setBlendTokens(IERC20 _blend, IERC20 _lpToken) external onlyOwner {
        require(address(blend) == address(0) && address(liquidityMining.lpToken) == address(0), 'Tokens already set!');
        blend = _blend;
        liquidityMining =
            PoolInfo({
                lpToken: _lpToken,
                lastRewardBlock: 0,
                accBlendPerShare: 0
        });
    }
    
    function startMining(uint256 startBlock) external onlyOwner {
        require(liquidityMining.lastRewardBlock == 0, 'Mining already started');
        liquidityMining.lastRewardBlock = startBlock;
    }

    function pendingRewards(address _user) external view returns (uint256) {
        require(liquidityMining.lastRewardBlock > 0 && block.number >= liquidityMining.lastRewardBlock, 'Mining not yet started');
        UserInfo storage user = userInfo[_user];
        uint256 accBlendPerShare = liquidityMining.accBlendPerShare;
        uint256 lpSupply = liquidityMining.lpToken.balanceOf(address(this));
        if (block.number > liquidityMining.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = block.number.sub(liquidityMining.lastRewardBlock);
            uint256 blendReward = multiplier.mul(blendPerBlock);
            accBlendPerShare = liquidityMining.accBlendPerShare.add(blendReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accBlendPerShare).div(1e12).sub(user.rewardDebt).add(user.pendingRewards);
    }

    function updatePool() internal {
        require(liquidityMining.lastRewardBlock > 0 && block.number >= liquidityMining.lastRewardBlock, 'Mining not yet started');
        if (block.number <= liquidityMining.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = liquidityMining.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            liquidityMining.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number.sub(liquidityMining.lastRewardBlock);
        uint256 blendReward = multiplier.mul(blendPerBlock);
        liquidityMining.accBlendPerShare = liquidityMining.accBlendPerShare.add(blendReward.mul(1e12).div(lpSupply));
        liquidityMining.lastRewardBlock = block.number;
    }

    function deposit(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                user.pendingRewards = user.pendingRewards.add(pending);
            }
        }
        if (amount > 0) {
            liquidityMining.lpToken.safeTransferFrom(address(msg.sender), address(this), amount);
            user.amount = user.amount.add(amount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12);
        emit Deposit(msg.sender, amount);
    }

    function withdraw(uint256 amount) external {
        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= amount, "Withdrawing more than you have!");
        updatePool();
        uint256 pending = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
        }
        if (amount > 0) {
            user.amount = user.amount.sub(amount);
            liquidityMining.lpToken.safeTransfer(address(msg.sender), amount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12);
        emit Withdraw(msg.sender, amount);
    }

    function claim() external {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        uint256 pending = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0 || user.pendingRewards > 0) {
            user.pendingRewards = user.pendingRewards.add(pending);
            uint256 claimedAmount = safeBlendTransfer(msg.sender, user.pendingRewards);
            emit Claim(msg.sender, claimedAmount);
            user.pendingRewards = user.pendingRewards.sub(claimedAmount);
        }
        user.rewardDebt = user.amount.mul(liquidityMining.accBlendPerShare).div(1e12);
    }

    function safeBlendTransfer(address to, uint256 amount) internal returns (uint256) {
        uint256 blendBalance = blend.balanceOf(address(this));
        if (amount > blendBalance) {
            blend.safeTransfer(to, blendBalance);
            return blendBalance;
        } else {
            blend.safeTransfer(to, amount);
            return amount;
        }
    }
    
    function setBlendPerBlock(uint256 _blendPerBlock) external onlyOwner {
        require(_blendPerBlock > 0, "BLEND per block should be greater than 0!");
        blendPerBlock = _blendPerBlock;
    }
}
