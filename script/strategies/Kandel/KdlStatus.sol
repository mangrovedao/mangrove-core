// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove,
  MgvStructs,
  AbstractKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlStatus is Deployer {
  function run() public {
    innerRun({kdl: Kandel(envAddressOrName("KANDEL"))});
  }

  function innerRun(Kandel kdl) public {
    uint96[] memory baseDist;
    uint96[] memory quoteDist;

    vm.prank(broadcaster());
    baseDist = kdl.baseDist();
    vm.prank(broadcaster());
    quoteDist = kdl.quoteDist();
    uint baseDecimals = kdl.BASE().decimals();
    uint quoteDecimals = kdl.QUOTE().decimals();
    uint p;
    for (uint i; i < baseDist.length; i++) {
      if (quoteDist[i] == 0 || baseDist[i] == 0) continue;
      p = uint(quoteDist[i]) * 10 ** baseDecimals / uint(baseDist[i]);
      (MgvStructs.OfferPacked ask,) = kdl.getOffer(AbstractKandel.OrderType.Ask, i);
      (MgvStructs.OfferPacked bid,) = kdl.getOffer(AbstractKandel.OrderType.Bid, i);
      string memory s_ask =
        ask.gives() > 0 ? (baseDist[i] == ask.gives() ? "\u001b[31ma\u001b[0m" : "\u001b[33ma\u001b[0m") : "\u2205";
      string memory s_bid =
        bid.gives() > 0 ? (quoteDist[i] == bid.gives() ? "\u001b[32mb\u001b[0m" : "\u001b[33mb\u001b[0m") : "\u2205";
      console.log("%s%s @ %s", s_ask, s_bid, toUnit(p, quoteDecimals));
    }
    console.log("{", toUnit(kdl.pendingBase(), baseDecimals), toUnit(kdl.pendingQuote(), quoteDecimals), "}");
  }
}
