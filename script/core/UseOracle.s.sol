// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";

import {IMangrove} from "@mgv/src/IMangrove.sol";
import "@mgv/src/core/MgvLib.sol";

contract UseOracle is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      oracle: IMgvMonitor(envAddressOrName("ORACLE", "MgvOracle"))
    });
    outputDeployment();
  }

  function innerRun(IMangrove mgv, IMgvMonitor oracle) public {
    broadcast();
    mgv.setMonitor(address(oracle));
    broadcast();
    mgv.setUseOracle(true);
  }
}
