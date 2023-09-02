// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Test2} from "mgv_lib/Test2.sol";
import {stdJson} from "forge-std/StdJson.sol";

using stdJson for string;

contract IMangroveAbiTest is Test2 {
  function test_abi_is_identical() public {
    string memory root = vm.projectRoot();
    string memory mangrovePath = string.concat(root, "/out/Mangrove.sol/Mangrove.json");
    string memory interfacePath = string.concat(root, "/out/IMangrove.sol/IMangrove.json");
    string memory mangroveJson = vm.readFile(mangrovePath);
    string memory interfaceJson = vm.readFile(interfacePath);

    string[] memory mangroveAbiElementsWithConstructor = stdJson.readStringArray(mangroveJson, ".abi");
    string[] memory mangroveAbiElements = new string[](mangroveAbiElementsWithConstructor.length-1);
    // Delete constructor definition as it is not present in interface
    for (uint i; i < mangroveAbiElements.length; ++i) {
      mangroveAbiElements[i] = mangroveAbiElementsWithConstructor[i + 1];
    }

    string memory errorMessage = string.concat(
      "IMangrove and Mangrove ABIs are not identical, Compare the two files to see more detailed diff (ignore ctor) (",
      mangrovePath,
      " ",
      interfacePath,
      ")"
    );

    string[] memory interfaceAbiElements = stdJson.readStringArray(interfaceJson, ".abi");
    uint minLength = mangroveAbiElements.length > interfaceAbiElements.length
      ? interfaceAbiElements.length
      : mangroveAbiElements.length;
    for (uint i = 0; i < minLength; i++) {
      assertEq(
        mangroveAbiElements[i],
        interfaceAbiElements[i],
        string.concat("JSON array index ", vm.toString(i), " ", errorMessage)
      );
    }
    if (mangroveAbiElements.length > interfaceAbiElements.length) {
      fail(string.concat("Mangrove implementation has more definitions. ", errorMessage));
    }

    if (interfaceAbiElements.length > mangroveAbiElements.length) {
      fail(string.concat("IMangrove interface has more definitions. ", errorMessage));
    }
  }
}