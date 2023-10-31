// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "@mgv/lib/ToyENS.sol";

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

/**
 * Arbitrum specific deployment of Mangrove and periphery contracts.
 */
contract ArbitrumMangroveDeployer is Deployer {
  MangroveDeployer public mangroveDeployer;
  uint public gasprice = 3; /* Arbitrary choose value from https://dune.com/queries/1009797/1744913 */
  /*
    Value is fixed at 0x4000000000000, but it's important to note that Arbitrum currently has a 32M gas limit per block 
    https://docs.arbitrum.io/arbitrum-ethereum-differences
    15/09/2023.
  */
  uint public gasmax = 3_000_000;

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
