// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Test2} from "mgv_lib/Test2.sol";
import {console} from "forge-std/Test.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

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
      mgv: Mangrove(envAddressOrName("MGV", "Mangrove")),
      outbound_tkn: IERC20(envAddressOrName("OUTBOUND_TKN")),
      inbound_tkn: IERC20(envAddressOrName("INBOUND_TKN")),
      outbound_in_gwei: vm.envUint("OUTBOUND_IN_GWEI"),
      fee: vm.envUint("FEE")
    });
  }

  function innerRun(Mangrove mgv, IERC20 outbound_tkn, IERC20 inbound_tkn, uint outbound_in_gwei, uint fee) public {
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    innerRun(mgv, global.gasprice(), outbound_tkn, inbound_tkn, outbound_in_gwei, fee);
  }

  function innerRun(
    Mangrove mgv,
    uint gaspriceOverride, // the gasprice that is used to compute density. Can be set higher that mangrove's gasprice to avoid dust without impacting user's bounty
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint outbound_in_gwei,
    uint fee
  ) public {
    /*

    The gasbase is the gas spent by Mangrove to manage one order execution.  We
    approximate it to twice a taker->mgv->maker,maker->mgv->tkr transfer
    sequence.

    */
    uint outbound_gas = measureTransferGas(outbound_tkn);
    uint inbound_gas = measureTransferGas(inbound_tkn);
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
    uint outbound_decimals = outbound_tkn.decimals();
    uint density = (COVER_FACTOR * gaspriceOverride * 10 ** outbound_decimals) / outbound_in_gwei;
    // min density of at least 1 wei of outbound token
    density = density == 0 ? 1 : density;
    console.log("With gasprice: %d gwei, cover factor:%d", gaspriceOverride, COVER_FACTOR);
    console.log("Derived density %s %s per gas unit", toUnit(density, outbound_decimals), outbound_tkn.symbol());

    broadcast();
    mgv.activate({
      outbound_tkn: address(outbound_tkn),
      inbound_tkn: address(inbound_tkn),
      fee: fee,
      density: density,
      offer_gasbase: gasbase
    });
  }

  function measureTransferGas(IERC20 tkn) internal returns (uint) {
    address someone = freshAddress();
    vm.prank(someone);
    tkn.approve(address(this), type(uint).max);
    deal(address(tkn), someone, 10);
    /* WARNING: gas metering is done by local execution, which means that on
     * networks that have different EIPs activated, there will be discrepancies. */
    uint post;
    uint pre = gasleft();
    tkn.transferFrom(someone, address(this), 1);
    post = gasleft();
    return pre - post;
  }
}
