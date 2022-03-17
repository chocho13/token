// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OneYearStakingContract is Ownable, ReentrancyGuard {

    mapping(address => uint[]) public ownerStakeIds;

    mapping(uint => address) public stakingUser;
    mapping(uint => uint) public stakingAmount;
    mapping(uint => uint) public stakingEndDate;
    mapping(uint => uint) public stakingUnclaimed;

    uint public stakesCount;

    uint public totalSupply;
    uint public totalStaked;
    bool public stakingAllowed;
    uint public lastUpdate;
    uint public maxApr;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 1 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.000008 * 1e18;
    uint public constant SECONDS_IN_YEAR = 31536000;


    address public constant STAKING_TOKEN_ADDRESS = 0x3b8f655397045f63AD172D009cb7EF35aF992224; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);
    constructor() {
        lastUpdate = block.timestamp;
        totalSupply = 0;
        stakingAllowed = true;
        maxApr = 500; // 500%
        stakesCount = 0;
    }

    event Stacked(uint _amount,uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event Updated(uint _lastupdate);
    event AdjustMaxApr(uint _maxApr);


    function testStake(uint _loop) external {
        for(uint i = 0; i < _loop; i++) {
            stake(i * 1e18);
        }
    }

    function adjustMaxApr(uint _maxApr) external onlyOwner returns (uint newMaxApr) {
        emit AdjustMaxApr(_maxApr);
        return maxApr = _maxApr;
    }

    function allowStaking(bool _allow) external onlyOwner returns (bool allowed) {
        emit StakingAllowed(_allow);
        return stakingAllowed = _allow;
    }
    function forceUpdatePool() external updatePool nonReentrant returns (bool updated) {
        return true;
    }

    function stake(uint _amount) public {
        // require(stakingAllowed, "Staking is not enabled");
        // require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        // require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        // require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        // require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakingUser[stakesCount] = msg.sender;
        stakingUnclaimed[stakesCount] = _amount;
        stakingEndDate[stakesCount] = block.timestamp + 365 days;
        stakingUnclaimed[stakesCount] = 0;
        ownerStakeIds[msg.sender].push(stakesCount);
        totalSupply += _amount;
        totalStaked += _amount;
        stakesCount += 1;
        // emit Stacked(_amount,totalSupply);
        // return true;
    }

    function claim() external updatePool nonReentrant returns(uint) {
        uint claimed = 0;
        uint j;
        for(uint i = 0; i < ownerStakeIds[msg.sender].length; i++) {
            j = ownerStakeIds[msg.sender][i];
            if (stakingUnclaimed[j] > 0) {
                require(STAKING_TOKEN.balanceOf(address(this)) - totalStaked > stakingUnclaimed[j], "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,stakingUnclaimed[j]), "Transfer failed");
            }
            claimed += stakingUnclaimed[j];
            stakingUnclaimed[j] = 0;
        }
        emit Claimed(claimed);
        return claimed;
    }

    function unstake() external updatePool nonReentrant returns(uint) {
        uint stakedAmount = 0;
        uint unclaimedAmount = 0;
        uint amount = 0;
        uint i = 0;
        uint stakeId;
        while(i < ownerStakeIds[msg.sender].length) {
            stakeId = ownerStakeIds[msg.sender][i];
            if (stakingEndDate[stakeId] < block.timestamp) {
                amount = stakingAmount[stakeId] + stakingUnclaimed[stakeId];
                stakedAmount += stakingAmount[stakeId];
                unclaimedAmount += stakingUnclaimed[stakeId];
                require(STAKING_TOKEN.balanceOf(address(this)) > amount, "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,amount), "Transfer failed");
                totalStaked -= stakingAmount[stakeId];
                stakingAmount[stakeId] = 0;

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
        uint maxRewardPerBlock = totalSupply * maxApr / SECONDS_IN_YEAR / 100 * 1e18;
        uint rewardPerBlock;
        if (REWARD_PER_BLOCK > maxRewardPerBlock) {
            rewardPerBlock = maxRewardPerBlock / totalSupply;
        } else {
            rewardPerBlock = REWARD_PER_BLOCK / totalSupply;
        }
        for(uint i = 0; i < stakesCount; i++) {
            if(stakingEndDate[i] >= block.timestamp) {
                stakingUnclaimed[i] += stakingAmount[i] * (block.timestamp - lastUpdate) * rewardPerBlock;
            } else if (lastUpdate < stakingEndDate[i]) {
                stakingUnclaimed[i] += stakingAmount[i] * (stakingEndDate[i] - lastUpdate) * rewardPerBlock;
            }
        }
        lastUpdate = block.timestamp;
        emit Updated(lastUpdate);
        _;
    }
}
