// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";

contract ConfigureMgvOracle is Deployer {
  function run() public {
    innerRun({
      oracleAddress: envHas("ORACLE") ? vm.envAddress("ORACLE") : fork.get("MgvOracle"),
      gasbotAddress: envHas("GASBOT") ? vm.envAddress("GASBOT") : fork.get("Gasbot"),
      mgvAddress: payable(envHas("MGV") ? vm.envAddress("MGV") : fork.get("Mangrove"))
    });
    outputDeployment();
  }

  function innerRun(address oracleAddress, address gasbotAddress, address payable mgvAddress) public {
    MgvOracle oracle = MgvOracle(oracleAddress);
    Mangrove mgv = Mangrove(mgvAddress);

    broadcast();
    oracle.setMutator(gasbotAddress);
    broadcast();
    mgv.setMonitor(address(oracle));
    broadcast();
    mgv.setUseOracle(true);

    outputDeployment();
  }
}
