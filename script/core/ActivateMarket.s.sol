// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";
import "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import "mgv_src/MgvLib.sol";

import {ActivateSemibook} from "./ActivateSemibook.s.sol";
/* Example: activate (USDC,WETH) offer lists. Assume $NATIVE_IN_USDC is the price of ETH/MATIC/native token in USDC; same for $NATIVE_IN_ETH.
 TKN1=USDC \
 TKN2=WETH \
 TICK_SPACING=1 \
 TKN1_IN_GWEI=$(cast --to-wei $(bc -l <<< 1/$NATIVE_IN_USDC) gwei) \
 TKN2_IN_GWEI=$(cast --to-wei $(bc -l <<< 1/$NATIVE_IN_ETH) gwei) \
 FEE=30 \
 forge script --fork-url mumbai ActivateMarket*/

contract ActivateMarket is Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      market: Market({
        tkn0: envAddressOrName("TKN1"),
        tkn1: envAddressOrName("TKN2"),
        tickSpacing: vm.envUint("TICK_SPACING")
      }),
      tkn1_in_gwei: vm.envUint("TKN1_IN_GWEI"),
      tkn2_in_gwei: vm.envUint("TKN2_IN_GWEI"),
      fee: vm.envUint("FEE")
    });
  }

  /* Activates a market on mangrove. Two semibooks are activated, one where the first tokens is outbound and the second inbound, and the reverse.
    mgv: mangrove address
    gaspriceOverride: overrides current mangrove's gasprice for the computation of density - default innerRun uses mangrove's gasprice
    tkn1: first tokens
    tkn2: second tokens,
    tickSpacing: tick spacing,
    tkn1_in_gwei: price of one tkn1 (display units) in gwei
    tkn2_in_gwei: price of one tkn2 (display units) in gwei
    fee: fee in per 10_000
  */

  /* 
    tknX_in_gwei should be obtained like this:
    1. Get the price of one tknX display unit in native token, in display units.
       For instance, on ethereum, the price of 1 WETH is 1e9 gwei
    2. Multiply by 1e9
    3. Round to nearest integer
  */

  function innerRun(
    IMangrove mgv,
    MgvReader reader,
    Market memory market,
    uint tkn1_in_gwei,
    uint tkn2_in_gwei,
    uint fee
  ) public {
    Global global = mgv.global();
    innerRun(mgv, global.gasprice(), reader, market, tkn1_in_gwei, tkn2_in_gwei, fee);
  }

  /**
   * innerRun with gasprice override to allow requiring a higher density without require more bounties from makers
   */

  function innerRun(
    IMangrove mgv,
    uint gaspriceOverride,
    MgvReader reader,
    Market memory market,
    uint tkn1_in_gwei,
    uint tkn2_in_gwei,
    uint fee
  ) public {
    new ActivateSemibook().innerRun({
      mgv: mgv,
      gaspriceOverride: gaspriceOverride,
      olKey: toOLKey(market),
      outbound_in_gwei: tkn1_in_gwei,
      fee: fee
    });

    new ActivateSemibook().innerRun({
      mgv: mgv,
      gaspriceOverride: gaspriceOverride,
      olKey: toOLKey(flipped(market)),
      outbound_in_gwei: tkn2_in_gwei,
      fee: fee
    });

    new UpdateMarket().innerRun({reader: reader, market: market});
  }
}
