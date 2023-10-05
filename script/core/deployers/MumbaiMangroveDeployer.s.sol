// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "@mgv/lib/ToyENS.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

/**
 * Mumbai specific deployment of MangroveDeployer
 */
contract MumbaiMangroveDeployer is Deployer {
  MangroveDeployer public mangroveDeployer;
  uint public gasprice = 1;
  uint public gasmax = 1_000_000;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveDeployer = new MangroveDeployer();

    mangroveDeployer.innerRun({
      chief: broadcaster(),
      gasprice: gasprice,
      gasmax: gasmax,
      gasbot: envAddressOrName("GASBOT", "Gasbot")
    });
  }
}
