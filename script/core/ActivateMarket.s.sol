// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {UpdateMarket} from "@mgv/script/periphery/UpdateMarket.s.sol";
import "@mgv/src/periphery/MgvReader.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import "@mgv/src/core/MgvLib.sol";

import {ActivateSemibook} from "./ActivateSemibook.s.sol";
/* Example: activate (USDC,WETH) offer lists. Assume $NATIVE_IN_USDC is the price of ETH/MATIC/native token in USDC; same for $NATIVE_IN_ETH.
 TKN1=USDC \
 TKN2=WETH \
 TICK_SPACING=1 \
 TKN1_IN_MWEI=$(cast --to-wei $(bc -l <<< 1/$NATIVE_IN_USDC) Mwei) \
 TKN2_IN_MWEI=$(cast --to-wei $(bc -l <<< 1/$NATIVE_IN_ETH) Mwei) \
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
      tkn1_in_Mwei: vm.envUint("TKN1_IN_MWEI"),
      tkn2_in_Mwei: vm.envUint("TKN2_IN_MWEI"),
      fee: vm.envUint("FEE")
    });
  }

  /* Activates a market on mangrove. Two semibooks are activated, one where the first tokens is outbound and the second inbound, and the reverse.
    mgv: mangrove address
    gaspriceOverride: overrides current mangrove's gasprice for the computation of density - default innerRun uses mangrove's gasprice
    tkn1: first tokens
    tkn2: second tokens,
    tickSpacing: tick spacing,
    tkn1_in_Mwei: price of one tkn1 (display units) in Mwei (1Mwei = 1e-12 eth = 1e6 wei)
    tkn2_in_Mwei: price of one tkn2 (display units) in Mwei 
    fee: fee in per 10_000
  */

  /* 
    tknX_in_Mwei should be obtained like this:
    1. Get the price of one tknX display unit in native token (also in display units, so 1e18 base units for the native token).
    2. Multiply by 1e12
    3. Round to nearest integer

    For instance, suppose 1ETH=$2 and 1USDT=$1, the price of 1 USDT is 1e12/2 Mwei.
  */

  function innerRun(
    IMangrove mgv,
    MgvReader reader,
    Market memory market,
    uint tkn1_in_Mwei,
    uint tkn2_in_Mwei,
    uint fee
  ) public {
    Global global = mgv.global();
    innerRun(mgv, global.gasprice(), reader, market, tkn1_in_Mwei, tkn2_in_Mwei, fee);
  }

  /**
   * innerRun with gasprice override to allow requiring a higher density without require more bounties from makers
   */

  function innerRun(
    IMangrove mgv,
    uint gaspriceOverride,
    MgvReader reader,
    Market memory market,
    uint tkn1_in_Mwei,
    uint tkn2_in_Mwei,
    uint fee
  ) public {
    new ActivateSemibook().innerRun({
      mgv: mgv,
      gaspriceOverride: gaspriceOverride,
      olKey: toOLKey(market),
      outbound_in_Mwei: tkn1_in_Mwei,
      fee: fee
    });

    new ActivateSemibook().innerRun({
      mgv: mgv,
      gaspriceOverride: gaspriceOverride,
      olKey: toOLKey(flipped(market)),
      outbound_in_Mwei: tkn2_in_Mwei,
      fee: fee
    });

    new UpdateMarket().innerRun({reader: reader, market: market});
  }
}
