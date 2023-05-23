// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

/**
 * Mumbai specific deployment of MangroveDeployer
 */
contract MumbaiMangroveDeployer is Deployer {
  MangroveDeployer public mangroveDeployer;
  uint public gasprice = 50;
  uint public gasmax = 1_000_000;

  function run() public {
    runWithChainSpecificParams(gasprice, gasmax);
    outputDeployment();
  }

  function runWithChainSpecificParams(uint gasprice_, uint gasmax_) public {
    mangroveDeployer = new MangroveDeployer();

    mangroveDeployer.innerRun({
      chief: broadcaster(),
      gasprice: gasprice_,
      gasmax: gasmax_,
      gasbot: envAddressOrName("GASBOT", "Gasbot")
    });
  }
}
