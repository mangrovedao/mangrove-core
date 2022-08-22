// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "./lib/ToyENS.sol";
import {MangroveDeployer} from "./lib/MangroveDeployer.sol";
import {Deployer} from "./lib/Deployer.sol";

contract MumbaiDeploy is Deployer {
  function run() public {
    new MangroveDeployer().deploy({
      chief: msg.sender,
      gasprice: 50,
      gasmax: 1_000_000
    });
    outputDeployment();
  }
}
