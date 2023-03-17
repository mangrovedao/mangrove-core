// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_src/toy/ERC20BL.sol";

contract TestToken is ERC20BL {
  mapping(address => bool) admins;
  uint public __decimals; // full uint to help forge-std's stdstore
  bool returnFalse;
  bool internal returnsBoolOnApproval_ = true;
  bool internal returnsBoolOnTransfer_ = true;

  constructor(address admin, string memory name, string memory symbol, uint8 _decimals) ERC20BL(name, symbol) {
    admins[admin] = true;
    __decimals = _decimals;
  }

  function failSoftly(bool fail) public {
    returnFalse = fail;
  }

  function returnsBoolOnApproval(bool toggle) external {
    returnsBoolOnApproval_ = toggle;
  }

  function returnsBoolOnTransfer(bool toggle) external {
    returnsBoolOnTransfer_ = toggle;
  }

  function $(uint amount) public view returns (uint) {
    return amount * 10 ** decimals();
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

  function transfer(address to, uint amount) public virtual override returns (bool) {
    if (returnFalse) {
      returnFalse = true;
      return false;
    } else {
      if (returnsBoolOnApproval_) {
        return super.transfer(to, amount);
      } else {
        assembly {
          return(0, 0)
        }
      }
    }
  }

  function transferFrom(address from, address to, uint amount) public virtual override returns (bool) {
    if (returnFalse) {
      returnFalse = true;
      return false;
    } else {
      return super.transferFrom(from, to, amount);
    }
  }

  function approve(address spender, uint amount) public virtual override returns (bool) {
    if (returnFalse) {
      returnFalse = true;
      return false;
    } else {
      return super.approve(spender, amount);
    }
  }
}
