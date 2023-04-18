// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";

contract UseOracle is Deployer {
  function run() public {
    innerRun({
      mgv: Mangrove(envAddressOrName("MGV", fork.get("Mangrove"))),
      oracleAddress: envAddressOrName("ORACLE", fork.get("MgvOracle"))
    });
    outputDeployment();
  }

  function innerRun(Mangrove mgv, address oracleAddress) public {
    broadcast();
    mgv.setMonitor(oracleAddress);
    broadcast();
    mgv.setUseOracle(true);
  }
}
