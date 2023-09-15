// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrder, IERC20, IMangrove} from "mgv_src/strategies/MangroveOrder.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveOrderDeployer} from "./MangroveOrderDeployer.s.sol";

/**
 * Arbitrum specific deployment of MangroveOrder
 */
contract ArbitrumMangroveOrderDeployer is Deployer {
  MangroveOrderDeployer public mangroveOrderDeployer;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    mangroveOrderDeployer = new MangroveOrderDeployer();
    mangroveOrderDeployer.innerRun({mgv: IMangrove(fork.get("Mangrove")), admin: fork.get("MgvGovernance")});
  }
}
