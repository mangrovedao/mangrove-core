// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {IMangrove, IERC20, KandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {AaveKandelSeeder} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandelSeeder.sol";
import {CoreKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice deploys a Kandel seeder
 */

contract KandelSeederDeployer is Deployer {
  function run() public {
    (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) = innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      addressesProvider: fork.get("Aave"),
      aaveKandelGasreq: vm.envUint("AAVE_KANDEL_GASREQ"),
      kandelGasreq: vm.envUint("KANDEL_GASREQ"),
      aaveRouterGasreq: vm.envUint("AAVE_ROUTER_GASREQ")
    });
    smokeTest(seeder, aaveSeeder);
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
    console.log("Deployed!");
  }

  function smokeTest(KandelSeeder kandelSeeder, AaveKandelSeeder aaveKandelSeeder) internal {
    string memory baseName;
    string memory quoteName;
    if (keccak256(abi.encode(fork.NAME())) == keccak256("mumbai")) {
      baseName = "WETH_AAVE";
      quoteName = "DAI_AAVE";
    } else {
      baseName = "WETH";
      quoteName = "DAI";
    }
    IERC20 base = IERC20(fork.get("WETH"));
    IERC20 quote = IERC20(fork.get("DAI"));

    KandelSeeder.KandelSeed memory seed =
      KandelSeeder.KandelSeed({base: base, quote: quote, gasprice: 0, liquiditySharing: true});
    CoreKandel kandel = kandelSeeder.sow(seed);
    require(address(kandel.router()) == address(kandel.NO_ROUTER()), "Incorrect router address");
    require(kandel.admin() == address(this), "Incorrect admin");
    require(kandel.RESERVE_ID() == kandel.admin(), "Incorrect id");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kandel.checkList(tokens);

    AaveKandelSeeder.KandelSeed memory aaveSeed =
      AaveKandelSeeder.KandelSeed({base: base, quote: quote, gasprice: 0, liquiditySharing: true});
    CoreKandel aaveKandel = aaveKandelSeeder.sow(aaveSeed);
    require(address(aaveKandel.router()) == address(aaveKandelSeeder.AAVE_ROUTER()), "Incorrect router address");
    require(aaveKandel.admin() == address(this), "Incorrect admin");
    require(aaveKandel.RESERVE_ID() == aaveKandel.admin(), "Incorrect id");
    aaveKandel.checkList(tokens);
  }
}
