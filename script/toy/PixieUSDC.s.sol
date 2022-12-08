// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";
import {PixieUSDC} from "mgv_src/toy/PixieUSDC.sol";

/**
 * @notice deploys a PixieUSDC instance
 */

contract PixieUSDCDeployer is Deployer {
  function run() public {
    innerRun({admin: fork.get("MgvGovernance")});
    outputDeployment();
  }

  function innerRun(address admin) public {
    broadcast();
    PixieUSDC pixie = new PixieUSDC(admin);
    fork.set("PxUSDC", address(pixie));
  }
}
