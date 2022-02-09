// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OneYearStakingContract is Ownable, ReentrancyGuard {

    struct Stake {
        address user;
        uint amount;
        uint untilBlock;
        uint unclaimed;
    }

    Stake[] public stakes;
    mapping(address => uint[]) private ownerStakIds;

    uint public totalSupply;
    bool public stakingAllowed;
    uint public lastUpdate;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 500 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.6808 * 1e18;

    // address public constant STAKING_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    address public constant STAKING_TOKEN_ADDRESS = 0xDecB06cCa15031927Adb8B2e8773145646CFB564; // testnet address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);
    
    constructor() {
        lastUpdate = block.timestamp;
        totalSupply = 0;
        stakingAllowed = true;
    }

    event Stacked(uint _amount,uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event Allowed(bool _allow);
    event Updated(uint _lastupdate);

    function allowStaking(bool _allow) external onlyOwner returns (bool allowed) {
        return stakingAllowed = _allow;
    }
    function forceUpdatePool() external updatePool nonReentrant returns (bool updated) {
        return true;
    }

    function stake(uint _amount) external updatePool nonReentrant returns (bool staked) {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount < STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakes.push(Stake(msg.sender, _amount, block.timestamp + 10 minutes,0));
        ownerStakIds[msg.sender].push(stakes.length-1);
        totalSupply += _amount;
        emit Stacked(_amount,totalSupply);
        return true;
    }

    function claim() external updatePool nonReentrant returns(uint amount) {
        uint claimed = 0;
        uint j;
        for(uint i = 0; i < ownerStakIds[msg.sender].length; i++) {
            j = ownerStakIds[msg.sender][i];
            if (stakes[j].unclaimed > 0) {
                require(STAKING_TOKEN.balanceOf(address(this)) > stakes[j].unclaimed, "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,stakes[j].unclaimed), "Transfer failed");
            }
            claimed += stakes[j].unclaimed;
            stakes[j].unclaimed = 0;
        }
        emit Claimed(claimed);
        return claimed;
    }

    function unstake() external updatePool nonReentrant returns(uint unstaked) {
        uint amount = 0;
        uint i = 0;
        uint stakeId;
        while(i < ownerStakIds[msg.sender].length) {
            stakeId = ownerStakIds[msg.sender][i];
            if (stakes[stakeId].untilBlock < block.timestamp) {
                amount = stakes[stakeId].amount + stakes[i].unclaimed;
                require(STAKING_TOKEN.balanceOf(address(this)) > amount, "Insuficient contract balance");
                require(STAKING_TOKEN.transfer(msg.sender,amount), "Transfer failed");
                stakes[stakeId] = stakes[stakes.length -1];
                for(uint k = 0; k < ownerStakIds[stakes[stakeId].user].length; k++) {
                    if (ownerStakIds[stakes[stakeId].user][k] == stakes.length -1) {
                        ownerStakIds[stakes[stakeId].user][k] = stakeId;
                    }
                }
                stakes.pop();
                ownerStakIds[msg.sender][i] = ownerStakIds[msg.sender][ownerStakIds[msg.sender].length -1];
                ownerStakIds[msg.sender].pop();
            } else {
                i++;
            }
        }
        require(amount > 0, "Nothing to unstake");
        emit Unstaked(amount);
        return amount;
    }

    function getUserStaksIds(address _user) external view returns (uint[] memory) {
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
            if(stakes[i].untilBlock >= block.timestamp) {
                stakes[i].unclaimed += stakes[i].amount * (block.timestamp - lastUpdate) * REWARD_PER_BLOCK / totalSupply;
            } else if (lastUpdate < stakes[i].untilBlock) {
                stakes[i].unclaimed += stakes[i].amount * (stakes[i].untilBlock - lastUpdate) * REWARD_PER_BLOCK / totalSupply;
            }
        }
        lastUpdate = block.timestamp;
        emit Updated(lastUpdate);
        _;
    }
}
