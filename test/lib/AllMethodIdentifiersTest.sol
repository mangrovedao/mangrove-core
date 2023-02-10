// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {stdJson} from "forge-std/StdJson.sol";
import {Vm} from "forge-std/Vm.sol";

library AllMethodIdentifiersTest {
  ///@notice Reads all methodIdentifiers (selectors) from ABI pointed to by relative path from project root.
  function getAllMethodIdentifiers(Vm vm, string memory relativeAbiPath) public view returns (bytes[] memory selectors) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, relativeAbiPath);
    string memory json = vm.readFile(path);

    // This reads the values of methodIdentifiers, but the "~" should make it read keys, so if this test starts failing that may be why.
    string[] memory methodIdentifiers = stdJson.readStringArray(json, ".methodIdentifiers[*]~");
    selectors = new bytes[](methodIdentifiers.length);
    for (uint i = 0; i < methodIdentifiers.length; i++) {
      selectors[i] = vm.parseBytes(methodIdentifiers[i]);
    }
  }
}
