// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {stdJson} from "forge-std/StdJson.sol";
import {Vm} from "forge-std/Vm.sol";

library AllMethodIdentifiersTest {
  function charToHex(uint8 c) internal pure returns (uint8) {
    return (bytes1(c) >= bytes1("a"))
      ? 10 + c - uint8(bytes1("a"))
      : (bytes1(c) >= bytes1("A") ? 10 + c - uint8(bytes1("A")) : (c - uint8(bytes1("0"))));
  }

  function fromStringHex(bytes memory stringHex) internal pure returns (bytes memory) {
    bytes memory b = new bytes(stringHex.length/2);
    for (uint i = 0; i < b.length; i++) {
      b[i] = bytes1(charToHex(uint8(stringHex[2 * i])) * 16 + charToHex(uint8(stringHex[2 * i + 1])));
    }
    return b;
  }

  ///@notice Reads all methodIdentifiers (selectors) from ABI pointed to by relative path from project root.
  function getAllMethodIdentifiers(Vm vm, string memory relativeAbiPath) public view returns (bytes[] memory selectors) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, relativeAbiPath);
    string memory json = vm.readFile(path);

    // This reads the values of methodIdentifiers, but the "~" should make it read keys, so if this test starts failing that may be why.
    string[] memory methodIdentifiers = stdJson.readStringArray(json, ".methodIdentifiers[*]~");
    selectors = new bytes[](methodIdentifiers.length);
    for (uint i = 0; i < methodIdentifiers.length; i++) {
      selectors[i] = fromStringHex(bytes(methodIdentifiers[i]));
    }
  }
}
