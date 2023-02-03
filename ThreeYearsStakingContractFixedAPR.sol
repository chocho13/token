// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @author  Fred DA ROS
 * @title   ThreeYearsStakingContractFixedAPR
 * @notice  Lock tokens for 3 years generating claimable rewards depending configured APR 
 */
contract ThreeYearsStakingContractFixedAPR is Ownable, ReentrancyGuard {

    address public constant STAKING_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);

    uint public constant MAX_SUPPLY = 500 * 1e6 * 1e18; // 500M
    uint public constant STAKING_DURATION = 1095 days; // 3 years - 1095day
    uint public constant APR = 10; // 10%
    uint public constant MINIMUM_AMOUNT = 500 * 1e18; // 500
    uint private constant SECONDS_IN_YEAR = 60 * 60 * 24 * 365;

    uint public stakesCount;
    uint public totalSupply; // Doesn't decrease on unstake
    uint public totalStaked; // Decreases on unstake
    bool public stakingAllowed;

    mapping(address => uint[]) private userStakeIds;
    mapping(uint => address) public stakingUser;
    mapping(uint => uint) public stakingAmount;
    mapping(uint => uint) public stakingEndDate;
    mapping(uint => uint) public stakingLastClaim;
    mapping(address => bool) private stakerAddressList;

    struct Stake {
        uint id;
        uint amount;
        uint endDate;
        uint lastClaim;
    }

    struct Status {
        bool stakingAllowed;
        uint stakesCount;
        uint totalSupply;
    }

    constructor() {
        totalSupply = 0;
        stakingAllowed = false; // TODO false
        stakesCount = 0;
    }

    event Staked(uint _amount, uint _totalSupply);
    event ReStaked(uint _amount);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event Withdrawed(uint _withdrawed);
    event StakingAllowed(bool _allow);
    event UpdatedStaker(address _staker, bool _allowed);
    event LastClaim(address _staker, uint _lastClaim);

    /**
     * @dev  function check if requirements to stake are ok
     * @param   _amount  amount to stake
     */
    function stakeRequirements(uint _amount) internal view {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient stake amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(userStakeIds[msg.sender].length < 100, "User stakings limit exceeded");
    }
    
    /**
     * @dev     enable or disable staking
     * @param   _allow  true to enable, false to disable
     */
    function allowStaking(bool _allow) external onlyOwner {
        stakingAllowed = _allow;
        emit StakingAllowed(_allow);
    }

    /**
     * @dev     external function to stake stake
     * @param   _amount  amount to stake
     */
    function stake(uint _amount) external {
        stakeRequirements(_amount);
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        _stake(_amount);
    }

    /**
     * @dev     recompound unclaimed rewards, it create a new stake
     */
    function recompound() external {
        uint _amount = getClaimableRewards(msg.sender);
        stakeRequirements(_amount);
        require(STAKING_TOKEN.balanceOf(address(this)) > _amount + totalStaked, "Insuficient contract balance");
        _updateLastClaim();
        _stake(_amount);
        emit ReStaked(_amount);
    }

    /**
     * @dev     claim claimable rewards
     */
    function claim() external nonReentrant {
        uint toClaim = getClaimableRewards(msg.sender);
        require(toClaim > 0, "Nothing to claim");
        require(STAKING_TOKEN.balanceOf(address(this)) > toClaim + totalStaked, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender, toClaim), "Transfer failed");
        _updateLastClaim();
        emit Claimed(toClaim);
    }

    /**
     * @dev     withdraw available tokens (balance minus totalStaked) from the contract
     * @param   amount  amount to withdraw
     */
    function withdraw(uint amount) external onlyOwner nonReentrant {
        require(amount > 0, "Nothing to withdraw");
        require(STAKING_TOKEN.balanceOf(address(this)) > amount + totalStaked, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender, amount), "Transfer failed");
        emit Withdrawed(amount);
    }

    /**
     * @dev     get withdrawable amount (balance minus totalStaked)
     */
    function getWithdrawableAmount() external view returns(uint) {
        return STAKING_TOKEN.balanceOf(address(this)) - totalStaked;
    }

    /**
     * @dev     unstake unlocked stakings
     */
    function unstake() external nonReentrant returns(uint) {
        uint toUnstake = 0;
        uint i = 0;
        uint stakeId;
        uint toClaim = getClaimableRewards(msg.sender);
        while (i < userStakeIds[msg.sender].length) {
            stakeId = userStakeIds[msg.sender][i];
            if (stakingEndDate[stakeId] < block.timestamp) {
                toUnstake += stakingAmount[stakeId];
                stakingAmount[stakeId] = 0;
                userStakeIds[msg.sender][i] = userStakeIds[msg.sender][userStakeIds[msg.sender].length - 1];
                userStakeIds[msg.sender].pop();
            } else {
                i++;
            }
        }
        require(toUnstake > 0, "Nothing to unstake"); 
        require(STAKING_TOKEN.balanceOf(address(this)) > toUnstake + toClaim, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender, toUnstake + toClaim), "Transfer failed");
        totalStaked -= toUnstake;
        _updateLastClaim();
        emit Unstaked(toUnstake);
        emit Claimed(toClaim);
        return toUnstake + toClaim;
    }

    /**
     * @dev     get a list of stake ids of a user
     * @param   _user  address of the user
     * @return  uint[]  list of stake ids
     */
    function getUserStakesIds(address _user) external view returns (uint[] memory) {
        return userStakeIds[_user];
    }

    /**
     * @dev     return stakes details of the message sender call
     * @return  Stake[]  list of stakes details
     */
    function getUserStakes() external view returns (Stake[] memory) {
        Stake[] memory stakes = new Stake[](userStakeIds[msg.sender].length);
        uint stakeId;
        for(uint i; i < userStakeIds[msg.sender].length; i++) {
            stakeId = userStakeIds[msg.sender][i];
            stakes[i] = Stake(stakeId, stakingAmount[stakeId], stakingEndDate[stakeId], stakingLastClaim[stakeId]);
        }
        return stakes;
    }

    /**
     * @dev     get contract details
     * @return  Status  contract status details
     */
    function getStatus() external view returns (Status memory) {
        return Status(stakingAllowed,stakesCount,totalSupply);
    }

    /**
     * @dev     get claimable rewards
     * @param   _user  address of the user
     * @return  uint  amount claimable
     */
    function getClaimableRewards(address _user) public view returns (uint) {
        uint reward = 0;
        uint stakeId;
        uint lastClaim;
        uint until;
        for (uint i = 0; i < userStakeIds[_user].length; i++) {
            stakeId = userStakeIds[_user][i];
            lastClaim = stakingLastClaim[stakeId];
            until = stakingEndDate[stakeId] < block.timestamp ? stakingEndDate[stakeId] : block.timestamp;
            reward += until > lastClaim ? stakingAmount[stakeId] * (until - lastClaim) * APR / 100 / SECONDS_IN_YEAR : 0;
        }
        return reward;
    }

    /**
     * @dev     update last claim of a user
     */
    function _updateLastClaim() internal {
        for (uint i = 0; i < userStakeIds[msg.sender].length; i++) {
            stakingLastClaim[userStakeIds[msg.sender][i]] = block.timestamp;
        }
        emit LastClaim(msg.sender,block.timestamp);
    }

    /**
     * @dev     internal stake
     * @param   _amount  amount to stake
     */
    function _stake(uint _amount) internal nonReentrant {
        stakingUser[stakesCount] = msg.sender;
        stakingAmount[stakesCount] = _amount;
        stakingEndDate[stakesCount] = block.timestamp + STAKING_DURATION;
        stakingLastClaim[stakesCount] = block.timestamp;
        userStakeIds[msg.sender].push(stakesCount);
        totalSupply += _amount;
        totalStaked += _amount;
        stakesCount += 1;
        emit Staked(_amount, totalSupply);
    }

}
