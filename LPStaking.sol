// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract farmingContract is Ownable, ReentrancyGuard {

    mapping(address => uint) public farmingAmount;
    mapping(address => uint) public farmingLastDepositedDate;
    mapping(address => uint) public farmingLastUpdate;
    mapping(address => uint) public farmingUnclaimedRewards;

    uint public totalSupply;
    bool public farmingAllowed;

    uint public constant MIN_AMOUNT = 1 * 1e18;
    uint public constant SECONDS_IN_YEAR = 365 days;
    uint public immutable APR;

    uint public constant PERFORMANCE_FEE_PERIOD = 72 hours;
    uint public constant WITHDRAW_FEE_PERIOD = 1 weeks;
    uint public constant withdrawFee = 5; // 5%
    uint public constant performanceFee = 5; // 5%

    address public constant REWARD_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    address public constant FARMING_TOKEN_ADDRESS = 0x469E0D351B868cb397967E57a00dc7DE082542A3; // LP token address
    IERC20 private constant FARMING_TOKEN = IERC20(FARMING_TOKEN_ADDRESS);
    IERC20 private constant REWARD_TOKEN = IERC20(REWARD_TOKEN_ADDRESS);

    constructor(uint _APR) {
        APR = _APR;
        farmingAllowed = true; // TODO => false
    }

    event Deposit(uint _totalSupply);
    event Withdraw(uint _amount);
    event Harvest(uint _harvested);
    event FarmingAllowed(bool _allow);

    function allowFarming(bool _allow) external onlyOwner {
        farmingAllowed = _allow;
        emit FarmingAllowed(_allow);
    }

    function deposit(uint _amount) external nonReentrant {
        require(farmingAllowed, "Farming is not enabled");
        require(_amount > MIN_AMOUNT, "Insuficient amount");
        require(_amount <= FARMING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(FARMING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        if (farmingAmount[msg.sender] > 0) {
            farmingUnclaimedRewards[msg.sender] += _harvestableRewardsSinceLastUpdate();
        }
        farmingAmount[msg.sender] += _amount;
        farmingLastDepositedDate[msg.sender] = block.timestamp;
        farmingLastUpdate[msg.sender] = block.timestamp;
        totalSupply += _amount;
        emit Deposit(totalSupply);
    }

    function _harvestableRewardsSinceLastUpdate() internal view returns (uint) {
        return (farmingAmount[msg.sender] * (block.timestamp - farmingLastUpdate[msg.sender]) * APR / 100 / SECONDS_IN_YEAR);
    }

    function getHarvestableRewards() public view returns (uint) {
        if (farmingAmount[msg.sender] == 0) {return 0;}
        uint currentRewards = _harvestableRewardsSinceLastUpdate() + farmingUnclaimedRewards[msg.sender];
        return block.timestamp - farmingLastUpdate[msg.sender] < PERFORMANCE_FEE_PERIOD ? currentRewards - currentRewards * performanceFee / 100 : currentRewards;
    }

    function getPerformanceFeeEndDate() external view returns (uint) {
        return farmingAmount[msg.sender] > 0 ? farmingLastUpdate[msg.sender] + PERFORMANCE_FEE_PERIOD : 0;
    }

    function getWithdrawFeeEndDate() external view returns (uint) {
        return farmingAmount[msg.sender] > 0 ? farmingLastDepositedDate[msg.sender] + PERFORMANCE_FEE_PERIOD : 0;
    }

    function getWithdrawableAmount() public view returns (uint) {
        return block.timestamp - farmingLastDepositedDate[msg.sender] < WITHDRAW_FEE_PERIOD ? farmingAmount[msg.sender] - farmingAmount[msg.sender] * withdrawFee / 100 : farmingAmount[msg.sender];
    }

    function getDepositedAmount() public view returns (uint) {
        return farmingAmount[msg.sender];
    }

    function getLastDepositedDate() public view returns (uint) {
        return farmingLastDepositedDate[msg.sender];
    }

    function getLastUpdateRewardsDate() public view returns (uint) {
        return farmingLastUpdate[msg.sender];
    }

    function harvest() public nonReentrant {
        uint toHarvest = getHarvestableRewards();
        require(toHarvest > 0, "Nothing to claim");
        _harvest(toHarvest);
    }

    function _harvest(uint _toHarvest) internal {
        require(REWARD_TOKEN.balanceOf(address(this)) > _toHarvest, "Insuficient contract balance");
        require(REWARD_TOKEN.transfer(msg.sender,_toHarvest), "Transfer failed");
        farmingLastUpdate[msg.sender] = block.timestamp;
        farmingUnclaimedRewards[msg.sender] = 0;
        emit Harvest(_toHarvest);
    }
    
    function withdraw() external nonReentrant {
        require(farmingAmount[msg.sender] > 0, "Nothing to withdraw"); 
        uint toWithdraw = getWithdrawableAmount();
        uint toHarvest = getHarvestableRewards();
        if (toHarvest > 0) {
            _harvest(toHarvest);
        }
        require(FARMING_TOKEN.balanceOf(address(this)) > toWithdraw, "Insuficient contract balance");
        require(FARMING_TOKEN.transfer(msg.sender, toWithdraw), "Transfer failed");
        totalSupply -= toWithdraw; 
        emit Withdraw(toWithdraw);
    }

}
