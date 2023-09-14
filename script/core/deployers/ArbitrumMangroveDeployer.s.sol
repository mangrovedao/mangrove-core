// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

/**
 * Arbitrum specific deployment of Mangrove and periphery contracts.
 */
contract ArbitrumMangroveDeployer is Deployer {
  MangroveDeployer public mangroveDeployer;
  uint public gasprice = 30;
  uint public gasmax = 5_000_000;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveDeployer = new MangroveDeployer();

    mangroveDeployer.innerRun({
      chief: fork.get("MgvGovernance"),
      gasprice: gasprice,
      gasmax: gasmax,
      gasbot: fork.get("Gasbot")
    });
  }
}
