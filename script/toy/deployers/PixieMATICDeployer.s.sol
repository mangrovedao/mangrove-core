// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "@mgv/forge-std/Script.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {PixieMATIC} from "@mgv/src/toy/PixieMATIC.sol";

/**
 * @notice deploys a PixieMATIC instance
 */

contract PixieMATICDeployer is Deployer {
  function run() public {
    innerRun({admin: envAddressOrName("MGV_GOVERNANCE", "MgvGovernance")});
    outputDeployment();
  }

  function innerRun(address admin) public {
    broadcast();
    PixieMATIC pixie = new PixieMATIC(admin);
    fork.set("PxMATIC", address(pixie));
  }
}
