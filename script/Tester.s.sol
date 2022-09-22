// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "./lib/ToyENS.sol";
import {MangroveDeployer} from "./lib/MangroveDeployer.sol";
import {Deployer} from "./lib/Deployer.sol";

contract Whatsup {
  uint i;

  constructor() {
    i = 3;
  }
}

contract WhatsupDeploy is Deployer {
  function run() public {
    vm.broadcast();
    new Whatsup();
    outputDeployment();
  }
}
