// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
import "../ERC20BLWithDecimals.sol";

contract TestTokenWithDecimals is ERC20BLWithDecimals {
  mapping(address => bool) admins;

  constructor(
    address admin,
    string memory name,
    string memory symbol,
    uint8 decimals
  ) ERC20BLWithDecimals(name, symbol, decimals) {
    admins[admin] = true;
  }

  function requireAdmin() internal view {
    require(admins[msg.sender], "TestToken/adminOnly");
  }

  function addAdmin(address admin) external {
    requireAdmin();
    admins[admin] = true;
  }

  function mint(address to, uint amount) external {
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
}
