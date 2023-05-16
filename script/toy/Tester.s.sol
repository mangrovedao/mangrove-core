// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

contract Whatsup {
  uint i;

  constructor() {
    i = 3;
  }
}

contract WhatsupDeploy is Deployer {
  function run() public {
    broadcast();
    new Whatsup();
    outputDeployment();
  }
}
