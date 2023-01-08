// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  ExplicitKandel as Kandel,
  IERC20,
  IMangrove,
  AbstractKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/**
 * @notice Populate Kandel's distribution on Mangrove
 */

contract KdlPopulate is Deployer {
  function run() public {
    innerRun({
      from: vm.envUint("FROM"),
      to: vm.envUint("TO"),
      lastBidIndex: vm.envUint("LASTBID"),
      gasprice: vm.envUint("GASPRICE"),
      kdl: Kandel(envAddressOrName("KANDEL"))
    });
  }

  function innerRun(
    Kandel kdl,
    uint from, // start index for the first element of the distribution
    uint to,
    uint lastBidIndex,
    uint gasprice
  ) public {
    IMangrove MGV = kdl.MGV();
    MgvReader MGVR = MgvReader(fork.get("MgvReader"));
    IERC20 BASE = kdl.BASE();
    IERC20 QUOTE = kdl.QUOTE();

    require(from < to && to < kdl.NSLOTS(), "interval must be of the form [from,...,to[");

    uint gasreq = kdl.offerGasreq();
    uint provAsk = MGVR.getProvision(address(BASE), address(QUOTE), gasreq, gasprice);
    uint provBid = MGVR.getProvision(address(QUOTE), address(BASE), gasreq, gasprice);

    prettyLog("Evaluating pivots...");
    vm.startPrank(broadcaster());
    HeapVars memory ret = evaluatePivots(
      HeapArgs({
        baseDist: kdl.baseDist(),
        quoteDist: kdl.quoteDist(),
        lastBidIndex: lastBidIndex,
        provBid: provBid,
        provAsk: provAsk,
        kdl: kdl,
        mgv: MGV,
        base: address(BASE),
        quote: address(QUOTE)
      })
    );
    vm.stopPrank();

    prettyLog("Approving base and quote...");
    broadcast();
    BASE.approve(address(kdl), ret.baseProvision);
    broadcast();
    QUOTE.approve(address(kdl), ret.quoteProvision);

    prettyLog("Funding asks...");
    broadcast();
    kdl.depositFunds(AbstractKandel.OrderType.Ask, ret.baseProvision);
    console.log(toUnit(ret.baseProvision, BASE.decimals()), BASE.name(), "deposited");

    prettyLog("Funding bids...");
    broadcast();
    kdl.depositFunds(AbstractKandel.OrderType.Bid, ret.quoteProvision);
    console.log(toUnit(ret.quoteProvision, QUOTE.decimals()), QUOTE.name(), "deposited");

    prettyLog("Populating Mangrove...");
    broadcast();
    kdl.populate{value: (provAsk + provBid) * (to - from)}(from, to, lastBidIndex, gasprice, ret.pivotIds);
    console.log(toUnit((provAsk + provBid) * (to - from), 18), "eth used as provision");
    console.log("Interval:", from, lastBidIndex, to);
  }

  struct HeapArgs {
    uint96[] baseDist;
    uint96[] quoteDist;
    uint lastBidIndex;
    uint provBid;
    uint provAsk;
    Kandel kdl;
    IMangrove mgv;
    address base;
    address quote;
  }

  struct HeapVars {
    uint baseProvision;
    uint quoteProvision;
    uint[] pivotIds;
    bool bidding;
    uint snapshotId;
    uint lastOfferId;
  }

  function evaluatePivots(HeapArgs memory args) public returns (HeapVars memory vars) {
    vars.pivotIds = new uint[](args.baseDist.length);

    uint gasreq = args.kdl.offerGasreq();

    // will revert all the insertion to avoid changing the state of mangrove on the local node (might mess up tests)
    vars.snapshotId = vm.snapshot();
    for (uint i = 0; i < vars.pivotIds.length; i++) {
      vars.bidding = i <= args.lastBidIndex;
      (address outbound, address inbound) = vars.bidding ? (args.quote, args.base) : (args.base, args.quote);
      (uint wants, uint gives) =
        vars.bidding ? (args.baseDist[i], args.quoteDist[i]) : (args.quoteDist[i], args.baseDist[i]);
      if (gives > 0) {
        vars.lastOfferId = args.mgv.newOffer{value: vars.bidding ? args.provBid : args.provAsk}({
          outbound_tkn: outbound,
          inbound_tkn: inbound,
          wants: wants,
          gives: gives,
          gasreq: gasreq,
          gasprice: 0,
          pivotId: vars.lastOfferId
        });
        vars.pivotIds[i] = args.mgv.offers(outbound, inbound, vars.lastOfferId).next();
        if (vars.bidding) {
          vars.quoteProvision += gives;
        } else {
          vars.baseProvision += gives;
        }
      }
    }
    require(vm.revertTo(vars.snapshotId), "snapshot restore failed");
  }
}
