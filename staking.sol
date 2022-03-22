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

    mapping(address => uint[]) private userStakeIds;

    mapping(uint => address) public stakingUser;
    mapping(uint => uint) public stakingAmount;
    mapping(uint => uint) public stakingEndDate;
    mapping(uint => uint) public stakingLastClaim;

    uint public stakesCount;
    uint public totalSupply; // Doesn't decrease on unstake
    uint public totalStaked; // Decreases on unstake
    bool public stakingAllowed;
    uint public lastUpdatePoolSizePercent;
    uint public maxApr;
    uint public percentAutoUpdatePool;

    uint public constant MAX_SUPPLY = 80 * 1e6 * 1e18;
    uint public constant MINIMUM_AMOUNT = 1 * 1e18;
    uint public constant REWARD_PER_BLOCK = 0.634 * 1e18;
    uint public constant SECONDS_IN_YEAR = 31536000;
    uint public constant MIN_APR = 25;
    uint public constant STAKING_LENGTH = 365 days;

    mapping(address => bool) private stakerAddressList;

    address public constant STAKING_TOKEN_ADDRESS = 0xd9145CCE52D386f254917e481eB44e9943F39138; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);

    constructor() {
        totalSupply = 0;
        lastUpdatePoolSizePercent = 0;
        stakingAllowed = true;
        maxApr = 500; // 500%
        stakesCount = 0;
        percentAutoUpdatePool = 5;
    }

    event Staked(uint _amount, uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event RewardPerBlockUpdatedTimestamp(uint _lastupdate);
    event AdjustMaxApr(uint _maxApr);
    event AdjustpercentAutoUpdatePool(uint _percentAutoUpdatePool);
    event UpdatedStaker(address _staker, bool _allowed);

    function addStakerAddress(address _addr) public onlyOwner {
        stakerAddressList[_addr] = true;
        emit UpdatedStaker(_addr, true);
    }

    function delStakerAddress(address _addr) public onlyOwner {
        stakerAddressList[_addr] = false;
        emit UpdatedStaker(_addr, false);
    }

    function isStakerAddress(address check) public view returns(bool isIndeed) {
        return stakerAddressList[check];
    }

    function adjustMaxApr(uint _maxApr) external onlyOwner {
        maxApr = _maxApr;
        emit AdjustMaxApr(maxApr);
    }

    function adjustpercentAutoUpdatePool(uint _percentAutoUpdatePool) external onlyOwner {
        percentAutoUpdatePool = _percentAutoUpdatePool;
        emit AdjustMaxApr(percentAutoUpdatePool);
    }

    function updateRewardPerBlock() external onlyOwner {
        _updateRewardPerBlock();
        lastUpdatePoolSizePercent = totalSupply * 100 / MAX_SUPPLY;
    }

    function allowStaking(bool _allow) external onlyOwner {
        stakingAllowed = _allow;
        emit StakingAllowed(_allow);
    }

    function stake(uint _amount) external {
        _stake(_amount, msg.sender);
    }

    function stakeForSomeoneElse(uint _amount, address _user) external {
        require(isStakerAddress(msg.sender), "Stakers allowed only");
        _stake(_amount, _user);
    }
    function recompound() external nonReentrant {
        uint toClaim = claimableRewards(msg.sender);
        require(toClaim >= MINIMUM_AMOUNT, "Insuficient amount");
        _stake(toClaim, msg.sender);
        _updateLastClaim();
    }

    function claim() external nonReentrant {
        uint toClaim = claimableRewards(msg.sender);
        require(STAKING_TOKEN.balanceOf(address(this)) > toClaim + totalStaked, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender, toClaim), "Transfer failed");
        _updateLastClaim();
        emit Claimed(toClaim);
    }

    function unstake() external nonReentrant returns(uint) {
        uint toUnstake = 0;
        uint i = 0;
        uint stakeId;
        uint toClaim = claimableRewards(msg.sender);
        while(i < userStakeIds[msg.sender].length) {
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

    function getUserStakesIds(address _user) external view returns (uint[] memory) {
        return userStakeIds[_user];
    }

    function claimableRewards(address _user) public view returns (uint) {
        uint reward = 0;
        uint stakeId;
        for(uint i = 0; i < userStakeIds[_user].length; i++) {
            stakeId = userStakeIds[_user][i];
            uint lastClaim = stakingLastClaim[stakeId];
            uint j;
            for(j = 1; j < rewardPerBlockHistory.length; j++) {
                if (rewardPerBlockHistory[j].timestamp > lastClaim) {
                    reward += stakingAmount[stakeId] * (rewardPerBlockHistory[j].timestamp - lastClaim) * rewardPerBlockHistory[j-1].rewardPerBlock / totalSupply;
                    lastClaim = rewardPerBlockHistory[j].timestamp;
                }
            }

            if (block.timestamp > lastClaim) {
                reward += stakingAmount[stakeId] * (block.timestamp - lastClaim) * rewardPerBlockHistory[rewardPerBlockHistory.length -1].rewardPerBlock / totalSupply;
            }
        }
        return reward;
    }

    function _updateLastClaim() internal {
        for(uint i = 0; i < userStakeIds[msg.sender].length; i++) {
            stakingLastClaim[userStakeIds[msg.sender][i]] = block.timestamp;
        }
    }

    function _stake(uint _amount, address _user) internal nonReentrant {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient stake amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        require(userStakeIds[_user].length < 100, "User stakings limit exceeded");

        stakingUser[stakesCount] = _user;
        stakingEndDate[stakesCount] = block.timestamp + STAKING_LENGTH;
        stakingLastClaim[stakesCount] = block.timestamp;
        stakingAmount[stakesCount] = _amount;
        userStakeIds[_user].push(stakesCount);
        totalSupply += _amount;
        totalStaked += _amount;
        stakesCount += 1;
        uint poolSizePercent = totalSupply * 100 / MAX_SUPPLY;
        if (stakesCount == 1) {
            _updateRewardPerBlock();
            lastUpdatePoolSizePercent = poolSizePercent;
        }
        if (poolSizePercent > lastUpdatePoolSizePercent + percentAutoUpdatePool) {
            _updateRewardPerBlock();
            lastUpdatePoolSizePercent = poolSizePercent;
        }
        emit Staked(_amount, totalSupply);
    }

    function _updateRewardPerBlock() internal {
        uint maxRewardPerBlock = totalSupply * maxApr / SECONDS_IN_YEAR / 100 ;
        uint minRewardPerBlock = totalSupply * MIN_APR / SECONDS_IN_YEAR / 100 ;
        uint rewardPerBlock;
 
        if (REWARD_PER_BLOCK < minRewardPerBlock) {
            rewardPerBlock = minRewardPerBlock;
        } else if (REWARD_PER_BLOCK > maxRewardPerBlock) {
            rewardPerBlock = maxRewardPerBlock;
        } else {
            rewardPerBlock = REWARD_PER_BLOCK;
        }
        rewardPerBlockHistory.push(Struct(block.timestamp, rewardPerBlock));
        emit RewardPerBlockUpdatedTimestamp(block.timestamp);
    }
}
