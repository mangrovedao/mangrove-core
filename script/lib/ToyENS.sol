// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

contract ToyENS {
  mapping(string => address) _addrs;
  mapping(string => bool) _isToken;
  string[] _names;

  function get(string calldata name)
    external
    view
    returns (address addr, bool isToken)
  {
    addr = _addrs[name];
    isToken = _isToken[name];
  }

  function set(string calldata name, address addr) public {
    set(name, addr, false);
  }

  function set(
    string calldata name,
    address addr,
    bool isToken
  ) public {
    _addrs[name] = addr;
    _names.push(name);
    _isToken[name] = isToken;
  }

  function set(
    string[] calldata names,
    address[] calldata addrs,
    bool[] calldata isToken
  ) external {
    for (uint i = 0; i < names.length; i++) {
      set(names[i], addrs[i], isToken[i]);
    }
  }

  function all()
    external
    view
    returns (
      string[] memory names,
      address[] memory addrs,
      bool[] memory isToken
    )
  {
    names = _names;
    addrs = new address[](names.length);
    isToken = new bool[](names.length);
    for (uint i = 0; i < _names.length; i++) {
      addrs[i] = _addrs[names[i]];
      isToken[i] = _isToken[names[i]];
    }
  }
}
