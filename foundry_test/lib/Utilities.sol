// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import {console2 as console} from "forge-std/console2.sol";

/* Some general utility methods.
/* You mostly want to inherit `MangroveTest` (which inherits `Utilities`) rather than inherit `Utilities` directly */

contract Utilities {
  /* Convert a uint to its string representation */
  function uint2str(uint _i)
    internal
    pure
    returns (string memory _uintAsString)
  {
    unchecked {
      if (_i == 0) {
        return "0";
      }
      uint j = _i;
      uint len;
      while (j != 0) {
        len++;
        j /= 10;
      }
      bytes memory bstr = new bytes(len);
      uint k = len - 1;
      while (_i != 0) {
        bstr[k--] = bytes1(uint8(48 + (_i % 10)));
        _i /= 10;
      }
      return string(bstr);
    }
  }

  /* units to e-18 units */
  function toEthUnits(uint w, string memory units)
    internal
    pure
    returns (string memory eth)
  {
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
      w = w * (10**(i - 18));
      return string.concat(uint2str(w), suffix);
    } else {
      uint zeroBefore = 18 - i;
      string memory zeros = "";
      while (zeroBefore > 1) {
        zeros = string.concat(zeros, "0");
        zeroBefore--;
      }
      return (string.concat("0.", zeros, uint2str(w), suffix));
    }
  }

  /* return bytes32 as string */
  function s32(bytes32 b) internal pure returns (string memory) {
    string memory s = new string(32);
    assembly {
      mstore(add(s, 32), b)
    }
    return s;
  }

  /* log bytes32 as string */
  function logString32(bytes32 b) internal view {
    string memory s = new string(32);
    assembly {
      mstore(add(s, 32), b)
    }
    console.log(s32(b));
  }

  function getReason(bytes memory returnData)
    internal
    pure
    returns (string memory reason)
  {
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

  /* ARRAY UTILITIES

     inDyn(x) wraps x in a size-1 dynamic array

     asDyn(uint[n] a) turns a into a dynamic array of size n
  */

  function inDyn(uint a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](1);
    ret[0] = a;
    return ret;
  }

  function inDyn(uint[1] memory a) internal pure returns (uint[1][] memory) {
    uint[1][] memory ret = new uint[1][](1);
    ret[0] = a;
    return ret;
  }

  function inDyn(uint[2] memory a) internal pure returns (uint[2][] memory) {
    uint[2][] memory ret = new uint[2][](1);
    ret[0] = a;
    return ret;
  }

  function inDyn(uint[3] memory a) internal pure returns (uint[3][] memory) {
    uint[3][] memory ret = new uint[3][](1);
    ret[0] = a;
    return ret;
  }

  function inDyn(uint[4] memory a) internal pure returns (uint[4][] memory) {
    uint[4][] memory ret = new uint[4][](1);
    ret[0] = a;
    return ret;
  }

  function asDyn(uint[1] memory a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](1);
    ret[0] = a[0];
    return ret;
  }

  function asDyn(uint[2] memory a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](2);
    ret[0] = a[0];
    ret[1] = a[1];
    return ret;
  }

  function asDyn(uint[3] memory a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](3);
    ret[0] = a[0];
    ret[1] = a[1];
    ret[2] = a[2];
    return ret;
  }

  function asDyn(uint[4] memory a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](4);
    ret[0] = a[0];
    ret[1] = a[1];
    ret[2] = a[2];
    ret[3] = a[3];
    return ret;
  }

  function asDyn(uint[5] memory a) internal pure returns (uint[] memory) {
    uint[] memory ret = new uint[](5);
    ret[0] = a[0];
    ret[1] = a[1];
    ret[2] = a[2];
    ret[3] = a[3];
    ret[4] = a[4];
    return ret;
  }

  // function dynArray(uint[1] memory a) internal pure returns (uint[] memory) {
  //   uint[] memory b = new uint[](1);
  //   b[0] = a[0];
  //   return b;
  // }
  // function dynArray(uint[1] memory a) internal pure returns (uint[] memory) {
  //   uint[] memory b = new uint[](1);
  //   b[0] = a[0];
  //   return b;
  // }
}
