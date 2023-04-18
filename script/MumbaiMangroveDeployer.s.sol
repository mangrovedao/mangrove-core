// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

contract MumbaiMangroveDeployer is Deployer {
  function run() public {
    new MangroveDeployer().innerRun({
      chief: broadcaster(),
      gasprice: 50,
      gasmax: 1_000_000,
      gasbot: envHas("GASBOT") ? envAddressOrName("GASBOT") : fork.get("Gasbot")
    });
    outputDeployment();
  }
}
