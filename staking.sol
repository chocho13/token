// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract OneYearStakingContract is Ownable, ReentrancyGuard {

    struct Stake {
        address user;
        uint amount;
        uint sinceBlock;
        uint untilBlock;
        uint lastUpdate;
        uint unclaimed;
    }

    Stake[] private stakes;
    
    uint public totalSupply;
    bool public stakingEnabled;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 500 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.6808 * 1e18;

    address public constant STAKING_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    IERC20 internal constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);
    
    constructor() {
        totalSupply = 0;
        stakingEnabled = true;
    }

    function enableStaking(bool _enable) external onlyOwner returns (bool enabled) {
        return stakingEnabled = _enable;
    }

    function stake(uint _amount) external updatePool nonReentrant returns (bool staked) {
        require(stakingEnabled, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount < STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakes.push(Stake(msg.sender, _amount, block.timestamp, block.timestamp, block.timestamp + 365 days,0));
        totalSupply += _amount;
        return true;
    }

    function claim() external updatePool nonReentrant returns(uint) {
        uint claimed = 0;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == msg.sender) {
                if (stakes[i].unclaimed > 0) {
                    require(STAKING_TOKEN.balanceOf(address(this)) > stakes[i].unclaimed, "Insuficient contract balance");
                    require(STAKING_TOKEN.transfer(msg.sender,stakes[i].unclaimed), "Transfer failed");
                }
                claimed += stakes[i].unclaimed;
                stakes[i].unclaimed = 0;
            }
        }
        return claimed;
    }

    function unstake() external updatePool nonReentrant {
        uint[] memory unstakeIds;
        uint j = 0;
        uint amount;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].untilBlock < block.timestamp && stakes[i].user == msg.sender) {
                unstakeIds[j] = i;
                j++;
                amount += stakes[i].amount;
            }
        }
        require(STAKING_TOKEN.balanceOf(address(this)) > amount, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender,amount), "Transfer failed");
        for(uint i = 0; i < unstakeIds.length; i++) {
            stakes[unstakeIds[i]] = stakes[stakes.length -1];
            stakes.pop();
        }

    }

    function viewUserStaks(address _user) external view returns (Stake[] memory) {
        Stake[] memory currents;
        uint j=0;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == _user) {
                currents[j] = stakes[i];
                j++;
            }
        }
        return currents;
    }

    modifier updatePool() {
        for(uint i = 0; i < stakes.length; i++) {
            if(stakes[i].untilBlock >= block.timestamp) {
                stakes[i].unclaimed += stakes[i].amount / totalSupply * (block.timestamp - stakes[i].lastUpdate) * REWARD_PER_BLOCK;
                stakes[i].lastUpdate = block.timestamp;
            }
        }
        _;
    }
}
