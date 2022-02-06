// SPDX-License-Identifier: MIT
pragma solidity 0.8.11;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @custom:security-contact contact@galeon.care
//base Plop on ERC20Capped + Ownable
contract Galeon is ERC20Capped, Ownable {
    // big int to store transfer limit
    uint limit;
    // bool that represent if limit is enabled
    bool limitEnabled;
    // address where the initial tokens will be minted and who owns the contract
    address public immutable multiSig;

    // Long name + shortname  and max supply 4 000 000 000 GALEON
    constructor() ERC20("Galeon", "GALEON") ERC20Capped(4 * 1e9 * 1e18)  {
        multiSig = 0xc0B3974C64ba269A0Ebd5DD698aC496Fcb817aa9;
        // initial circulating supply 1 056 000 000 GALEON
        _mint(multiSig, 1.056 * 1e9 * 1e18);
        // emit Mint event
        emit Mint(multiSig, 1.056 * 1e9 * 1e18);
        // limit to 85 700 GALEON
        limit = 85700 * 1e18;
        // enable transfer limit
        limitEnabled = true;
        // emit TransferLimitUnlocked event
        emit TransferLimitUnlocked(false);
    }
    //function to unlock transfer limit only executable by Owner of the contract
    function unlockTransferLimit() external onlyOwner {
        // check if limit is enabled before go further
        require(limitEnabled, "Action can be done only once");
        // assign MAX_INT to limit
        limit = 2**256 - 1;
        // disable bool
        limitEnabled = false;
        // emit TransferLimitUnlocked event
        emit TransferLimitUnlocked(true);
    }
    // call function, return if limit is enabled
    function isTransferLimitEnabled() external view returns (bool) {
        return limitEnabled;
    }
    // mint function only executable by Owner of the contract
    function mint(address to, uint amount) external onlyOwner {
        _mint(to, amount);
        // emit Mint event
        emit Mint(to, amount);
    }
    // burn function only executable by Owner of the contract
    function burn(address from, uint amount) external onlyOwner {
        _burn(from, amount);
        // emit Burn event
        emit Burn(from, amount);
    }
    // override default transfer function 
    function transfer(address recipient, uint amount) public virtual override returns (bool) {
        // if limiteEnabled check if balance + amount is lower than the limit
        if(limitEnabled) {
            require(balanceOf(recipient) + amount <= limit,"85700 GALEON limit Exceeded");
        }
        // execute orignal transfer method
        super.transfer(recipient, amount);
        return true;
    }

    event TransferLimitUnlocked(bool limitUnlocked);
    event Mint(address to, uint amount);
    event Burn(address from, uint amount);
}
