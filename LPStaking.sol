// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LPStakingContract is Ownable, ReentrancyGuard {

    struct Stake {
        address user;
        uint amount;
        uint stakingEndDate;
        uint unclaimed;
    }

    Stake[] public stakes;
    mapping(address => uint[]) private ownerStakeIds;

    uint public totalSupply;
    bool public stakingAllowed;
    uint public lastUpdate;
    uint public rewardPerBlock;

    uint public constant MINIMUM_AMOUNT = 500 * 1e18;

    address public constant REWARD_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    address public constant STAKING_TOKEN_ADDRESS = 0x469E0D351B868cb397967E57a00dc7DE082542A3; // LP token address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);
    IERC20 private constant REWARD_TOKEN = IERC20(REWARD_TOKEN_ADDRESS);
    
    constructor() {
        lastUpdate = block.timestamp;
        totalSupply = 0;
        stakingAllowed = true;
        rewardPerBlock = 0.6808 * 1e18;
    }

    event Stacked(uint _amount,uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event Updated(uint _lastupdate);
    event AdjustRewardPerBlock(uint _rewardPerBlock);

    function allowStaking(bool _allow) external onlyOwner returns (bool allowed) {
        emit StakingAllowed(_allow);
        return stakingAllowed = _allow;
    }

    function adjustRewardPerBlock(uint _rewardPerBlock) external onlyOwner returns (uint newRewardPerBlock) {
        emit AdjustRewardPerBlock(_rewardPerBlock);
        return rewardPerBlock = _rewardPerBlock;
    }

    function forceUpdatePool() external updatePool nonReentrant returns (bool updated) {
        return true;
    }

    function stake(uint _amount) external updatePool nonReentrant returns (bool staked) {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakes.push(Stake(msg.sender, _amount, block.timestamp + 365 days,0));
        ownerStakeIds[msg.sender].push(stakes.length-1);
        totalSupply += _amount;
        emit Stacked(_amount,totalSupply);
        return true;
    }

    function claim() external updatePool nonReentrant returns(uint amount) {
        uint claimed = 0;
        uint j;
        for(uint i = 0; i < ownerStakeIds[msg.sender].length; i++) {
            j = ownerStakeIds[msg.sender][i];
            if (stakes[j].unclaimed > 0) {
                require(REWARD_TOKEN.balanceOf(address(this)) > stakes[j].unclaimed, "Insuficient contract balance");
                require(REWARD_TOKEN.transfer(msg.sender,stakes[j].unclaimed), "Transfer failed");
            }
            claimed += stakes[j].unclaimed;
            stakes[j].unclaimed = 0;
        }
        emit Claimed(claimed);
        return claimed;
    }

    function unstake() external updatePool nonReentrant returns(uint totalReceived) {
        uint i = 0;
        uint stakeId;
        uint stakedAmount = 0;
        uint unclaimedAmount = 0;
        while(i < ownerStakeIds[msg.sender].length) {
            stakeId = ownerStakeIds[msg.sender][i];
            if (stakes[stakeId].stakingEndDate < block.timestamp) {
                stakedAmount += stakes[stakeId].amount;
                unclaimedAmount += stakes[stakeId].unclaimed;
                require(STAKING_TOKEN.balanceOf(address(this)) > stakes[stakeId].amount, "Insuficient staking contract balance");
                require(REWARD_TOKEN.balanceOf(address(this)) > stakes[stakeId].unclaimed, "Insuficient reward contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,stakes[stakeId].amount), "Staking transfer failed");
                require(REWARD_TOKEN.transfer(msg.sender,stakes[stakeId].unclaimed), "Reward transfer failed");
                totalSupply -= stakes[stakeId].amount;
                stakes[stakeId] = stakes[stakes.length -1];
                for(uint k = 0; k < ownerStakeIds[stakes[stakeId].user].length; k++) {
                    if (ownerStakeIds[stakes[stakeId].user][k] == stakes.length -1) {
                        ownerStakeIds[stakes[stakeId].user][k] = stakeId;
                    }
                }
                stakes.pop();
                ownerStakeIds[msg.sender][i] = ownerStakeIds[msg.sender][ownerStakeIds[msg.sender].length -1];
                ownerStakeIds[msg.sender].pop();
            } else {
                i++;
            }
        }
        require(stakedAmount > 0, "Nothing to unstake");
        emit Unstaked(stakedAmount);
        emit Claimed(unclaimedAmount);
        return stakedAmount + unclaimedAmount;
    }

    function getUserStakesIds(address _user) external view returns (uint[] memory) {
        return ownerStakeIds[_user];
    }

    modifier updatePool() {
        for(uint i = 0; i < stakes.length; i++) {
            if(stakes[i].stakingEndDate >= block.timestamp) {
                stakes[i].unclaimed += stakes[i].amount * (block.timestamp - lastUpdate) * rewardPerBlock / totalSupply;
            } else if (lastUpdate < stakes[i].stakingEndDate) {
                stakes[i].unclaimed += stakes[i].amount * (stakes[i].stakingEndDate - lastUpdate) * rewardPerBlock / totalSupply;
            }
        }
        lastUpdate = block.timestamp;
        emit Updated(lastUpdate);
        _;
    }
}
