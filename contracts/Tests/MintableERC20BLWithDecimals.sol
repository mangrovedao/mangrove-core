// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
import "./ERC20BLWithDecimals.sol";
import "./SafeMath.sol";

contract MintableERC20BLWithDecimals is ERC20BLWithDecimals {
  using SafeMath for uint;

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
    require(admins[msg.sender], "MintableERC20BLWithDecimals/adminOnly");
  }

  function addAdmin(address admin) external {
    requireAdmin();
    admins[admin] = true;
  }

  function mint(uint amount) external {
    uint limit = 1000;
    require(
      amount <= limit.mul(pow(10, decimals())),
      "MintableERC20BLWithDecimals/mintLimitExceeded"
    );
    _mint(_msgSender(), amount);
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
    if (e == 0) {
      return 1;
    } else if (e == 1) {
      return n;
    } else {
      uint p = pow(n, e.div(2));
      p = p.mul(p);
      if (e.mod(2) == 1) {
        p = p.mul(n);
      }
      return p;
    }
  }
}
