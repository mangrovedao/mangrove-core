// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

/**
 * @notice deploys a MgvReader instance
 */

contract MgvReaderDeployer is Deployer {
  function run() public {
    innerRun({mgv: envHas("MGV") ? envAddressOrName("MGV") : fork.get("Mangrove")});
    outputDeployment();
  }

  function innerRun(address mgv) public {
    broadcast();
    MgvReader reader = new MgvReader({mgv: payable(mgv)});
    fork.set("MgvReader", address(reader));
  }
}
