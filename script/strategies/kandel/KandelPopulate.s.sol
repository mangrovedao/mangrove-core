// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {Kandel, IERC20, IMangrove, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {CoreKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {AbstractKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandel.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";

/**
 * @notice Populates Kandel's distribution on Mangrove
 */

/*
  # The following uses ~12 million gas - with 0 pivots it uses ~30 million gas
  KANDEL=kdl5 FROM=0 TO=100 LAST_BID_INDEX=50 PRICE_POINTS=100 RATIO=10100 SPREAD=1 \
  INIT_QUOTE=$(cast ff 6 100) VOLUME=$(cast ff 18 0.1) \
  forge script KandelPopulate --fork-url $LOCAL_URL*/

contract KandelPopulate is Deployer {
  function run() public {
    Kandel.Params memory params;

    params.ratio = uint24(vm.envUint("RATIO"));
    require(params.ratio == vm.envUint("RATIO"), "Invalid RATIO");
    params.pricePoints = uint8(vm.envUint("PRICE_POINTS"));
    require(params.pricePoints == vm.envUint("PRICE_POINTS"), "Invalid PRICE_POINTS");
    params.spread = uint8(vm.envUint("SPREAD"));
    require(params.spread == vm.envUint("SPREAD"), "Invalid SPREAD");
    params.compoundRateBase = uint24(vm.envUint("COMPOUND_RATE_BASE"));
    require(params.compoundRateBase == vm.envUint("COMPOUND_RATE_BASE"), "Invalid COMPOUND_RATE_BASE");
    params.compoundRateQuote = uint24(vm.envUint("COMPOUND_RATE_QUOTE"));
    require(params.compoundRateQuote == vm.envUint("COMPOUND_RATE_QUOTE"), "Invalid COMPOUND_RATE_QUOTE");

    innerRun(
      HeapArgs({
        from: vm.envUint("FROM"),
        to: vm.envUint("TO"),
        firstAskIndex: vm.envUint("FIRST_ASK_INDEX"),
        params: params,
        initQuote: vm.envUint("INIT_QUOTE"),
        volume: vm.envUint("VOLUME"),
        kdl: Kandel(envAddressOrName("KANDEL"))
      })
    );
  }

  ///@notice Arguments for innerRun
  ///@param initQuote the amount of quote tokens that Kandel must want/give at `from` index
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param provBid the amount of provision (in native tokens) that are required to post a fresh bid
  ///@param provAsk the amount of provision (in native tokens) that are required to post a fresh ask
  ///@param kdl the Kandel instance
  ///@param mgv is kdl.MGV()
  ///@param base is kdl.BASE()
  ///@param quote is kdl.QUOTE()

  struct HeapArgs {
    uint from;
    uint to;
    uint firstAskIndex;
    Kandel.Params params;
    uint initQuote;
    uint volume;
    Kandel kdl;
  }

  struct HeapVars {
    CoreKandel.Distribution distribution;
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
      /*uint24 ratio*/
      ,
      /*uint24 compoundRateBase*/
      ,
      /*uint24 compoundRateQuote*/
      ,
      /*uint8 spread*/
      ,
      /*uint8 length*/
    ) = args.kdl.params();

    vars.provAsk = vars.mgvReader.getProvision(address(vars.BASE), address(vars.QUOTE), vars.gasreq, vars.gasprice);
    vars.provBid = vars.mgvReader.getProvision(address(vars.QUOTE), address(vars.BASE), vars.gasreq, vars.gasprice);
    uint funds = (vars.provAsk + vars.provBid) * (args.to - args.from);

    prettyLog("Calculating base and quote...");
    vars.distribution = calculateBaseQuote(args);

    prettyLog("Evaluating pivots and required collateral...");
    evaluatePivots(vars.distribution, args, vars, funds);
    // after the above call, `vars.pivotIds` and `vars.base/quoteAmountRequired` are filled
    prettyLog(
      string.concat(
        "Got required collateral of base=",
        vm.toString(vars.baseAmountRequired),
        " and quote=",
        vm.toString(vars.quoteAmountRequired)
      )
    );

    string memory deficit;

    if (vars.BASE.balanceOf(broadcaster()) < vars.baseAmountRequired) {
      deficit = string.concat(
        "Not enough base (",
        vm.toString(address(vars.BASE)),
        "). Deficit: ",
        vm.toString(vars.baseAmountRequired - vars.BASE.balanceOf(broadcaster()))
      );
    }
    if (vars.QUOTE.balanceOf(broadcaster()) < vars.quoteAmountRequired) {
      deficit = string.concat(
        bytes(deficit).length > 0 ? string.concat(deficit, ". ") : "",
        "Not enough quote (",
        vm.toString(address(vars.QUOTE)),
        "). Deficit: ",
        vm.toString(vars.quoteAmountRequired - vars.QUOTE.balanceOf(broadcaster()))
      );
    }
    if (bytes(deficit).length > 0) {
      deficit = string.concat("broadcaster: ", vm.toString(broadcaster()), " ", deficit);
      prettyLog(deficit);
      revert(deficit);
    }

    prettyLog("Approving base and quote...");
    broadcast();
    vars.BASE.approve(address(args.kdl), vars.baseAmountRequired);
    broadcast();
    vars.QUOTE.approve(address(args.kdl), vars.quoteAmountRequired);

    prettyLog("Populating Mangrove...");

    broadcast();

    args.kdl.populate{value: funds}(
      vars.distribution,
      vars.pivotIds,
      args.firstAskIndex,
      args.params,
      dynamic([IERC20(vars.BASE), vars.QUOTE]),
      dynamic([uint(vars.baseAmountRequired), vars.quoteAmountRequired])
    );
    console.log(toUnit(funds, 18), "eth used as provision");
  }

  function calculateBaseQuote(HeapArgs memory args) public view returns (CoreKandel.Distribution memory distribution) {
    (distribution, /* uint lastQuote */ ) = KandelLib.calculateDistribution(
      args.from, args.to, args.volume, args.initQuote, args.params.ratio, args.kdl.PRECISION()
    );
  }

  ///@notice evaluates Pivot ids for offers that need to be published on Mangrove
  ///@dev we use foundry cheats to revert all changes to the local node in order to prevent inconsistent tests.
  function evaluatePivots(
    CoreKandel.Distribution memory distribution,
    HeapArgs memory args,
    HeapVars memory vars,
    uint funds
  ) public {
    vars.snapshotId = vm.snapshot();
    vm.prank(broadcaster());
    (vars.pivotIds, vars.baseAmountRequired, vars.quoteAmountRequired) =
      KandelLib.estimatePivotsAndRequiredAmount(distribution, args.kdl, args.firstAskIndex, args.params, funds);
    require(vm.revertTo(vars.snapshotId), "snapshot restore failed");
  }
}
