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
 * - prices given by the oracle are in USD with 8 decimals of precision.
 *      Script will throw if oracle uses ETH as base currency instead of USD (as oracle contract permits).
 */
contract MumbaiMangroveFullTestnetDeployer is Deployer {
  uint internal maticPrice;

  function run() public {
    runWithChainSpecificParams();
    outputDeployment();
  }

  function toGweiOfMatic(uint price) internal view returns (uint) {
    return (price * 10 ** 9) / maticPrice;
  }

  function runWithChainSpecificParams() public {
    // Deploy Mangrove
    new MumbaiMangroveDeployer().runWithChainSpecificParams();
    Mangrove mgv = Mangrove(fork.get("Mangrove"));
    MgvReader reader = MgvReader(fork.get("MgvReader"));
    IPriceOracleGetter priceOracle =
      IPriceOracleGetter(IPoolAddressesProvider(fork.get("AaveAddressProvider")).getAddress("PRICE_ORACLE"));
    require(priceOracle.BASE_CURRENCY() == address(0), "script assumes base currency is in USD");

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
    maticPrice = priceOracle.getAssetPrice(fork.get("WMATIC"));

    // 1 token_i = (prices[i] / 10**8) USD
    // 1 USD = (10**8 / maticPrice) Matic
    // 1 token_i = (prices[i] * 10**9 / maticPrice) gwei of Matic
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140, // this overrides Mangrove's gasprice for the computation of market's density
      reader: reader,
      tkn1: dai,
      tkn2: usdc,
      tkn1_in_gwei: toGweiOfMatic(prices[0]),
      tkn2_in_gwei: toGweiOfMatic(prices[1]),
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
      tkn1: weth,
      tkn2: dai,
      tkn1_in_gwei: toGweiOfMatic(prices[2]),
      tkn2_in_gwei: toGweiOfMatic(prices[0]),
      fee: 0
    });
    new ActivateMarket().innerRun({
      mgv: mgv,
      gaspriceOverride: 140,
      reader: reader,
      tkn1: weth,
      tkn2: usdc,
      tkn1_in_gwei: toGweiOfMatic(prices[2]),
      tkn2_in_gwei: toGweiOfMatic(prices[1]),
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
