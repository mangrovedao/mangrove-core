// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";

import {MintableERC20BLWithDecimals} from "mgv_test/lib/tokens/MintableERC20BLWithDecimals.sol";

contract PixieMATIC is MintableERC20BLWithDecimals {
  constructor(address admin) MintableERC20BLWithDecimals(admin, "Pixie MATIC", "PxMATIC", 18) {}
}
/**
 * @notice deploys a MgvReader instance
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
