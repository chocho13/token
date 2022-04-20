// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract farmingContract is Ownable, ReentrancyGuard {

    mapping(address => uint) public farmingAmount;
    mapping(address => uint) public farmingLastUpdate;
    mapping(address => uint) public farmingUnclaimedRewards;

    uint public totalSupply;
    bool public farmingAllowed;

    uint public constant MIN_AMOUNT = 1 * 1e18;
    uint public constant SECONDS_IN_YEAR = 31536000;
    uint public immutable APR;


    address public constant REWARD_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    address public constant FARMING_TOKEN_ADDRESS = 0x469E0D351B868cb397967E57a00dc7DE082542A3; // LP token address
    IERC20 private constant FARMING_TOKEN = IERC20(FARMING_TOKEN_ADDRESS);
    IERC20 private constant REWARD_TOKEN = IERC20(REWARD_TOKEN_ADDRESS);

    constructor(uint _APR) {
        APR = _APR;
        farmingAllowed = true; // TODO => false
    }

    event Farmed(uint _totalSupply);
    event Unfarmed(uint _amount);
    event Claimed(uint _claimed);
    event FarmingAllowed(bool _allow);

    function allowFarming(bool _allow) external onlyOwner {
        farmingAllowed = _allow;
        emit FarmingAllowed(_allow);
    }

    function farm(uint _amount) external nonReentrant {
        require(farmingAllowed, "Farming is not enabled");
        require(_amount > MIN_AMOUNT, "Insuficient amount");
        require(_amount <= FARMING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(FARMING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        if (farmingAmount[msg.sender] > 0) {
            farmingUnclaimedRewards[msg.sender] += _claimableRewardsSinceLastUpdate();
        }
        farmingAmount[msg.sender] += _amount;
        farmingLastUpdate[msg.sender] = block.timestamp;
        totalSupply += _amount;
        emit Farmed(totalSupply);
    }

    function _claimableRewardsSinceLastUpdate() internal view returns (uint) {
        return (farmingAmount[msg.sender] * (block.timestamp - farmingLastUpdate[msg.sender]) * APR / 100 / SECONDS_IN_YEAR);
    }

    function getClaimableRewards() public view returns (uint) {
        return (farmingUnclaimedRewards[msg.sender] + _claimableRewardsSinceLastUpdate());
    }

    function claim() public nonReentrant {
        uint toClaim = getClaimableRewards();
        require(toClaim > 0, "Nothing to claim");
        _claim(toClaim);
    }

    function _claim(uint _toClaim) internal {
        require(REWARD_TOKEN.balanceOf(address(this)) > _toClaim, "Insuficient contract balance");
        require(REWARD_TOKEN.transfer(msg.sender,_toClaim), "Transfer failed");
        farmingLastUpdate[msg.sender] = block.timestamp;
        farmingUnclaimedRewards[msg.sender] = 0;
        emit Claimed(_toClaim);
    }

    function unfarm() external nonReentrant {
        uint toUnfarm = farmingAmount[msg.sender];
        require(toUnfarm > 0, "Nothing to unfarm"); 
        uint toClaim = getClaimableRewards();
        if (toClaim > 0) {
            _claim(toClaim);
        }
        require(FARMING_TOKEN.balanceOf(address(this)) > toUnfarm, "Insuficient contract balance");
        require(FARMING_TOKEN.transfer(msg.sender, toUnfarm), "Transfer failed");
        totalSupply -= toUnfarm; 
        emit Unfarmed(toUnfarm);
    }

}
