// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";

contract UseOracle is Deployer {
  function run() public {
    innerRun({
      oracleAddress: envHas("ORACLE") ? vm.envAddress("ORACLE") : fork.get("MgvOracle"),
      mgvAddress: payable(envHas("MGV") ? vm.envAddress("MGV") : fork.get("Mangrove"))
    });
    outputDeployment();
  }

  function innerRun(address oracleAddress, address payable mgvAddress) public {
    Mangrove mgv = Mangrove(mgvAddress);

    broadcast();
    mgv.setMonitor(oracleAddress);
    broadcast();
    mgv.setUseOracle(true);
  }
}
