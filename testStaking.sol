// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OneYearStakingContract is Ownable, ReentrancyGuard {

    struct Struct {
        uint timestamp;
        uint rewardPerBlock;
    }

    Struct[] public rewardPerBlockHistory;

    mapping(address => uint[]) public ownerStakeIds;
    mapping(uint => address) public stakingUser;
    mapping(uint => uint) public stakingAmount;
    mapping(uint => uint) public stakingEndDate;
    mapping(uint => uint) public stakingLastClaim;

    uint public stakesCount;
    uint public totalSupply;
    uint public totalStaked;
    bool public stakingAllowed;
    uint public lastUpdatePoolSizePercent;
    uint public maxApr;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 1 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.000008 * 1e18;
    uint public constant SECONDS_IN_YEAR = 31536000;
    uint public constant MIN_APR = 25;

    address public constant STAKING_TOKEN_ADDRESS = 0xd9145CCE52D386f254917e481eB44e9943F39138; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);

    constructor() {
        totalSupply = 0;
        lastUpdatePoolSizePercent = 0;
        stakingAllowed = true;
        maxApr = 500; // 500%
        stakesCount = 0;
    }

    event Stacked(uint _amount,uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event RewardPerBlockUpdatedTimestamp(uint _lastupdate);
    event AdjustMaxApr(uint _maxApr);
    event plop(uint);

    function testStake(uint _loop) external {
        emit plop(STAKING_TOKEN.balanceOf(msg.sender));
        for(uint i = 0; i < _loop; i++) {
            _stake((500+i) * 1e18,msg.sender);
        }
    }

    function adjustMaxApr(uint _maxApr) external onlyOwner {
        maxApr = _maxApr;
        emit AdjustMaxApr(_maxApr);
    }

    function updateRewardPerBlock() external onlyOwner {
        _updateRewardPerBlock();
    }
    function allowStaking(bool _allow) external onlyOwner {
        stakingAllowed = _allow;
        emit StakingAllowed(_allow);
    }

    function stake(uint _amount) external {
        require(_stake(_amount,msg.sender),"staking failed");
    }

    function stakForSomeoneElse(uint _amount,address _user) external {
        require(_stake(_amount,_user),"staking failed");
    }

    function claim() external nonReentrant {
        uint toClaim = _claimableRewards(msg.sender);
        require(STAKING_TOKEN.balanceOf(address(this)) > toClaim, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender,toClaim), "Transfer failed");
        emit Claimed(toClaim);
    }

    function unstake() external nonReentrant returns(uint) {
        uint toUnstake = 0;
        uint i = 0;
        uint stakeId;
        while(i < ownerStakeIds[msg.sender].length) {
            stakeId = ownerStakeIds[msg.sender][i];
            if (stakingEndDate[stakeId] < block.timestamp) {
                toUnstake += stakingAmount[stakeId];
                totalStaked -= stakingAmount[stakeId];
                stakingAmount[stakeId] = 0;
                ownerStakeIds[msg.sender][i] = ownerStakeIds[msg.sender][ownerStakeIds[msg.sender].length -1];
                ownerStakeIds[msg.sender].pop();
            } else {
                i++;
            }
        }
        require(toUnstake >0, "Nothing to unstake"); 
        uint toClaim = _claimableRewards(msg.sender);
        require(STAKING_TOKEN.balanceOf(address(this)) > toUnstake + toClaim, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender,toUnstake + toClaim), "Transfer failed");
        emit Unstaked(toUnstake);
        emit Claimed(toClaim);
        return toUnstake + toClaim;
    }

    function getUserStakesIds(address _user) external view returns (uint[] memory) {
        return ownerStakeIds[_user];
    }

    function _stake(uint _amount, address _user) internal nonReentrant returns (bool) {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakingUser[stakesCount] = _user;
        stakingEndDate[stakesCount] = block.timestamp + 365 days;
        stakingLastClaim[stakesCount] = block.timestamp;
        ownerStakeIds[_user].push(stakesCount);
        totalSupply += _amount;
        totalStaked += _amount;
        stakesCount += 1;
        uint poolSizePercent = totalSupply * 100 / MAX_SUPPLY;
        if (poolSizePercent < lastUpdatePoolSizePercent + 5) {
            _updateRewardPerBlock;
        }
        emit Stacked(_amount,totalSupply);
        return true;
    }

    function _updateRewardPerBlock() internal {
        uint maxRewardPerBlock = totalSupply * maxApr / SECONDS_IN_YEAR / 100 * 1e18;
        uint minRewardPerBlock = totalSupply * MIN_APR / SECONDS_IN_YEAR / 100 * 1e18;
        uint rewardPerBlock;
        if (REWARD_PER_BLOCK < minRewardPerBlock) {
            rewardPerBlock = minRewardPerBlock / totalSupply;
        } else if (REWARD_PER_BLOCK > maxRewardPerBlock) {
            rewardPerBlock = maxRewardPerBlock / totalSupply;
        } else {
            rewardPerBlock = REWARD_PER_BLOCK / totalSupply;
        }
        rewardPerBlockHistory.push(Struct(block.timestamp,rewardPerBlock));
        emit RewardPerBlockUpdatedTimestamp(block.timestamp);
    }

    function _claimableRewards(address _user) internal returns (uint) {
        uint reward = 0;
        uint stakeId;
        for(uint i = 0; i < ownerStakeIds[_user].length; i++) {
            stakeId = ownerStakeIds[_user][i];
            uint lastClaim = stakingLastClaim[stakeId];
            for(uint j = 0; j < rewardPerBlockHistory.length; j++) {
                if (rewardPerBlockHistory[j].timestamp > lastClaim) {
                    reward += stakingAmount[stakeId] * (rewardPerBlockHistory[j].timestamp - lastClaim) * rewardPerBlockHistory[j].rewardPerBlock;
                    lastClaim = rewardPerBlockHistory[j].timestamp;
                }
            }
            stakingLastClaim[stakeId] = lastClaim;
        }
        return reward;
    }
}
