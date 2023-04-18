// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {IMgvMonitor} from "mgv_src/MgvLib.sol";

contract UseOracle is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", fork.get("Mangrove"))),
      oracle: IMgvMonitor(envAddressOrName("ORACLE", fork.get("MgvOracle")))
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, IMgvMonitor oracle) public {
    broadcast();
    mgv.setMonitor(address(oracle));
    broadcast();
    mgv.setUseOracle(true);
  }
}
