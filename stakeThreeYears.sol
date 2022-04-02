// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract ThreeYearsStakingContract is Ownable, ReentrancyGuard {

    address public constant STAKING_TOKEN_ADDRESS = 0x1d0Ac23F03870f768ca005c84cBb6FB82aa884fD; // galeon address
    IERC20 private constant STAKING_TOKEN = IERC20(STAKING_TOKEN_ADDRESS);

    uint public constant POOL_SIZE = 240 * 1e6 * 1e18;
    uint public constant MAX_SUPPLY = 200 * 1e6 * 1e18;
    uint public constant STAKING_DURATION = 1095 days; // 3 years
    uint public constant MIN_APR = 30; // 30 % = 10000 * POOL_SIZE / MAX_SUPPLY / STAKING_YEARS_PERCENT
    uint public constant MINIMUM_AMOUNT = 500 * 1e18; // TODO 500

    uint private constant SECONDS_IN_YEAR = 60 * 60 * 24 * 365;
    uint private constant STAKING_YEARS_PERCENT = 300;

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

    struct Struct {
        uint timestamp;
        uint apr;
    }

    struct Stake {
        uint id;
        uint amount;
        uint endDate;
        uint lastClaim;
    }

    Struct[] public aprHistory;

    mapping(address => bool) private stakerAddressList;

    constructor() {
        totalSupply = 0;
        lastUpdatePoolSizePercent = 0;
        stakingAllowed = false; // TODO false
        maxApr = 500;
        stakesCount = 0;
        percentAutoUpdatePool = 5;
        aprHistory.push(Struct(block.timestamp, maxApr));
    }

    event Staked(uint _amount, uint _totalSupply);
    event Unstaked(uint _amount);
    event Claimed(uint _claimed);
    event StakingAllowed(bool _allow);
    event AprUpdated(uint _lastupdate, uint _apr);
    event AdjustMaxApr(uint _maxApr);
    event AdjustpercentAutoUpdatePool(uint _percentAutoUpdatePool);
    event UpdatedStaker(address _staker, bool _allowed);
    event LastClaim(address _staker, uint _lastClaim);

    function addStakerAddress(address _addr) external onlyOwner {
        stakerAddressList[_addr] = true;
        emit UpdatedStaker(_addr, true);
    }

    function delStakerAddress(address _addr) external onlyOwner {
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

    function updateApr() external onlyOwner {
        _updateApr();
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
        require(_user != address(0), "0x address not allowed");
        require(isStakerAddress(msg.sender), "Stakers allowed only");
        _stake(_amount, _user);
    }

    function recompound() external {
        uint toClaim = getClaimableRewards(msg.sender);
        require(toClaim >= MINIMUM_AMOUNT, "Insuficient amount");
        _stake(toClaim, msg.sender);
        _updateLastClaim();
    }

    function claim() external nonReentrant {
        uint toClaim = getClaimableRewards(msg.sender);
        require(toClaim > 0, "Nothing to claim");
        require(STAKING_TOKEN.balanceOf(address(this)) > toClaim + totalStaked, "Insuficient contract balance");
        require(STAKING_TOKEN.transfer(msg.sender, toClaim), "Transfer failed");
        _updateLastClaim();
        emit Claimed(toClaim);
    }

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

    function getUserStakesIds(address _user) external view returns (uint[] memory) {
        return userStakeIds[_user];
    }

    function getUserStakes() external view returns (Stake[] memory) {
        Stake[] memory stakes = new Stake[](userStakeIds[msg.sender].length);
        uint stakeId;
        for(uint i; i < userStakeIds[msg.sender].length; i++) {
            stakeId = userStakeIds[msg.sender][i];
            stakes[i] = Stake(stakeId, stakingAmount[stakeId], stakingEndDate[stakeId], stakingLastClaim[stakeId]);
        }
        return stakes;
    }

    function getCurrentApr() external view returns (uint) {
        return aprHistory[aprHistory.length - 1].apr;
    }

    function getClaimableRewards(address _user) public view returns (uint) {
        uint reward = 0;
        uint stakeId;
        for (uint i = 0; i < userStakeIds[_user].length; i++) {
            stakeId = userStakeIds[_user][i];
            uint lastClaim = stakingLastClaim[stakeId];
            uint endDate = stakingEndDate[stakeId];

            uint until = block.timestamp;
            if (endDate < block.timestamp) {
                until = endDate;
            }

            uint j;
            for (j = 1; j < aprHistory.length; j++) {
                if (aprHistory[j].timestamp > lastClaim) {

                    uint interval = aprHistory[j].timestamp - lastClaim;
                    if (until < aprHistory[j].timestamp) {
                        interval = until - lastClaim;
                        //  > 0 ? until - lastClaim : 0;
                    }

                    reward += stakingAmount[stakeId] * interval * aprHistory[j-1].apr / 100 / SECONDS_IN_YEAR;
                    lastClaim = until < aprHistory[j].timestamp ? until : aprHistory[j].timestamp;
                }
            }

            if (until > lastClaim) {
                uint interval = until - lastClaim;
                //  > 0 ? until - lastClaim : 0;
                reward += stakingAmount[stakeId] * interval * aprHistory[aprHistory.length - 1].apr / 100 / SECONDS_IN_YEAR;
            }
        }
        return reward;
    }

    function _updateLastClaim() internal {
        for (uint i = 0; i < userStakeIds[msg.sender].length; i++) {
            stakingLastClaim[userStakeIds[msg.sender][i]] = block.timestamp;
        }
        emit LastClaim(msg.sender,block.timestamp);
    }

    function _stake(uint _amount, address _user) internal nonReentrant {
        require(stakingAllowed, "Staking is not enabled");
        require(_amount >= MINIMUM_AMOUNT, "Insuficient stake amount");
        require(totalSupply + _amount <= MAX_SUPPLY, "Pool capacity exceeded");
        require(_amount <= STAKING_TOKEN.balanceOf(msg.sender), "Insuficient balance");
        require(STAKING_TOKEN.transferFrom(msg.sender, address(this), _amount), "TransferFrom failed");
        require(userStakeIds[_user].length < 100, "User stakings limit exceeded");

        stakingUser[stakesCount] = _user;
        stakingAmount[stakesCount] = _amount;
        stakingEndDate[stakesCount] = block.timestamp + STAKING_DURATION;
        stakingLastClaim[stakesCount] = block.timestamp;
        userStakeIds[_user].push(stakesCount);
        totalSupply += _amount;
        totalStaked += _amount;
        stakesCount += 1;
        uint poolSizePercent = totalSupply * 100 / MAX_SUPPLY;
        if (poolSizePercent > lastUpdatePoolSizePercent + percentAutoUpdatePool) {
            _updateApr();
            lastUpdatePoolSizePercent = poolSizePercent;
        }
        emit Staked(_amount, totalSupply);
    }

    function _updateApr() internal {
        require(totalSupply > 0, "0 division protection");
        uint apr = 10000 * POOL_SIZE / totalSupply / STAKING_YEARS_PERCENT;
        if (apr < MIN_APR) {
            apr = MIN_APR;
        } else if (apr > maxApr) {
            apr = maxApr;
        }
        aprHistory.push(Struct(block.timestamp, apr));
        emit AprUpdated(block.timestamp, apr);
    }
}
