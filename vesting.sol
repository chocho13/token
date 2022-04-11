// contracts/TokenVesting.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title TokenVesting
 */
contract TokenVesting is Ownable, ReentrancyGuard{
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct VestingSchedule{
        bool initialized;
        // beneficiary of tokens after they are released
        address  beneficiary;
        // cliff period in seconds
        uint256  cliff;
        // start time of the vesting period
        uint256  start;
        // duration of the vesting period in seconds
        uint256  duration;
        // duration of a slice period for the vesting in seconds
        uint256 slicePeriodSeconds;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens released
        uint256  released;
    }

    // address of the ERC20 token
    IERC20 immutable private _token;

    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    uint256 private vestingSchedulesTotalAmount;
    mapping(address => uint256) private holdersVestingCount;

    mapping(address => bool) private vesterAddressList;

    event Released(uint256 amount);

    /**
    * @dev Reverts if no vesting schedule matches the passed identifier.
    */
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].initialized);
        _;
    }

    /**
    * @dev Reverts if the caller is not on vester list.
    */
    modifier onlyVesters() {
        require(vesterAddressList[msg.sender] == true,"Not authorized");
        _;
    }

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the ERC20 token contract
     */
    constructor(address token_) {
        require(token_ != address(0));
        _token = IERC20(token_);
        vesterAddressList[msg.sender] = true;
    }

    receive() external payable {}

    fallback() external payable {}

    /**
    * @dev Returns the number of vesting schedules associated to a beneficiary.
    * @return the number of vesting schedules
    */
    function getVestingSchedulesCountByBeneficiary(address _beneficiary)
    public
    view
    returns(uint256){
        return holdersVestingCount[_beneficiary];
    }

    /**
    * @dev Returns the vesting schedule id at the given index.
    * @return the vesting id
    */
    function getVestingIdAtIndex(uint256 index)
    external
    view
    returns(bytes32){
        require(index < getVestingSchedulesCount(), "TokenVesting: index out of bounds");
        return vestingSchedulesIds[index];
    }

    /**
    * @notice Returns the vesting schedule information for a given holder and index.
    * @return the vesting schedule structure information
    */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index)
    external
    view
    returns(VestingSchedule memory){
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
    * @notice Returns the total amount of vesting schedules.
    * @return the total amount of vesting schedules
    */
    function getVestingSchedulesTotalAmount()
    external
    view
    returns(uint256){
        return vestingSchedulesTotalAmount;
    }

    /**
    * @dev Returns the address of the ERC20 token managed by the vesting contract.
    */
    function getToken()
    external
    view
    returns(address){
        return address(_token);
    }

    /**
    * FRED : added
    * @dev add address to authorized vesters.
    */
    function addVesterAddress(address _addr) external onlyOwner {
        vesterAddressList[_addr] = true;
    }

    /**
    * FRED : added
    * @dev delete address from authorized vesters.
    */
    function delVesterAddress(address _addr) external onlyOwner {
        delete vesterAddressList[_addr];
    }

    /**
    * FRED : added
    * @dev create multiple vesting.
    */
    function createMultipleVestingSchedule(
        address[] calldata _beneficiaries,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        uint256[] calldata _amounts
    )
        public
        onlyVesters {
            for (uint i; i < _beneficiaries.length; i++) {
                createVestingSchedule(_beneficiaries[i],_start,_cliff,_duration,_slicePeriodSeconds,_amounts[i]);
            }
        }

    /**
    * FRED : changed modifier from onlyOwner to onlyVesters
    * @notice Creates a new vesting schedule for a beneficiary.
    * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
    * @param _start start time of the vesting period
    * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
    * @param _duration duration in seconds of the period in which the tokens will vest
    * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
    * @param _amount total amount of tokens to be released at the end of the vesting
    */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _start,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        uint256 _amount
    )
        public
        onlyVesters {
        require(
            this.getWithdrawableAmount() >= _amount,
            "TokenVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(_duration > 0, "TokenVesting: duration must be > 0");
        require(_amount > 0, "TokenVesting: amount must be > 0");
        require(_slicePeriodSeconds >= 1, "TokenVesting: slicePeriodSeconds must be >= 1");
        bytes32 vestingScheduleId = this.computeNextVestingScheduleIdForHolder(_beneficiary);
        uint256 cliff = _start.add(_cliff);
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            cliff,
            _start,
            _duration,
            _slicePeriodSeconds,
            _amount,
            0
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingCount[_beneficiary];
        holdersVestingCount[_beneficiary] = currentVestingCount.add(1);
    }

    /**
    * @notice Withdraw the specified amount if possible.
    * @param amount the amount to withdraw
    */
    function withdraw(uint256 amount) public nonReentrant onlyOwner {
        require(this.getWithdrawableAmount() >= amount, "TokenVesting: not enough withdrawable funds");
        _token.safeTransfer(owner(), amount);
    }

    /**
    * FRED : added
    * @notice Release vested amount of tokens for gived holder.
    * @param holder is holder address
    */
    function releaseAllforHolder(address holder) public nonReentrant {
        bytes32[] memory vestingIds = getVestingScheduleIdsForHolder(holder);
        uint amountReleased;
        for (uint index; index < vestingIds.length; index++) {
            amountReleased += _release(vestingIds[index]);
        }
        emit Released(amountReleased);
    }

    /**
    * FRED : added
    * @notice Release vested amount of tokens.
    * @param vestingScheduleId the vesting schedule identifier
    */
    function release(bytes32 vestingScheduleId) public nonReentrant {
        emit Released(_release(vestingScheduleId));
    }

    /**
    * FRED : renamed from release to _release and changed from public to internal to manage the nonReentrant at upperlevel
    * FRED : modified isOwner to isVester
    * @notice Release vested amount of tokens.
    * @param vestingScheduleId the vesting schedule identifier
    */
    function _release(bytes32 vestingScheduleId) internal returns (uint) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        // bool isOwner = msg.sender == owner();
        bool isVester = vesterAddressList[msg.sender];
        require(
            isBeneficiary || isVester,
            "TokenVesting: only beneficiary and vesters can release vested tokens"
        );
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount == 0) {return 0;}
        vestingSchedule.released = vestingSchedule.released.add(vestedAmount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(vestedAmount);
        _token.safeTransfer(beneficiaryPayable, vestedAmount);
        return vestedAmount;
    }

    /**
    * @dev Returns the number of vesting schedules managed by this contract.
    * @return the number of vesting schedules
    */
    function getVestingSchedulesCount()
        public
        view
        returns(uint256){
        return vestingSchedulesIds.length;
    }

    /**
    * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
    * @return the vested amount
    */
    function computeReleasableAmount(bytes32 vestingScheduleId) public view returns(uint256){
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
    * FRED : added
    * @notice Computes the vested amount of tokens for the given holder address.
    * @return the vested amount
    */
    function computeReleasableAmountByHolder(address holder) public view  returns(uint256){
        uint amount = 0;
        for (uint index; index < getVestingSchedulesCountByBeneficiary(holder); index++) {
            amount += computeReleasableAmount(computeVestingScheduleIdForAddressAndIndex(holder,index));
        }
        return amount;
    }

    /**
    * @notice Returns the vesting schedule information for a given identifier.
    * @return the vesting schedule structure information
    */
    function getVestingSchedule(bytes32 vestingScheduleId)
        public
        view
        returns(VestingSchedule memory){
        return vestingSchedules[vestingScheduleId];
    }

    /**
    * @dev Returns the amount of tokens that can be withdrawn by the owner.
    * @return the amount of tokens
    */
    function getWithdrawableAmount()
        public
        view
        returns(uint256){
        return _token.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }

    /**
    * @dev Computes the next vesting schedule identifier for a given holder address.
    */
    function computeNextVestingScheduleIdForHolder(address holder)
        public
        view
        returns(bytes32){
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder]);
    }

    /**
    * @dev Returns the last vesting schedule for a given holder address.
    */
    function getLastVestingScheduleForHolder(address holder)
        public
        view
        returns(VestingSchedule memory){
        return vestingSchedules[computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder] - 1)];
    }

    /**
    * FRED - added
    * @dev Returns vesting Ids for a given holder address.
    *
    */
    function getVestingScheduleIdsForHolder(address holder) public view returns(bytes32[] memory){
        uint vestingCount = getVestingSchedulesCountByBeneficiary(holder);
        bytes32[] memory scheduleIds = new bytes32[](vestingCount);
        for (uint index; index < vestingCount; index++) {
            scheduleIds[index] = computeVestingScheduleIdForAddressAndIndex(holder,index);
        }
        return scheduleIds;
    }

    /**
    * @dev Computes the vesting schedule identifier for an address and an index.
    */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index)
        public
        pure
        returns(bytes32){
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
    * @dev Computes the releasable amount of tokens for a vesting schedule.
    * @return the amount of releasable tokens
    */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule)
    internal
    view
    returns(uint256){
        uint256 currentTime = getCurrentTime();
        if (currentTime < vestingSchedule.cliff) {
            return 0;
        } else if (currentTime >= vestingSchedule.start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = currentTime.sub(vestingSchedule.start);
            uint secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }

    function getCurrentTime()
        internal
        virtual
        view
        returns(uint256){
        return block.timestamp;
    }

}
