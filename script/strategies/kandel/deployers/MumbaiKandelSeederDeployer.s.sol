// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

import {IMangrove, KandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {AaveKandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {KandelSeederDeployer} from "./KandelSeederDeployer.s.sol";

contract MumbaiKandelSeederDeployer is Deployer {
  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) {
    return new KandelSeederDeployer().innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      addressesProvider: envAddressOrName("AAVE", "Aave"),
      aaveKandelGasreq: 160_000,
      kandelGasreq: 160_000,
      aaveRouterGasreq: 500_000
    });
  }
}
