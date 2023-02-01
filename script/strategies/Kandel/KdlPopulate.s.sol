// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {Kandel, IERC20, IMangrove, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {AbstractKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandel.sol";
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
    uint16 ratio = uint16(vm.envUint("RATIO"));
    require(ratio == vm.envUint("RATIO"), "Invalid RATIO");
    uint8 kandelSize = uint8(vm.envUint("SIZE"));
    require(kandelSize == vm.envUint("SIZE"), "Invalid SIZE");
    uint8 spread = uint8(vm.envUint("SPREAD"));
    require(spread == vm.envUint("SPREAD"), "Invalid SPREAD");

    innerRun(
      HeapArgs({
        from: vm.envUint("FROM"),
        to: vm.envUint("TO"),
        lastBidIndex: vm.envUint("LAST_BID_INDEX"),
        kandelSize: kandelSize,
        ratio: ratio,
        spread: spread,
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
    uint8 kandelSize;
    uint16 ratio;
    uint8 spread;
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
    MgvReader mgvReader;
    IERC20 BASE;
    IERC20 QUOTE;
    uint provAsk;
    uint provBid;
  }

  function innerRun(HeapArgs memory args) public {
    HeapVars memory vars;

    vars.mgvReader = MgvReader(fork.get("MgvReader"));
    vars.BASE = args.kdl.BASE();
    vars.QUOTE = args.kdl.QUOTE();

    (
      vars.gasprice,
      vars.gasreq,
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

    vars.provAsk = vars.mgvReader.getProvision(address(vars.BASE), address(vars.QUOTE), vars.gasreq, vars.gasprice);
    vars.provBid = vars.mgvReader.getProvision(address(vars.QUOTE), address(vars.BASE), vars.gasreq, vars.gasprice);
    uint funds = (vars.provAsk + vars.provBid) * (args.to - args.from);

    prettyLog("Calculating base and quote...");
    KandelLib.Distribution memory distribution = calculateBaseQuote(args);

    prettyLog("Evaluating pivots and required collateral...");
    evaluatePivots(distribution, args, vars, funds);
    // after the above call, `vars.pivotIds` and `vars.base/quoteAmountRequired` are filled

    prettyLog("Approving base and quote...");
    broadcast();
    vars.BASE.approve(address(args.kdl), vars.baseAmountRequired);
    broadcast();
    vars.QUOTE.approve(address(args.kdl), vars.quoteAmountRequired);

    prettyLog("Funding asks...");
    broadcast();
    args.kdl.depositFunds(dynamic([IERC20(vars.BASE)]), dynamic([uint(vars.baseAmountRequired)]));
    console.log(toUnit(vars.baseAmountRequired, vars.BASE.decimals()), vars.BASE.name(), "deposited");

    prettyLog("Funding bids...");
    broadcast();
    args.kdl.depositFunds(dynamic([IERC20(vars.QUOTE)]), dynamic([uint(vars.quoteAmountRequired)]));
    console.log(toUnit(vars.quoteAmountRequired, vars.QUOTE.decimals()), vars.QUOTE.name(), "deposited");

    // baseDist is just uniform distribution here:
    uint[] memory baseDist = new uint[](args.to - args.from);
    for (uint i = 0; i < args.to - args.from; i++) {
      baseDist[i] = args.volume;
    }

    prettyLog("Populating Mangrove...");

    broadcast();
    args.kdl.populate{value: funds}(
      distribution.indices,
      distribution.baseDist,
      distribution.quoteDist,
      vars.pivotIds,
      args.lastBidIndex,
      args.kandelSize,
      args.ratio,
      args.spread
    );
    console.log(toUnit(funds, 18), "eth used as provision");
  }

  function calculateBaseQuote(HeapArgs memory args) public view returns (KandelLib.Distribution memory distribution) {
    (distribution, /* uint lastQuote */ ) =
      KandelLib.calculateDistribution(args.from, args.to, args.volume, args.initQuote, args.ratio, args.kdl.PRECISION());
  }

  ///@notice evaluates Pivot ids for offers that need to be published on Mangrove
  ///@dev we use foundry cheats to revert all changes to the local node in order to prevent inconsistent tests.
  function evaluatePivots(
    KandelLib.Distribution memory distribution,
    HeapArgs memory args,
    HeapVars memory vars,
    uint funds
  ) public {
    vars.snapshotId = vm.snapshot();
    (vars.pivotIds, vars.baseAmountRequired, vars.quoteAmountRequired) = KandelLib.estimatePivotsAndRequiredAmount(
      distribution, args.kdl, args.lastBidIndex, args.kandelSize, args.ratio, args.spread, funds
    );
    require(vm.revertTo(vars.snapshotId), "snapshot restore failed");
  }
}
