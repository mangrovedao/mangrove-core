// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IMangrove, KandelSeeder, Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {AaveKandelSeeder, AaveKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
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
    bool deployAaveKandel = true;
    bool deployKandel = true;
    try vm.envBool("DEPLOY_AAVE_KANDEL") returns (bool deployAaveKandel_) {
      deployAaveKandel = deployAaveKandel_;
    } catch {}
    try vm.envBool("DEPLOY_KANDEL") returns (bool deployKandel_) {
      deployKandel = deployKandel_;
    } catch {}
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      addressesProvider: envAddressOrName("AAVE_ADDRESS_PROVIDER", "AaveAddressProvider"),
      aaveKandelGasreq: 200_000,
      kandelGasreq: 200_000,
      aaveRouterGasreq: 380_000,
      deployAaveKandel: deployAaveKandel,
      deployKandel: deployKandel,
      testBase: IERC20(envAddressOrName("TEST_BASE")),
      testQuote: IERC20(envAddressOrName("TEST_QUOTE"))
    });
    outputDeployment();
  }

  function innerRun(
    IMangrove mgv,
    address addressesProvider,
    uint aaveRouterGasreq,
    uint aaveKandelGasreq,
    uint kandelGasreq,
    bool deployAaveKandel,
    bool deployKandel,
    IERC20 testBase,
    IERC20 testQuote
  ) public returns (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) {
    if (deployKandel) {
      prettyLog("Deploying Kandel seeder...");
      broadcast();
      seeder = new KandelSeeder(mgv, kandelGasreq);
      fork.set("KandelSeeder", address(seeder));

      prettyLog("Deploying Kandel instance for code verification...");
      broadcast();
      new Kandel(mgv, testBase, testQuote, 1, 1, address(0));
      smokeTest(mgv, seeder, AbstractRouter(address(0)), testBase, testQuote);
    }
    if (deployAaveKandel) {
      prettyLog("Deploying AaveKandel seeder...");
      // Bug workaround: Foundry has a bug where the nonce is not incremented when AaveKandelSeeder is deployed.
      //                 We therefore ensure that this happens.
      uint64 nonce = vm.getNonce(broadcaster());
      broadcast();
      aaveSeeder = new AaveKandelSeeder(mgv, addressesProvider, aaveRouterGasreq, aaveKandelGasreq);
      // Bug workaround: See comment above `nonce` further up
      if (nonce == vm.getNonce(broadcaster())) {
        vm.setNonce(broadcaster(), nonce + 1);
      }
      fork.set("AaveKandelSeeder", address(aaveSeeder));
      fork.set("AavePooledRouter", address(aaveSeeder.AAVE_ROUTER()));

      prettyLog("Deploying AaveKandel instance for code verification...");
      broadcast();
      new AaveKandel(mgv, testBase, testQuote, 1, 1, address(0));
      smokeTest(mgv, aaveSeeder, aaveSeeder.AAVE_ROUTER(), testBase, testQuote);
    }
    console.log("Deployed!");
  }

  function smokeTest(
    IMangrove mgv,
    AbstractKandelSeeder kandelSeeder,
    AbstractRouter expectedRouter,
    IERC20 testBase,
    IERC20 testQuote
  ) internal {
    // Ensure that WETH/DAI market is open on Mangrove
    vm.startPrank(mgv.governance());
    mgv.activate(address(testBase), address(testQuote), 0, 1, 1);
    mgv.activate(address(testQuote), address(testBase), 0, 1, 1);
    vm.stopPrank();

    AbstractKandelSeeder.KandelSeed memory seed =
      AbstractKandelSeeder.KandelSeed({base: testBase, quote: testQuote, gasprice: 0, liquiditySharing: true});
    CoreKandel kandel = kandelSeeder.sow(seed);

    require(kandel.router() == expectedRouter, "Incorrect router address");
    require(kandel.admin() == address(this), "Incorrect admin");
    if (expectedRouter == kandel.NO_ROUTER()) {
      require(kandel.RESERVE_ID() == address(kandel), "Incorrect id");
    } else {
      require(kandel.RESERVE_ID() == kandel.admin(), "Incorrect id");
    }
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = testBase;
    tokens[1] = testQuote;
    kandel.checkList(tokens);
  }
}
