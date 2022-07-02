// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import "./ERC20BL.sol";

contract TestToken is ERC20BL {
  mapping(address => bool) admins;
  uint public __decimals; // full uint to help forge-std's stdstore

  constructor(
    address admin,
    string memory name,
    string memory symbol,
    uint8 _decimals
  ) ERC20BL(name, symbol) {
    admins[admin] = true;
    __decimals = _decimals;
  }

  function $(uint amount) public view returns (uint) {
    return amount * 10**decimals();
  }

  function decimals() public view override returns (uint8) {
    return uint8(__decimals);
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
}
