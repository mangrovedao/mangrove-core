// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {KandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {AbstractKandelSeeder} from
  "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/**
 * @notice deploys a Kandel seeder
 */

contract KandelSow is Deployer {
  function run() public {
    innerRun({
      seeder: envAddressOrName("KANDELSEEDER"),
      base: envAddressOrName("BASE"),
      quote: envAddressOrName("QUOTE"),
      gasprice: vm.envUint("GASPRICE")
    });
  }

  function innerRun(address seeder, address base, address quote, uint gasprice) public {
    KandelSeeder kandelSeeder = KandelSeeder(seeder);
    AbstractKandelSeeder.KandelSeed memory seed =
      AbstractKandelSeeder.KandelSeed(IERC20(base), IERC20(quote), gasprice, false);
    broadcast();
    kandelSeeder.sow(seed);
  }
}
