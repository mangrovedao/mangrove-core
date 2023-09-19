// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import "mgv_lib/Test2.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs, DensityLib, OLKey} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

uint constant COVER_FACTOR = 1000;

/* 
  Activates a semibook on mangrove.
    outbound: outbound token
    inbound: inbound token,
    outbound_in_gwei: price of one outbound token (display units) in gwei of native token
    fee: fee in per 10_000

  outbound_in_gwei should be obtained like this:
  1. Get the price of one outbound token display unit in native token
  2. Multiply by 10^9
  3. Round to nearest integer*/

contract ActivateSemibook is Test2, Deployer {
  function run() public {
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      olKey: OLKey({
        outbound: envAddressOrName("OUTBOUND_TKN"),
        inbound: envAddressOrName("INBOUND_TKN"),
        tickScale: vm.envUint("TICK_SCALE")
      }),
      outbound_in_gwei: vm.envUint("OUTBOUND_IN_GWEI"),
      fee: vm.envUint("FEE")
    });
  }

  function innerRun(IMangrove mgv, OLKey memory olKey, uint outbound_in_gwei, uint fee) public {
    MgvStructs.GlobalPacked global = mgv.global();
    innerRun(mgv, global.gasprice(), olKey, outbound_in_gwei, fee);
  }

  function innerRun(
    IMangrove mgv,
    uint gaspriceOverride, // the gasprice that is used to compute density. Can be set higher that mangrove's gasprice to avoid dust without impacting user's bounty
    OLKey memory olKey,
    uint outbound_in_gwei,
    uint fee
  ) public {
    /*

    The gasbase is the gas spent by Mangrove to manage one order execution.  We
    approximate it to twice a taker->mgv->maker,maker->mgv->tkr transfer
    sequence.

    */
    //FIXME: This underestimates, OfferGasBase.t.sol for better estimate.
    uint outbound_gas = measureTransferGas(olKey.outbound);
    uint inbound_gas = measureTransferGas(olKey.inbound);
    uint gasbase = 2 * (outbound_gas + inbound_gas);
    console.log("Measured gasbase: %d", gasbase);

    /* 

    The density is the minimal amount of tokens bought per unit of gas spent.
    The heuristic is: The gas cost of executing an order should represent at
    most 1/COVER_FACTOR the value being bought. In other words: multiply the
    price of gas in tokens (obtained from the price of gas in gwei and the price
    of tokens in gwei) by COVER_FACTOR to get the density.
    
    Units:
       - outbound_in_gwei is in gwei/display token units
       - COVER_FACTOR is unitless
       - decN is in (base token units)/(display token units)
       - global.gasprice() is in gwei/gas
       - so density is in (base token units token)/gas
    */
    uint outbound_decimals = IERC20(olKey.outbound).decimals();
    uint density96X32 = DensityLib.paramsTo96X32({
      outbound_decimals: outbound_decimals,
      gasprice_in_gwei: gaspriceOverride,
      outbound_display_in_gwei: outbound_in_gwei,
      cover_factor: COVER_FACTOR
    });

    // min density of at least 1 wei of outbound token
    density96X32 = density96X32 == 0 ? 1 << 32 : density96X32;
    console.log("With gasprice: %d gwei, cover factor:%d", gaspriceOverride, COVER_FACTOR);
    console.log(
      "Derived density %s %s per gas unit", toFixed(density96X32, outbound_decimals), IERC20(olKey.outbound).symbol()
    );

    broadcast();
    mgv.activate({olKey: olKey, fee: fee, density96X32: density96X32, offer_gasbase: gasbase});
  }

  function measureTransferGas(address tkn) public returns (uint) {
    address someone = freshAddress();
    vm.prank(someone);
    IERC20(tkn).approve(address(this), type(uint).max);
    deal(tkn, someone, 10);
    /* WARNING: gas metering is done by local execution, which means that on
     * networks that have different EIPs activated, there will be discrepancies. */
    uint post;
    uint pre = gasleft();
    IERC20(tkn).transferFrom(someone, address(this), 1);
    post = gasleft();
    return pre - post;
  }
}
