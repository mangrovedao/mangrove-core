// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice deploys a Kandel instance on a given market
 */

contract KandelStart is Deployer {
  Kandel public kdl;
  IMangrove MGV;
  IERC20 BASE;
  IERC20 QUOTE;

  function run() public {
    kdl = Kandel(envAddressOrName("KANDEL"));
    innerRun({
      baseDist: vm.envUint("BASEDIST", ","),
      quoteDist: vm.envUint("QUOTEDIST", ","),
      startPopulate: vm.envUint("START"),
      endPopulate: vm.envUint("END"),
      lastBidIndex: vm.envUint("LASTBID"),
      gasprice: vm.envUint("GASPRICE")
    });
  }

  function innerRun(
    uint[] memory baseDist,
    uint[] memory quoteDist,
    uint startPopulate,
    uint endPopulate,
    uint lastBidIndex,
    uint gasprice
  ) public {
    MGV = kdl.MGV();
    BASE = kdl.BASE();
    QUOTE = kdl.QUOTE();

    vm.broadcast();
    kdl.activate(dynamic([BASE, QUOTE]));

    uint provAsk = kdl.getMissingProvision(BASE, QUOTE, kdl.offerGasreq(), gasprice, 0);
    uint provBid = kdl.getMissingProvision(QUOTE, BASE, kdl.offerGasreq(), gasprice, 0);

    // assuming base and quote distributions have the same length <= kdl.NSLOTS()
    vm.broadcast();
    kdl.setDistribution(0, baseDist.length, [baseDist, quoteDist]);

    uint[] memory pivotIds = evaluatePivots(
      HeapArgs({
        baseDist: baseDist,
        quoteDist: quoteDist,
        lastBidIndex: int(lastBidIndex) - int(startPopulate),
        provBid: provBid,
        provAsk: provAsk
      })
    );

    vm.broadcast();
    kdl.populate{value: (provAsk + provBid) * (endPopulate - startPopulate)}(
      startPopulate, endPopulate, lastBidIndex, gasprice, pivotIds
    );
  }

  struct HeapArgs {
    uint[] baseDist;
    uint[] quoteDist;
    int lastBidIndex;
    uint provBid;
    uint provAsk;
  }

  function evaluatePivots(HeapArgs memory args) internal returns (uint[] memory pivotIds) {
    pivotIds = new uint[](args.baseDist.length);
    uint gasreq = kdl.offerGasreq();
    uint lastOfferId;

    for (uint i = 0; i < pivotIds.length; i++) {
      bool bidding = args.lastBidIndex >= 0 && i <= uint(args.lastBidIndex);
      (address outbound, address inbound) = bidding ? (address(QUOTE), address(BASE)) : (address(BASE), address(QUOTE));

      lastOfferId = MGV.newOffer{value: bidding ? args.provBid : args.provAsk}({
        outbound_tkn: outbound,
        inbound_tkn: inbound,
        wants: bidding ? args.baseDist[i] : args.quoteDist[i],
        gives: bidding ? args.quoteDist[i] : args.baseDist[i],
        gasreq: gasreq,
        gasprice: 0,
        pivotId: lastOfferId
      });
      pivotIds[i] = MGV.offers(outbound, inbound, lastOfferId).next();
    }
  }
}
