pragma solidity ^0.8.14;

import {IERC20} from "mgv_src/IERC20.sol";
import {ERC20Base, ERC20} from "mgv_src/toy/ERC20.sol";

// Wrapper token that can only be transferred or unlocked by whitelisted accounts
contract LockedWrapperToken is ERC20 {
  mapping(address => bool) public admins;
  mapping(address => bool) public whitelisted;
  ERC20 underlying;

  constructor(address admin, string memory name, string memory symbol, ERC20 _underlying)
    ERC20Base(name, symbol)
    ERC20(name)
  {
    admins[admin] = true;
    whitelisted[admin] = true;
    underlying = _underlying;
    _underlying.approve(address(this), type(uint).max);
  }

  modifier onlyAdmin() {
    require(admins[_msgSender()], "LockedWrapperToken/adminOnly");
    _;
  }

  modifier onlyWhitelisted(address account) {
    require(whitelisted[account], "LockedWrapperToken/whitelistedOnly");
    _;
  }

  function addAdmin(address admin) external onlyAdmin {
    admins[admin] = true;
    whitelisted[admin] = true;
  }

  function removeAdmin(address admin) external onlyAdmin {
    admins[admin] = false;
  }

  function addToWhitelist(address account) external onlyAdmin {
    whitelisted[account] = true;
  }

  function addFromWhitelist(address account) external onlyAdmin {
    whitelisted[account] = false;
  }

  function mint(address account, uint amount) public override onlyAdmin returns (bool) {
    underlying.mint(address(this), amount);
    _mint(account, amount);
    return true;
  }

  /**
   * @dev Allow a user to deposit underlying tokens and mint the corresponding number of wrapped tokens.
   */
  function depositFor(address account, uint amount) public onlyWhitelisted(_msgSender()) returns (bool) {
    underlying.transferFrom(_msgSender(), address(this), amount);
    _mint(account, amount);
    return true;
  }

  /**
   * @dev Allow a user to deposit underlying tokens fron another owner and mint the corresponding number of wrapped tokens.
   */
  function depositFrom(address owner, address account, uint amount) public onlyWhitelisted(_msgSender()) returns (bool) {
    bool result = underlying.transferFrom(owner, address(this), amount);
    require(result, "LockedWrapperToken/underlyingTransferFailed");
    _mint(account, amount);
    return true;
  }

  /**
   * @dev Allow a user to burn a number of wrapped tokens and withdraw the corresponding number of underlying tokens.
   */
  function withdrawTo(address account, uint amount) public virtual onlyWhitelisted(_msgSender()) returns (bool) {
    _burn(_msgSender(), amount);
    underlying.transfer(account, amount);
    return true;
  }

  function unlockFor(address account, uint amount) public virtual onlyWhitelisted(_msgSender()) returns (bool) {
    return _unlockFor(account, amount);
  }

  function _unlockFor(address account, uint amount) internal virtual returns (bool) {
    _burn(account, amount);
    underlying.transferFrom(address(this), account, amount);
    return true;
  }

  function transfer(address to, uint amount) public override onlyWhitelisted(_msgSender()) returns (bool) {
    return super.transfer(to, amount);
  }

  function transferFrom(address from, address to, uint amount)
    public
    override
    onlyWhitelisted(_msgSender())
    returns (bool)
  {
    return super.transferFrom(from, to, amount);
  }

  function approve(address spender, uint amount) public override returns (bool) {
    return super.approve(spender, amount);
  }
}
