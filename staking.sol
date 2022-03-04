// SPDX-License-Identifier: MIT
pragma solidity 0.8.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OneYearStakingContract is Ownable, ReentrancyGuard {

    struct Stake {
        address user;
        uint amount;
        uint stakingEndDate;
        uint unclaimed;
    }

    Stake[] public stakes;
    mapping(address => uint[]) private ownerStakeIds;

    uint public totalSupply;
    uint public totalStaked;
    bool public stakingAllowed;
    uint public lastUpdate;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 500 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.6808 * 1e18;

    address public constant STAKING_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);
    
    constructor() {
        lastUpdate = block.timestamp;
        totalSupply = 0;
        stakingAllowed = true;
    }

    event Stacked(uint _amount,uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event Updated(uint _lastupdate);

    function allowStaking(bool _allow) external onlyOwner returns (bool allowed) {
        emit StakingAllowed(_allow);
        return stakingAllowed = _allow;
    }
    function forceUpdatePool() external updatePool nonReentrant returns (bool updated) {
        return true;
    }

    function stake(uint _amount) external updatePool nonReentrant returns (bool staked) {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakes.push(Stake(msg.sender, _amount, block.timestamp + 365 days,0));
        ownerStakeIds[msg.sender].push(stakes.length-1);
        totalSupply += _amount;
        totalStaked += _amount;
        emit Stacked(_amount,totalSupply);
        return true;
    }

    function claim() external updatePool nonReentrant returns(uint amount) {
        uint claimed = 0;
        uint j;
        for(uint i = 0; i < ownerStakeIds[msg.sender].length; i++) {
            j = ownerStakeIds[msg.sender][i];
            if (stakes[j].unclaimed > 0) {
                require(STAKING_TOKEN.balanceOf(address(this)) - totalStaked > stakes[j].unclaimed, "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,stakes[j].unclaimed), "Transfer failed");
            }
            claimed += stakes[j].unclaimed;
            stakes[j].unclaimed = 0;
        }
        emit Claimed(claimed);
        return claimed;
    }

    function unstake() external updatePool nonReentrant returns(uint unstaked) {
        uint stakedAmount = 0;
        uint unclaimedAmount = 0;
        uint amount = 0;
        uint i = 0;
        uint stakeId;
        while(i < ownerStakeIds[msg.sender].length) {
            stakeId = ownerStakeIds[msg.sender][i];
            if (stakes[stakeId].stakingEndDate < block.timestamp) {
                amount = stakes[stakeId].amount + stakes[stakeId].unclaimed;
                stakedAmount += stakes[stakeId].amount;
                unclaimedAmount += stakes[stakeId].unclaimed;
                require(STAKING_TOKEN.balanceOf(address(this)) > amount, "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,amount), "Transfer failed");
                totalStaked -= stakes[stakeId].amount;
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
        uint j = 0;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == _user) {
                j++;
            }
        }
        uint[] memory ids = new uint[](j);
        j = 0;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == _user) {
                ids[j] = i;
                j++;
            }
        }
        return ids;
    }

    modifier updatePool() {
        for(uint i = 0; i < stakes.length; i++) {
            if(stakes[i].stakingEndDate >= block.timestamp) {
                stakes[i].unclaimed += stakes[i].amount * (block.timestamp - lastUpdate) * REWARD_PER_BLOCK / totalSupply;
            } else if (lastUpdate < stakes[i].stakingEndDate) {
                stakes[i].unclaimed += stakes[i].amount * (stakes[i].stakingEndDate - lastUpdate) * REWARD_PER_BLOCK / totalSupply;
            }
        }
        lastUpdate = block.timestamp;
        emit Updated(lastUpdate);
        _;
    }
}
