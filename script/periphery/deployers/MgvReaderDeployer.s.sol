// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

/**
 * @notice deploys a MgvReader instance
 */

contract MgvReaderDeployer is Deployer {
  function run() public {
    innerRun({mgv: Mangrove(envAddressOrName("MGV", "Mangrove"))});
    outputDeployment();
  }

  function innerRun(Mangrove mgv) public {
    MgvReader reader;
    broadcast();
    if (forMultisig) {
      reader = new MgvReader{salt:salt}({mgv: address(mgv)});
    } else {
      reader = new MgvReader({mgv: address(mgv)});
    }
    fork.set("MgvReader", address(reader));
  }
}
