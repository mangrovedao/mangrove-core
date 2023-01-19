// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  Kandel,
  IERC20,
  IMangrove,
  MgvStructs,
  AbstractKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlStatus is Deployer {
  function run() public view {
    innerRun({kdl: Kandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(Kandel kdl) public view {
    IERC20 base = kdl.BASE();
    IERC20 quote = kdl.QUOTE();
    uint baseDecimals = base.decimals();
    uint quoteDecimals = quote.decimals();
    uint nslots = kdl.length();

    for (uint i; i < nslots; i++) {
      (MgvStructs.OfferPacked ask,) = kdl.getOffer(AbstractKandel.OrderType.Ask, i);
      (MgvStructs.OfferPacked bid,) = kdl.getOffer(AbstractKandel.OrderType.Bid, i);

      if (ask.gives() > 0) {
        uint p = ask.wants() /*quote*/ * 10 ** baseDecimals / ask.gives(); /*base */
        console.log("ask @ %s for %d %s", toUnit(p, quoteDecimals), toUnit(ask.gives(), baseDecimals), base.symbol());
      } else {
        uint p = bid.gives() /*quote*/ * 10 ** baseDecimals / bid.wants(); /*base */
        console.log("bid @ %s for %d %s", toUnit(p, quoteDecimals), toUnit(bid.gives(), quoteDecimals), quote.symbol());
      }
    }
    console.log(
      "{",
      toUnit(uint(kdl.pending(AbstractKandel.OrderType.Ask)), baseDecimals),
      toUnit(uint(kdl.pending(AbstractKandel.OrderType.Bid)), quoteDecimals),
      "}"
    );
  }
}
