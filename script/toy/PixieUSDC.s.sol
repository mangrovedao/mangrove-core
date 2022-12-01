// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";

import {MintableERC20BLWithDecimals} from "mgv_test/lib/tokens/MintableERC20BLWithDecimals.sol";

contract PixieUSDC is MintableERC20BLWithDecimals {
  constructor(address admin) MintableERC20BLWithDecimals(admin, "Pixie USDC", "PxUSDC", 6) {}
}
/**
 * @notice deploys a MgvReader instance
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
