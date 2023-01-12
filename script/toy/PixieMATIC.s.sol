// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";
import {PixieMATIC} from "mgv_src/toy/PixieMATIC.sol";

/**
 * @notice deploys a PixieMATIC instance
 */

contract PixieMATICDeployer is Deployer {
  function run() public {
    innerRun({admin: fork.get("MgvGovernance")});
    outputDeployment();
  }

  function innerRun(address admin) public {
    broadcast();
    PixieMATIC pixie = new PixieMATIC(admin);
    fork.set("PxMATIC", address(pixie));
  }
}
