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
 * @notice Populates Kandel's distribution on Mangrove
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

  ///@notice This function posts offer on Mangrove according to Kandel's price distribution. It also transfers necessary funds to cover offer gives.
  ///@param kdl the Kandel instance
  ///@param from the start price slot index
  ///@param to the end price slot index
  ///@param lastBidIndex all price slots after `from` and before this index (included) will be populated as Bids. Price slots after this index and before `to` (excluded) will be populated as Asks.
  function innerRun(Kandel kdl, uint from, uint to, uint lastBidIndex, uint gasprice) public {
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

  ///@notice Arguments for the `evaluatePivots` function
  ///@param baseDist the amount of base tokens that Kandel must want/give at each index
  ///@param quoteDist the amount of quote tokens that Kandel must want/give at each index
  ///@param lastBidIndex indexes before this (included) must bid when populated. Indexes after this must ask.
  ///@param provBid the amount of provision (in native tokens) that are required to post a fresh bid
  ///@param provAsk the amount of provision (in native tokens) that are required to post a fresh ask
  ///@param kdl the Kandel instance
  ///@param mgv is kdl.MGV()
  ///@param base is kdl.BASE()
  ///@param quote is kdl.QUOTE()
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
    uint gasreq;
  }

  ///@notice evaluates Pivot ids for offers that need to be published on Mangrove
  ///@dev we use foundry cheats to revert all changes to the local node in order to prevent inconsistent tests.
  function evaluatePivots(HeapArgs memory args) public returns (HeapVars memory vars) {
    vars.pivotIds = new uint[](args.baseDist.length);

    vars.gasreq = args.kdl.offerGasreq();

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
          gasreq: vars.gasreq,
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
