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
}
