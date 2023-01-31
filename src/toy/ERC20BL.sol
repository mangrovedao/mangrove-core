// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./ERC20.sol";

abstract contract ERC20BL is ERC20 {
  mapping(address => bool) public _blacklisted;

  constructor(string memory _name, string memory _symbol) ERC20Base(_name, _symbol) ERC20(_name) {}

  modifier notBlackListed(address addr) {
    require(!_blacklisted[addr], "ERC20BL/Blacklisted");
    _;
  }

  function _blacklists(address addr) internal virtual {
    _blacklisted[addr] = true;
  }

  function _whitelists(address addr) internal virtual {
    _blacklisted[addr] = false;
  }

  function transfer(address to, uint amount)
    public
    virtual
    override
    notBlackListed(to)
    notBlackListed(msg.sender)
    returns (bool)
  {
    return super.transfer(to, amount);
  }

  function approve(address spender, uint amount)
    public
    virtual
    override
    notBlackListed(spender)
    notBlackListed(msg.sender)
    returns (bool)
  {
    return super.approve(spender, amount);
  }

  function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s)
    public
    virtual
    override
    notBlackListed(owner)
    notBlackListed(spender)
  {
    super.permit(owner, spender, value, deadline, v, r, s);
  }

  function transferFrom(address from, address to, uint amount)
    public
    virtual
    override
    notBlackListed(from)
    notBlackListed(to)
    notBlackListed(msg.sender)
    returns (bool)
  {
    return super.transferFrom(from, to, amount);
  }
}
