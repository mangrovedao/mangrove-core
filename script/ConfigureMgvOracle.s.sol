// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "./lib/Deployer.sol";
import {MgvOracle} from "../src/periphery/MgvOracle.sol";
import {Mangrove} from "../src/Mangrove.sol";

contract ConfigureMgvOracle is Deployer {
  function run(
    Mangrove mgv,
    MgvOracle oracle,
    address bot
  ) public {
    vm.startBroadcast();

    oracle.setMutator(bot);
    mgv.setMonitor(address(oracle));
    mgv.setUseOracle(true);

    vm.stopBroadcast();

    outputDeployment();
  }
}
