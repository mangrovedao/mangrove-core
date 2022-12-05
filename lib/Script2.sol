// SPDX-License-Identifier:	AGPL-2.0
pragma solidity ^0.8.13;

import {console2 as console} from "forge-std/console2.sol";
import {Script} from "forge-std/Script.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {ToyENS} from "mgv_lib/ToyENS.sol";

/* Some general utility methods.
/* You may want to inherit `MangroveTest` (which inherits Test2` which inherits `Script2`) rather than inherit `Script2` directly */
contract Script2 is Script {
  /* *** Singleton ***
    Shared global refs for multiple contracts. Better than `vm.etch(hash(name),address(new Contract()).code)`, which does *not* carry over state modification caused by the constructor.
  */

  ToyENS _singletons;

  function singleton(string memory name) public returns (address) {
    if (address(_singletons).code.length == 0) {
      vm.etch(address(_singletons), address(new ToyENS()).code);
      return address(0);
    } else {
      return _singletons._addrs(name);
    }
  }

  function singleton(string memory name, address addr) public {
    require(singleton(name) == address(0), "Script2: cannot update existing singleton");
    _singletons.set(name, addr);
  }

  /* *** Logging *** */
  /* Log arrays */

  function logary(uint[] memory uints) public view {
    string memory s = "";
    for (uint i = 0; i < uints.length; i++) {
      s = string.concat(s, vm.toString(uints[i]));
      if (i < uints.length - 1) {
        s = string.concat(s, ", ");
      }
    }
    console.log(s);
  }

  function logary(int[] memory ints) public view {
    string memory s = "";
    for (uint i = 0; i < ints.length; i++) {
      s = string.concat(s, vm.toString(uint(ints[i])));
      if (i < ints.length - 1) {
        s = string.concat(s, ", ");
      }
    }
    console.log(s);
  }

  /* *** Unit conversion *** */

  function toEthUnits(uint w, string memory units) internal pure returns (string memory eth) {
    string memory suffix = string.concat(" ", units);

    if (w == 0) {
      return (string.concat("0", suffix));
    }
    uint i = 0;
    while (w % 10 == 0) {
      w = w / 10;
      i += 1;
    }
    if (i >= 18) {
      w = w * (10 ** (i - 18));
      return string.concat(vm.toString(w), suffix);
    } else {
      uint zeroBefore = 18 - i;
      string memory zeros = "";
      while (zeroBefore > 1) {
        zeros = string.concat(zeros, "0");
        zeroBefore--;
      }
      return (string.concat("0.", zeros, vm.toString(w), suffix));
    }
  }

  function getReason(bytes memory returnData) internal pure returns (string memory reason) {
    /* returnData for a revert(reason) is the result of
       abi.encodeWithSignature("Error(string)",reason)
       but abi.decode assumes the first 4 bytes are padded to 32
       so we repad them. See:
       https://github.com/ethereum/solidity/issues/6012
     */
    bytes memory pointer = abi.encodePacked(bytes28(0), returnData);
    uint len = returnData.length - 4;
    assembly {
      pointer := add(32, pointer)
      mstore(pointer, len)
    }
    reason = abi.decode(pointer, (string));
  }

  /* *********  ARRAY UTILITIES */

  /* *******
     Convert T[] arrays to U[] arrays
  */
  function toIERC20(address[] memory addrs) internal pure returns (IERC20[] memory ierc20s) {
    assembly {
      ierc20s := addrs
    }
  }

  /* *******
     wrap_dynamic(x) wraps x in a size-1 dynamic array
  */

  function wrap_dynamic(uint a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](1);
    ret[0] = a;
    return ret;
  }

  function wrap_dynamic(uint[1] memory a) internal pure returns (uint[1][] memory) {
    uint[1][] memory ret = new uint[1][](1);
    ret[0] = a;
    return ret;
  }

  function wrap_dynamic(uint[2] memory a) internal pure returns (uint[2][] memory) {
    uint[2][] memory ret = new uint[2][](1);
    ret[0] = a;
    return ret;
  }

  function wrap_dynamic(uint[3] memory a) internal pure returns (uint[3][] memory) {
    uint[3][] memory ret = new uint[3][](1);
    ret[0] = a;
    return ret;
  }

  function wrap_dynamic(uint[4] memory a) internal pure returns (uint[4][] memory) {
    uint[4][] memory ret = new uint[4][](1);
    ret[0] = a;
    return ret;
  }

  /* *****
  Internal utility: copy `words` words from `i_ptr` to `o_ptr`
  */
  function memcpy(uint i_ptr, uint words, uint o_ptr) internal pure {
    while (words > 0) {
      assembly {
        function loc(i, w) -> o {
          o := add(i, mul(sub(w, 1), 32))
        }
        mstore(loc(o_ptr, words), mload(loc(i_ptr, words)))
      }
      words--;
    }
  }

  /* *******
     dynamic(uint[n] a) turns a into a dynamic array of size n
  */

  function dynamic(uint[1] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[2] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[3] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[4] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[5] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[6] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[7] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[8] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[9] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(uint[10] memory a) internal pure returns (uint[] memory ret) {
    ret = new uint[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[1] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[2] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[3] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[4] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[5] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[6] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[7] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[8] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[9] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(int[10] memory a) internal pure returns (int[] memory ret) {
    ret = new int[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[1] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[2] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[3] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[4] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[5] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[6] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[7] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[8] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[9] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(IERC20[10] memory a) internal pure returns (IERC20[] memory ret) {
    ret = new IERC20[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[1] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[2] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[3] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[4] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[5] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[6] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[7] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[8] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[9] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(bytes32[10] memory a) internal pure returns (bytes32[] memory ret) {
    ret = new bytes32[](a.length);
    uint i_ptr;
    uint o_ptr;
    assembly {
      i_ptr := a
      o_ptr := add(ret, 32)
    }
    memcpy(i_ptr, a.length, o_ptr);
  }

  function dynamic(string[1] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[2] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[3] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[4] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[5] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[6] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[7] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[8] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[9] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  function dynamic(string[10] memory a) internal pure returns (string[] memory ret) {
    ret = new string[](a.length);
    for (uint i = 0; i < a.length; i++) {
      ret[i] = a[i];
    }
  }

  /* Math abs */
  function abs(int i) internal pure returns (uint) {
    if (i < 0) {
      return uint(-i);
    } else {
      return uint(i);
    }
  }

  /// @notice Convert a bytes32 array to a string array
  /// @param bs an array of bytes32
  /// @return ss an array of strings
  function strings(bytes32[] memory bs) internal pure returns (string[] memory) {
    string[] memory ss = new string[](bs.length);
    for (uint i = 0; i < bs.length; i++) {
      ss[i] = string(bytes.concat(bs[i]));
    }
    return ss;
  }

  /// @notice Convert a strings array to a bytes32 array
  /// @param ss an array of strings
  /// @return bs an array of bytes32
  function b32s(string[] memory ss) internal pure returns (bytes32[] memory) {
    bytes32[] memory bs = new bytes32[](ss.length);
    for (uint i = 0; i < ss.length; i++) {
      bs[i] = bytes32(bytes(ss[i]));
    }
    return bs;
  }

  /* String stuff */
  // @notice Uppercase any string that only contains ascii lower/uppercase and underscores
  /// @param s a string
  /// @return ss s, uppercased
  function simpleCapitalize(string memory s) internal pure returns (string memory ss) {
    bytes memory b = bytes(s);
    ss = new string(b.length);
    unchecked {
      for (uint i = 0; i < b.length; i++) {
        bytes1 bb = b[i];
        bool lowercase = bb >= "a" && bb <= "z";
        require(lowercase || bb == "_" || (bb >= "A" && bb <= "Z"), "simpleCapitalize input out of range");
        bytes(ss)[i] = lowercase ? bytes1(uint8(bb) - 32) : bb;
      }
    }
  }
}
