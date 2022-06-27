// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import "./ERC20BL.sol";
import "mgv_test/lib/Test2.sol";

contract TestToken is ERC20BL, Test2 {
  mapping(address => bool) admins;
  uint8 __decimals;

  constructor(
    address admin,
    string memory name,
    string memory symbol
  ) ERC20BL(name, symbol) {
    admins[admin] = true;
  }

  function $(uint amount) public view returns (uint) {
    return amount * 10**decimals();
  }

  function decimals() public view override returns (uint8) {
    return __decimals;
  }

  function setDecimals(uint8 _decimals) public {
    requireAdmin();
    __decimals = _decimals;
  }

  function requireAdmin() internal view {
    require(admins[msg.sender], "TestToken/adminOnly");
  }

  function addAdmin(address admin) external {
    requireAdmin();
    admins[admin] = true;
  }

  function removeAdmin(address admin) external {
    requireAdmin();
    admins[admin] = false;
  }

  function mint(address to, uint amount) external {
    requireAdmin();
    _mint(to, amount);
  }

  function burn(address from, uint amount) external {
    requireAdmin();
    _burn(from, amount);
  }

  function blacklists(address account) external {
    requireAdmin();
    _blacklists(account);
  }

  function whitelists(address account) external {
    requireAdmin();
    _whitelists(account);
  }

  /* return underlying amount with correct number of decimals */
  function cash(uint amt) public view returns (uint) {
    return amt * 10**this.decimals();
  }

  /* return underlying amount divided by 10**power */
  function cash(uint amt, uint power) public view returns (uint) {
    return cash(amt) / 10**power;
  }
}
