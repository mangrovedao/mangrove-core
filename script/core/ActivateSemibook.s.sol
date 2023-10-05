// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import "@mgv/lib/Test2.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import "@mgv/src/core/MgvLib.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

uint constant COVER_FACTOR = 1000;

/* 
  Activates a semibook on mangrove.
    outbound: outbound token
    inbound: inbound token,
    outbound_in_Mwei: price of one outbound token (display units) in Mwei of native token
    fee: fee in per 10_000

  outbound_in_Mwei should be obtained like this:
  1. Get the price of one outbound token display unit in native token
  2. Multiply by 10^12
  3. Round to nearest integer*/

contract ActivateSemibook is Test2, Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      olKey: OLKey({
        outbound_tkn: envAddressOrName("OUTBOUND_TKN"),
        inbound_tkn: envAddressOrName("INBOUND_TKN"),
        tickSpacing: vm.envUint("TICK_SPACING")
      }),
      outbound_in_Mwei: vm.envUint("OUTBOUND_IN_MWEI"),
      fee: vm.envUint("FEE")
    });
  }

  function innerRun(IMangrove mgv, OLKey memory olKey, uint outbound_in_Mwei, uint fee) public {
    Global global = mgv.global();
    innerRun(mgv, global.gasprice(), olKey, outbound_in_Mwei, fee);
  }

  function innerRun(
    IMangrove mgv,
    uint gaspriceOverride, // the gasprice that is used to compute density. Can be set higher that mangrove's gasprice to avoid dust without impacting user's bounty
    OLKey memory olKey,
    uint outbound_in_Mwei,
    uint fee
  ) public {
    /*

    The gasbase is the gas spent by Mangrove to manage one order execution.  We
    approximate it to twice a taker->mgv->maker,maker->mgv->tkr transfer
    sequence.

    */
    //FIXME: This underestimates, OfferGasBase.t.sol for better estimate.
    uint outbound_gas = measureTransferGas(olKey.outbound_tkn);
    uint inbound_gas = measureTransferGas(olKey.inbound_tkn);
    uint gasbase = 2 * (outbound_gas + inbound_gas);
    console.log("Measured gasbase: %d", gasbase);

    /* 

    The density is the minimal amount of tokens bought per unit of gas spent.
    The heuristic is: The gas cost of executing an order should represent at
    most 1/COVER_FACTOR the value being bought. In other words: multiply the
    price of gas in tokens (obtained from the price of gas in Mwei and the price
    of tokens in Mwei) by COVER_FACTOR to get the density.
    
    Units:
       - outbound_in_Mwei is in Mwei/display token units
       - COVER_FACTOR is unitless
       - decN is in (base token units)/(display token units)
       - global.gasprice() is in Mwei/gas
       - so density is in (base token units token)/gas
    */
    uint outbound_decimals = IERC20(olKey.outbound_tkn).decimals();
    uint density96X32 = DensityLib.paramsTo96X32({
      outbound_decimals: outbound_decimals,
      gasprice_in_Mwei: gaspriceOverride,
      outbound_display_in_Mwei: outbound_in_Mwei,
      cover_factor: COVER_FACTOR
    });

    // min density of at least 1 wei of outbound token
    density96X32 = density96X32 == 0 ? 1 << 32 : density96X32;
    console.log("With gasprice: %d Mwei, cover factor:%d", gaspriceOverride, COVER_FACTOR);
    console.log(
      "Derived density %s %s per gas unit",
      toFixed(density96X32, outbound_decimals),
      IERC20(olKey.outbound_tkn).symbol()
    );

    broadcast();
    mgv.activate({olKey: olKey, fee: fee, density96X32: density96X32, offer_gasbase: gasbase});
  }
}
