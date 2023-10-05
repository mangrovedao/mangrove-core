// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";

import {ActivateUtils, IERC20} from "mgv_script/core/ActivateSemiBook.s.sol";

import {console} from "forge-std/console.sol";

/**
 * This scripts logs gasbase and density suggested values in order to activate the (TOKEN0, TOKEN1) market using a gasprice override to compute density
 *
 * TOKEN0 the name of the first token
 * TOKEN1 the name of the second token
 * NATIVE_IN_USD the price of a native token in USD with fixed decimals precision (say n)
 * TOKEN[0/1]_IN_USD the price of token[0/1] in USD with the n decimals precision
 * GASPRICE_OVERRIDE is the gasprice (in gwei) to consider to compute density
 * COVER_FACTOR to compute density, i.e density =
 *
 *
 * usage with Native token being AETH (with n=1):
 * GASPRICE_OVERRIDE=1 NATIVE_IN_USD=1600 TOKEN0=USDC TOKEN1=USDT TOKEN0_IN_USD=1 TOKEN1_IN_USD=1 COVER_FACTOR=100 forge script EvalMarketParameters --fork-url arbitrum
 */

contract EvalMarketParameters is Deployer, ActivateUtils {
  uint nativePrice;

  function run() public {
    nativePrice = vm.envUint("NATIVE_IN_USD");
    uint gaspriceOverride = vm.envUint("GASPRICE_OVERRIDE");
    IERC20 token0 = IERC20(envAddressOrName("TOKEN0"));
    IERC20 token1 = IERC20(envAddressOrName("TOKEN1"));
    uint price0 = vm.envUint("TOKEN0_IN_USD");
    uint price1 = vm.envUint("TOKEN1_IN_USD");
    uint coverFactor = vm.envUint("COVER_FACTOR");

    innerRun(token0, token1, price0, price1, gaspriceOverride, coverFactor);
  }

  function toGweiOfNative(uint price) internal view returns (uint) {
    return (price * 10 ** 9) / nativePrice;
  }

  function innerRun(IERC20 token0, IERC20 token1, uint price0, uint price1, uint gaspriceOverride, uint coverFactor)
    public
  {
    uint gasbase = evaluateGasbase(token0, token1);
    console.log("gasbase:", gasbase);
    uint density0 = evaluateDensity(token0, coverFactor, gaspriceOverride, toGweiOfNative(price0));
    console.log("density for outbound %s: %d", token0.symbol(), density0);
    uint density1 = evaluateDensity(token1, coverFactor, gaspriceOverride, toGweiOfNative(price1));
    console.log("density for outbound %s: %d", token1.symbol(), density1);
  }
}
