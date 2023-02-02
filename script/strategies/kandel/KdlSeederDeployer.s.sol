// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {
  IMangrove,
  IERC20,
  KandelSeeder,
  CoreKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveTest, Test} from "mgv_test/lib/MangroveTest.sol";

/**
 * @notice deploys a Kandel instance on a given market
 * @dev since the max number of price slot Kandel can use is an immutable, one should deploy Kandel on a large price range.
 */

contract KdlSeederDeployer is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(fork.get("Mangrove")),
      addressesProvider: fork.get("Aave"),
      aaveKandelGasreq: vm.envUint("AAVE_KANDEL_GASREQ"),
      kandelGasreq: vm.envUint("KANDEL_GASREQ"),
      aaveRouterGasreq: vm.envUint("AAVE_ROUTER_GASREQ")
    });
  }

  function innerRun(
    IMangrove mgv,
    address addressesProvider,
    uint aaveRouterGasreq,
    uint aaveKandelGasreq,
    uint kandelGasreq
  ) public {
    prettyLog("Deploying Kandel seeder...");
    broadcast();
    KandelSeeder kdlseeder = new KandelSeeder(mgv, addressesProvider, aaveRouterGasreq, aaveKandelGasreq, kandelGasreq);
    console.log("Deployed!");
    smokeTest(kdlseeder);
  }

  function smokeTest(KandelSeeder kdlseeder) internal {
    string memory baseName;
    string memory quoteName;
    if (keccak256(abi.encode(fork.NAME())) == keccak256("mumbai")) {
      baseName = "WETH_AAVE";
      quoteName = "DAI_AAVE";
    } else {
      baseName = "WETH";
      quoteName = "DAI";
    }
    IERC20 base = IERC20(fork.get(baseName));
    IERC20 quote = IERC20(fork.get(quoteName));

    KandelSeeder.KandelSeed memory seed = KandelSeeder.KandelSeed({
      base: base,
      quote: quote,
      gasprice: 0,
      onAave: true,
      compoundRateBase: 10_000,
      compoundRateQuote: 10_000,
      liquiditySharing: true
    });
    CoreKandel kdl = kdlseeder.sow(seed);
    require(address(kdl.router()) == address(kdlseeder.AAVE_ROUTER()), "Incorrect router address");
    require(kdl.admin() == address(this), "Incorrect admin");
    require(kdl.owner() == kdl.admin(), "Incorrect owner");
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    kdl.checkList(tokens, kdl.owner());
  }
}
