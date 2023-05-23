// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {MumbaiMangroveDeployer} from "mgv_script/core/deployers/MumbaiMangroveDeployer.s.sol";
import {MumbaiMangroveOrderDeployer} from
  "mgv_script/strategies/mangroveOrder/deployers/MumbaiMangroveOrderDeployer.s.sol";
import {
  MumbaiKandelSeederDeployer,
  KandelSeeder,
  AaveKandelSeeder
} from "mgv_script/strategies/kandel/deployers/MumbaiKandelSeederDeployer.s.sol";

import {ActivateMarket, IERC20} from "mgv_script/core/ActivateMarket.s.sol";
import {ActivateMangroveOrder, MangroveOrder} from "mgv_script/strategies/mangroveOrder/ActivateMangroveOrder.s.sol";
import {KandelSower, IMangrove} from "mgv_script/strategies/kandel/KandelSower.s.sol";
import {IPoolAddressesProvider} from "mgv_src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";
import {IPriceOracleGetter} from "mgv_src/strategies/vendor/aave/v3/IPriceOracleGetter.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

import {console} from "forge-std/console.sol";

/**
 * Deploy and configure a complete Mangrove testnet deployment:
 * - Mangrove and periphery contracts
 * - MangroveOrder
 * - KandelSeeder and AaveKandelSeeder
 * - open markets: DAI/USDC, WETH/DAI, WETH/USDC
 */
contract MumbaiMangroveFullTestnetDeployer is Deployer {
  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function runWithChainSpecificParams() public {
    // Deploy Mangrove
    new MumbaiMangroveDeployer().runWithChainSpecificParams();
    Mangrove mgv = Mangrove(fork.get("Mangrove"));
    MgvReader reader = MgvReader(fork.get("MgvReader"));
    IPriceOracleGetter priceOracle =
      IPriceOracleGetter(IPoolAddressesProvider(fork.get("Aave")).getAddress("PRICE_ORACLE"));
    IERC20 baseCurrency = IERC20(priceOracle.BASE_CURRENCY()); // 0x0 if base currency is USD

    // Deploy MangroveOrder
    new MumbaiMangroveOrderDeployer().runWithChainSpecificParams();
    MangroveOrder mangroveOrder = MangroveOrder(fork.get("MangroveOrder"));

    // Deploy KandelSeeder & AaveKandelSeeder
    (KandelSeeder seeder, AaveKandelSeeder aaveSeeder) = new MumbaiKandelSeederDeployer().runWithChainSpecificParams();

    // Activate markets
    IERC20 dai = IERC20(fork.get("DAI"));
    IERC20 usdc = IERC20(fork.get("USDC"));
    IERC20 weth = IERC20(fork.get("WETH"));

    uint[] memory prices = priceOracle.getAssetsPrices(dynamic([address(dai), address(usdc), address(weth)]));
    console.log("dai %d, usdc %d, weth %d", prices[0], prices[1], prices[2]);

    new ActivateMarket().innerRun({
      mgv: mgv,
      reader: reader,
      tkn1: dai,
      tkn2: usdc,
      tkn1_in_gwei: 35999750,
      tkn2_in_gwei: 40000000,
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      reader: reader,
      tkn1: weth,
      tkn2: dai,
      tkn1_in_gwei: 140245027725,
      tkn2_in_gwei: 35999750,
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      reader: reader,
      tkn1: weth,
      tkn2: usdc,
      tkn1_in_gwei: 140245027725,
      tkn2_in_gwei: 40000000,
      fee: 0
    });

    // Activate MangroveOrder on markets
    IERC20[] memory iercs = new IERC20[](3);
    iercs[0] = weth;
    iercs[1] = dai;
    iercs[2] = usdc;
    new ActivateMangroveOrder().innerRun({
      mgvOrder: mangroveOrder,
      iercs: iercs
    });

    // Deploy Kandel instance via KandelSeeder to get the Kandel contract verified
    new KandelSower().innerRun({
      mgv: IMangrove(payable(mgv)),
      kandelSeeder: seeder,
      base: weth,
      quote: usdc,
      gaspriceFactor: 1,
      sharing: false,
      onAave: false,
      registerNameOnFork: false,
      name: ""
    });

    // Deploy AaveKandel instance via AaveKandelSeeder to get the AaveKandel contract verified
    new KandelSower().innerRun({
      mgv: IMangrove(payable(mgv)),
      kandelSeeder: aaveSeeder,
      base: weth,
      quote: usdc,
      gaspriceFactor: 1,
      sharing: false,
      onAave: true,
      registerNameOnFork: false,
      name: ""
    });
  }
}
