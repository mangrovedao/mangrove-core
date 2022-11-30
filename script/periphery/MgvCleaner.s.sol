// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";

import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
/**
 * @notice deploys a MgvReader instance
 */

contract MgvCleanerDeployer is Deployer {
  function run() public {
    innerRun({mgv: envHas("MGV") ? envAddressOrName("MGV") : fork.get("Mangrove")});
    outputDeployment();
  }

  function innerRun(address mgv) public {
    broadcast();
    MgvCleaner cleaner = new MgvCleaner({mgv: payable(mgv)});
    fork.set("MgvCleaner", address(cleaner));
  }
}
