// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

/* Onchain contract registry with the following features:
 * stores the list of mapped names
 */

contract ToyENS {
  event Set(
    string name,
    address addr
  );

  mapping(string => address) public _addrs;
  string[] _names;

  /* ! Warning ! */
  /* ToyENS should not have any constructor code because its deployed code is sometimes directly written to addresses, either using vm.etch or using anvil_setCode. */

  function get(string calldata name) public view returns (address payable addr) {
    addr = payable(_addrs[name]);
    require(addr != address(0), string.concat("ToyENS: address not found for ", name));
  }

  function set(string calldata name, address addr) public {
    // 0 is a strong absence marker, can't lose that invariant
    require(addr != address(0), "ToyENS: cannot record a name as 0x0");
    if (_addrs[name] == address(0)) {
      _names.push(name);
    }
    _addrs[name] = addr;
    emit Set(name,addr);
  }

  function set(string[] calldata names, address[] calldata addrs) external {
    for (uint i = 0; i < names.length; i++) {
      set(names[i], addrs[i]);
    }
  }

  function all() external view returns (string[] memory names, address[] memory addrs) {
    names = _names;
    addrs = new address[](names.length);
    for (uint i = 0; i < _names.length; i++) {
      addrs[i] = _addrs[names[i]];
    }
  }
}
