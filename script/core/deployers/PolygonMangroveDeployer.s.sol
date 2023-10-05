// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "@mgv/lib/ToyENS.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

/**
 * Polygon specific deployment of Mangrove and periphery contracts.
 */
contract PolygonMangroveDeployer is Deployer {
  MangroveDeployer public mangroveDeployer;
  uint public gasprice = 130;
  uint public gasmax = 1_000_000;

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
