// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MgvReader, IMangrove} from "src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 ADMIN=$MUMBAI_PRIVATE_ADDRESS forge script --fork-url mumbai MgvReaderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MgvReaderDeployer -vvv --broadcast --verify
*/
contract MgvReaderDeployer is Deployer {
  function run() public {
    address payable mgv = fork.get("Mangrove");
    console.log("Deploying Mangrove Reader...");

    broadcast();
    MgvReader mgvr = new MgvReader(mgv);
    fork.set("MgvReader", address(mgvr));
    outputDeployment();
    console.log("Deployed!", address(mgvr));
  }
}
