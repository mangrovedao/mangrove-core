// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {stdJson} from "@mgv/forge-std/StdJson.sol";
import {Vm} from "@mgv/forge-std/Vm.sol";

library AllMethodIdentifiersTest {
  ///@notice Reads all methodIdentifiers (selectors) from ABI pointed to by relative path from project root.
  function getAllMethodIdentifiers(Vm vm, string memory relativeAbiPath) public view returns (bytes[] memory selectors) {
    string memory root = vm.projectRoot();
    string memory path = string.concat(root, relativeAbiPath);
    string memory json = vm.readFile(path);

    // This reads the values of methodIdentifiers, but the "~" should make it read keys, so if this test starts failing that may be why.
    string memory key = ".methodIdentifiers[*]~";
    // The following should be used when https://github.com/foundry-rs/foundry/issues/4844 is fixed
    // string[] memory methodIdentifiers = stdJson.readStringArray(json, key);
    bytes memory encoded = vm.parseJson(json, key);
    string[] memory methodIdentifiers = abi.decode(encoded, (string[]));
    selectors = new bytes[](methodIdentifiers.length);
    for (uint i = 0; i < methodIdentifiers.length; i++) {
      selectors[i] = vm.parseBytes(methodIdentifiers[i]);
    }
  }
}
