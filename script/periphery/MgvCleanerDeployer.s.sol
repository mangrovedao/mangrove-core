// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";

import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";

/**
 * @notice deploys a MgvReader instance
 */

contract MgvCleanerDeployer is Deployer {
  function run() public {
    innerRun({mgv: Mangrove(envAddressOrName("MGV", fork.get("Mangrove")))});
    outputDeployment();
  }

  function innerRun(Mangrove mgv) public {
    broadcast();
    MgvCleaner cleaner;
    if (forMultisig) {
      cleaner = new MgvCleaner{salt:salt}({mgv: address(mgv)});
    } else {
      cleaner = new MgvCleaner({mgv: address(mgv)});
    }
    fork.set("MgvCleaner", address(cleaner));
  }
}
