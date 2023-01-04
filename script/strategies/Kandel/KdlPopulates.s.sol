// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlPopulates is Deployer {
  Kandel public kdl;
  IMangrove MGV;
  IERC20 BASE;
  IERC20 QUOTE;
  MgvReader MGVR;

  function run() public {
    kdl = Kandel(envAddressOrName("KANDEL"));
    innerRun({
      from: vm.envUint("FROM"),
      to: vm.envUint("TO"),
      lastBidIndex: vm.envUint("LASTBID"),
      gasprice: vm.envUint("GASPRICE")
    });
  }

  function innerRun(
    uint from, // start index for the first element of the distribution
    uint to,
    uint lastBidIndex,
    uint gasprice
  ) public {
    MGV = kdl.MGV();
    MGVR = MgvReader(fork.get("MgvReader"));
    BASE = kdl.BASE();
    QUOTE = kdl.QUOTE();

    require(from < to && to < kdl.NSLOTS(), "interval must be of the form [from,...,to[");

    uint gasreq = kdl.offerGasreq();
    uint provAsk = MGVR.getProvision(address(BASE), address(QUOTE), gasreq, gasprice);
    uint provBid = MGVR.getProvision(address(QUOTE), address(BASE), gasreq, gasprice);

    prettyLog("Evaluating pivots");
    vm.startPrank(broadcaster());
    uint[] memory pivotIds = evaluatePivots(
      HeapArgs({
        baseDist: kdl.baseDist(),
        quoteDist: kdl.quoteDist(),
        lastBidIndex: lastBidIndex,
        provBid: provBid,
        provAsk: provAsk
      })
    );
    vm.stopPrank();

    prettyLog("Populating Mangrove...");
    vm.broadcast();
    kdl.populate{value: (provAsk + provBid) * (to - from)}(from, to, lastBidIndex, gasprice, pivotIds);
  }

  struct HeapArgs {
    uint96[] baseDist;
    uint96[] quoteDist;
    uint lastBidIndex;
    uint provBid;
    uint provAsk;
  }

  function evaluatePivots(HeapArgs memory args) internal returns (uint[] memory pivotIds) {
    pivotIds = new uint[](args.baseDist.length);
    uint gasreq = kdl.offerGasreq();
    uint lastOfferId;

    for (uint i = 0; i < pivotIds.length; i++) {
      bool bidding = i <= args.lastBidIndex;
      (address outbound, address inbound) = bidding ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));
      (uint wants, uint gives) = bidding ? (args.baseDist[i], args.quoteDist[i]) : (args.quoteDist[i], args.baseDist[i]);
      if (gives > 0) {
        lastOfferId = MGV.newOffer{value: bidding ? args.provBid : args.provAsk}({
          outbound_tkn: outbound,
          inbound_tkn: inbound,
          wants: wants,
          gives: gives,
          gasreq: gasreq,
          gasprice: 0,
          pivotId: lastOfferId
        });
        pivotIds[i] = MGV.offers(outbound, inbound, lastOfferId).next();
      }
      console.log(bidding ? "bid" : "ask", i, pivotIds[i], lastOfferId);
    }
  }
}
