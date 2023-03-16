// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IMangrove, KandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {AaveKandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {AbstractKandelSeeder} from
  "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandelSeeder.sol";
import {CoreKandel, IERC20} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";

/**
 * @notice deploys a Kandel seeder
 */

contract KandelSeederDeployer is Deployer {
  function run() public {
    (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) = innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      addressesProvider: fork.get("Aave"),
      aaveKandelGasreq: 160_000,
      kandelGasreq: 160_000,
      aaveRouterGasreq: 500_000
    });
    smokeTest(seeder, AbstractRouter(address(0)));
    smokeTest(aaveSeeder, aaveSeeder.AAVE_ROUTER());
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    address addressesProvider,
    uint aaveRouterGasreq,
    uint aaveKandelGasreq,
    uint kandelGasreq
  ) public returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) {
    prettyLog("Deploying Kandel seeder...");
    broadcast();
    seeder = new KandelSeeder(mgv, kandelGasreq);
    fork.set("KandelSeeder", address(seeder));
    prettyLog("Deploying AaveKandel seeder...");
    broadcast();
    aaveSeeder = new AaveKandelSeeder(mgv, addressesProvider, aaveRouterGasreq, aaveKandelGasreq);
    fork.set("AaveKandelSeeder", address(aaveSeeder));
    fork.set("AavePooledRouter", address(aaveSeeder.AAVE_ROUTER()));
    console.log("Deployed!");
  }

  function smokeTest(AbstractKandelSeeder kandelSeeder, AbstractRouter expectedRouter) internal {
    IERC20 base = IERC20(fork.get("WETH"));
    IERC20 quote = IERC20(fork.get("DAI"));

    AbstractKandelSeeder.KandelSeed memory seed =
      AbstractKandelSeeder.KandelSeed({base: base, quote: quote, gasprice: 0, liquiditySharing: true});
    CoreKandel kandel = kandelSeeder.sow(seed);

    require(kandel.router() == expectedRouter, "Incorrect router address");
    require(kandel.admin() == address(this), "Incorrect admin");
    require(kandel.RESERVE_ID() == kandel.admin(), "Incorrect id");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kandel.checkList(tokens);
  }
}
