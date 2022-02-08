// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OneYearStakingContract is Ownable {

    IERC20 internal constant stakingToken = IERC20(stakingTokenAddress);

    struct Stake {
        address user;
        uint amount;
        uint sinceBlock;
        uint lastUpdate;
        uint untilBlock;
        uint unclaimed;
    }

    Stake[] stakes;
    
    uint public totalSupply;
    uint public constant maxSupply = 80 * 1e6 * 1e18;
    uint public constant minimumAmount = 500 * 1e18;
    uint public constant rewardPerBlock = 0.6808 * 1e18;
    bool public stakingEnabled;

    address public constant stakingTokenAddress = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    
    constructor() {
        totalSupply = 0;
        stakingEnabled = true;
    }

    function enableStaking(bool _enable) external onlyOwner returns (bool enabled) {
        return stakingEnabled = _enable;
    }

    function stake(uint _amount) external updatePool returns (bool staked) {
        require(stakingEnabled, "Staking is not enabled");
        require(_amount >= minimumAmount, "Insuficient amount");
        require(totalSupply + _amount <= maxSupply, "Pool capacity exceeded");
        require(_amount < stakingToken.balanceOf(msg.sender), "Insuficient balance");
        require(stakingToken.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        stakes.push(Stake(msg.sender, _amount, block.timestamp, block.timestamp, block.timestamp + 365 days,0));
        totalSupply += _amount;
        return true;
    }

    function claim() external updatePool returns(uint) {
        uint claimed = 0;
        for(uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == msg.sender) {
                if (stakes[i].unclaimed > 0) {
                    require(stakingToken.balanceOf(address(this)) > stakes[i].unclaimed, "Insuficient contract balance");
                    require(stakingToken.transfer(msg.sender,stakes[i].unclaimed), "Transfer failed");
                }
                claimed += stakes[i].unclaimed;
                stakes[i].unclaimed = 0;
            }
        }
        return claimed;
    }

    modifier updatePool() {
        for(uint i = 0; i < stakes.length; i++) {
            if(stakes[i].untilBlock >= block.timestamp) {
                stakes[i].unclaimed += stakes[i].amount / totalSupply * (block.timestamp - stakes[i].lastUpdate) * rewardPerBlock;
                stakes[i].lastUpdate = block.timestamp;
            }
        }
        _;
    }

    function unstake() external updatePool {
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
        require(stakingToken.balanceOf(address(this)) > amount, "Insuficient contract balance");
        require(stakingToken.transfer(msg.sender,amount), "Transfer failed");
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
}
