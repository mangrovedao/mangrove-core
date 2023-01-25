// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {
  Kandel, IERC20, IMangrove, AbstractKandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";

/**
 * @notice Populates Kandel's distribution on Mangrove
 */

/*
  FROM=0 TO=10 LAST_BID_INDEX=4 SIZE=10 RATIO=10100 SPREAD=1 INIT_QUOTE=$(cast ff 6 100) VOLUME=$(cast ff 18 0.1) \
  KANDEL=Kandel_WETH_USDC forge script KdlPopulate --fork-url $LOCALHOST_URL \
  --private-key $MUMBAI_TESTER_PRIVATE_KEY --broadcast*/

contract KdlPopulate is Deployer {
  function run() public {
    innerRun(
      HeapArgs({
        from: vm.envUint("FROM"),
        to: vm.envUint("TO"),
        lastBidIndex: vm.envUint("LAST_BID_INDEX"),
        kandelSize: vm.envUint("SIZE"),
        ratio: vm.envUint("RATIO"),
        spread: vm.envUint("SPREAD"),
        initQuote: vm.envUint("INIT_QUOTE"),
        volume: vm.envUint("VOLUME"),
        kdl: Kandel(envAddressOrName("KANDEL"))
      })
    );
  }

  ///@notice Arguments for innerRun
  ///@param initQuote the amount of quote tokens that Kandel must want/give at `from` index
  ///@param lastBidIndex indexes before this (included) must bid when populated. Indexes after this must ask.
  ///@param provBid the amount of provision (in native tokens) that are required to post a fresh bid
  ///@param provAsk the amount of provision (in native tokens) that are required to post a fresh ask
  ///@param kdl the Kandel instance
  ///@param mgv is kdl.MGV()
  ///@param base is kdl.BASE()
  ///@param quote is kdl.QUOTE()

  struct HeapArgs {
    uint from;
    uint to;
    uint lastBidIndex;
    uint kandelSize;
    uint ratio;
    uint spread;
    uint initQuote;
    uint volume;
    Kandel kdl;
  }

  struct HeapVars {
    uint baseAmountRequired;
    uint quoteAmountRequired;
    uint[] pivotIds;
    bool bidding;
    uint snapshotId;
    uint lastOfferId;
    uint gasreq;
    uint gasprice;
    IMangrove MGV;
    MgvReader MGVR;
    IERC20 BASE;
    IERC20 QUOTE;
    uint provAsk;
    uint provBid;
  }

  function innerRun(HeapArgs memory args) public {
    HeapVars memory vars;

    vars.MGV = IMangrove(fork.get("Mangrove"));
    vars.MGVR = MgvReader(fork.get("MgvReader"));
    vars.BASE = args.kdl.BASE();
    vars.QUOTE = args.kdl.QUOTE();

    (
      vars.gasprice,
      /*uint16 ratio*/
      ,
      /*uint16 compoundRateBase*/
      ,
      /*uint16 compoundRateQuote*/
      ,
      /*uint8 spread*/
      ,
      /*uint8 length*/
    ) = args.kdl.params();

    vars.gasreq = args.kdl.offerGasreq();
    vars.provAsk = vars.MGVR.getProvision(address(vars.BASE), address(vars.QUOTE), vars.gasreq, vars.gasprice);
    vars.provBid = vars.MGVR.getProvision(address(vars.QUOTE), address(vars.BASE), vars.gasreq, vars.gasprice);

    prettyLog("Evaluating pivots and required collateral...");
    evaluatePivots(args, vars);
    // after the above call, `vars.pivotIds` and `vars.base/quoteAmountRequired` are filled

    prettyLog("Approving base and quote...");
    broadcast();
    vars.BASE.approve(address(args.kdl), vars.baseAmountRequired);
    broadcast();
    vars.QUOTE.approve(address(args.kdl), vars.quoteAmountRequired);

    prettyLog("Funding asks...");
    broadcast();
    args.kdl.depositFunds(AbstractKandel.OfferType.Ask, vars.baseAmountRequired);
    console.log(toUnit(vars.baseAmountRequired, vars.BASE.decimals()), vars.BASE.name(), "deposited");

    prettyLog("Funding bids...");
    broadcast();
    args.kdl.depositFunds(AbstractKandel.OfferType.Bid, vars.quoteAmountRequired);
    console.log(toUnit(vars.quoteAmountRequired, vars.QUOTE.decimals()), vars.QUOTE.name(), "deposited");

    // baseDist is just uniform distribution here:
    uint[] memory baseDist = new uint[](args.to - args.from);
    for (uint i = 0; i < args.to - args.from; i++) {
      baseDist[i] = args.volume;
    }

    prettyLog("Populating Mangrove...");

    broadcast();
    uint funds = (vars.provAsk + vars.provBid) * (args.to - args.from);
    KandelLib.populate({
      kandel: args.kdl,
      from: args.from,
      to: args.to,
      lastBidIndex: args.lastBidIndex,
      kandelSize: args.kandelSize,
      ratio: uint16(args.ratio),
      spread: uint8(args.spread),
      initBase: args.volume, // base distribution in [from, to[
      initQuote: args.initQuote, // quote given/wanted at index from
      pivotIds: vars.pivotIds,
      funds: funds
    });
    console.log(toUnit(funds, 18), "eth used as provision");
  }

  ///@notice evaluates Pivot ids for offers that need to be published on Mangrove
  ///@dev we use foundry cheats to revert all changes to the local node in order to prevent inconsistent tests.
  function evaluatePivots(HeapArgs memory args, HeapVars memory vars) public {
    vars.pivotIds = new uint[](args.to - args.from);

    // will revert all the insertion to avoid changing the state of mangrove on the local node (might mess up tests)
    vars.snapshotId = vm.snapshot();
    uint quote_i = args.initQuote;
    for (uint i = 0; i < vars.pivotIds.length; i++) {
      vars.bidding = i <= args.lastBidIndex;
      (address outbound, address inbound) =
        vars.bidding ? (address(vars.QUOTE), address(vars.BASE)) : (address(vars.BASE), address(vars.QUOTE));

      (uint wants, uint gives) = vars.bidding ? (args.volume, quote_i) : (quote_i, args.volume);
      quote_i = (quote_i * args.ratio) / 10 ** 4;

      if (gives > 0) {
        vars.lastOfferId = vars.MGV.newOffer{value: vars.bidding ? vars.provBid : vars.provAsk}({
          outbound_tkn: outbound,
          inbound_tkn: inbound,
          wants: wants,
          gives: gives,
          gasreq: vars.gasreq,
          gasprice: 0,
          pivotId: vars.lastOfferId
        });
        vars.pivotIds[i] = vars.MGV.offers(outbound, inbound, vars.lastOfferId).next();
        if (vars.bidding) {
          vars.quoteAmountRequired += gives;
        } else {
          vars.baseAmountRequired += gives;
        }
      }
    }
    require(vm.revertTo(vars.snapshotId), "snapshot restore failed");
  }
}
