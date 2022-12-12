// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./ERC20BL.sol";

contract MintableERC20BLWithDecimals is
  ERC20BL // enherited an old version of ERC20BL
{
  // This version does not have any "failSoftly" as the TestToken has

  mapping(address => bool) admins;
  uint public __decimals; // full uint to help forge-std's stdstore

  constructor(address admin, string memory name, string memory symbol, uint8 _decimals) ERC20BL(name, symbol) {
    admins[admin] = true;
    __decimals = _decimals;
  }

  function decimals() public view virtual override returns (uint8) {
    return uint8(__decimals);
  }

  function requireAdmin() internal view {
    require(admins[msg.sender], "MintableERC20BLWithDecimals/adminOnly");
  }

  function addAdmin(address admin) external {
    requireAdmin();
    admins[admin] = true;
  }

  function mint(address to, uint amount) external {
    mintRestricted(to, amount);
  }

  function mint(uint amount) external {
    mintRestricted(_msgSender(), amount);
  }

  function mintRestricted(address to, uint amount) internal {
    uint limit = 100_000;
    require(
      amount <= limit * pow(10, decimals()), // was limit.mul(...)
      "MintableERC20BLWithDecimals/mintLimitExceeded"
    );
    _mint(to, amount);
  }

  function mintAdmin(address to, uint amount) external {
    requireAdmin();
    _mint(to, amount);
  }

  function burn(address account, uint amount) external {
    requireAdmin();
    _burn(account, amount);
  }

  function blacklists(address account) external {
    requireAdmin();
    _blacklists(account);
  }

  function whitelists(address account) external {
    requireAdmin();
    _whitelists(account);
  }

  function pow(uint n, uint e) public pure returns (uint) {
    // This function seems not neccesary?
    if (e == 0) {
      return 1;
    } else if (e == 1) {
      return n;
    } else {
      uint p = pow(n, e / 2); // was e.div(2)
      p = p * p; // was p.mul(p)
      if (e % 2 == 1) {
        // was e.mod(2)
        p = p * n; // was p.mul(n)
      }
      return p;
    }
  }
}
