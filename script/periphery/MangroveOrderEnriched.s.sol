// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "../lib/Deployer.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/strategies/MangroveOrderEnriched.sol";

/**
 * @notice deploys a MgvReader instance
 */

contract MangroveOrderEnrichedDeployer is Deployer {
  function run() public {
    address mgv = envHas("MANGROVE") ? vm.envAddress("MANGROVE") : fork.get("Mangrove");
    address governance = fork.get("MgvGovernance");
    innerRun({mgv: mgv, admin: governance});
    outputDeployment();
  }

  function innerRun(address mgv, address admin) public {
    broadcast();
    MangroveOrderEnriched mgvOrder = new MangroveOrderEnriched(IMangrove(payable(mgv)), admin);
    fork.set("MangroveOrderEnriched", address(mgvOrder));
  }
}
