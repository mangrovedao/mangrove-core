// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console2 as console} from "forge-std/Script.sol";
import {Kandel, IERC20, IMangrove, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {CoreKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {AbstractKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/AbstractKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";

/**
 * @notice Populates Kandel's distribution on Mangrove
 */

/**
 * KANDEL=Kandel_WETH_USDC FROM=0 TO=100 FIRST_ASK_INDEX=50 PRICE_POINTS=100\
 *    RATIO=101 SPREAD=1 INIT_QUOTE=$(cast ff 6 100) VOLUME=$(cast ff 18 0.1)\
 *    forge script KandelPopulate --fork-url $LOCALHOST_URL --private-key $MUMBAI_PRIVATE_KEY --broadcast
 */

contract KandelPopulate is Deployer {
  function run() public {
    GeometricKandel kdl = Kandel(envAddressOrName("KANDEL"));
    Kandel.Params memory params;
    params.ratio = uint24(vm.envUint("RATIO"));
    require(params.ratio == vm.envUint("RATIO"), "Invalid RATIO");
    params.pricePoints = uint8(vm.envUint("PRICE_POINTS"));
    require(params.pricePoints == vm.envUint("PRICE_POINTS"), "Invalid PRICE_POINTS");
    params.spread = uint8(vm.envUint("SPREAD"));
    require(params.spread == vm.envUint("SPREAD"), "Invalid SPREAD");

    innerRun(
      HeapArgs({
        from: vm.envUint("FROM"),
        to: vm.envUint("TO"),
        firstAskIndex: vm.envUint("FIRST_ASK_INDEX"),
        params: params,
        initQuote: vm.envUint("INIT_QUOTE"),
        volume: vm.envUint("VOLUME"),
        kdl: kdl
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
    GeometricKandel kdl;
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
      args.params.compoundRateBase,
      args.params.compoundRateQuote,
      /*uint8 spread*/
      ,
      /*uint8 length*/
    ) = args.kdl.params();

    vars.provAsk = vars.mgvReader.getProvision(address(vars.BASE), address(vars.QUOTE), vars.gasreq, vars.gasprice);
    vars.provBid = vars.mgvReader.getProvision(address(vars.QUOTE), address(vars.BASE), vars.gasreq, vars.gasprice);
    uint funds = (vars.provAsk + vars.provBid) * (args.to - args.from);
    if (broadcaster().balance < funds) {
      console.log(
        "Broadcaster does not have enough funds to provision offers. Missing",
        toUnit(funds - broadcaster().balance, 18),
        "native tokens"
      );
      require(false, "Not enough funds");
    }

    prettyLog("Calculating base and quote...");
    vars.distribution = calculateBaseQuote(args);

    prettyLog("Evaluating pivots and required collateral...");
    evaluatePivots(vars.distribution, args, vars, funds);
    // after the above call, `vars.pivotIds` and `vars.base/quoteAmountRequired` are filled
    uint baseDecimals = vars.BASE.decimals();
    uint quoteDecimals = vars.QUOTE.decimals();
    prettyLog(
      string.concat(
        "Required collateral of base is ",
        toUnit(vars.baseAmountRequired, baseDecimals),
        " and quote is ",
        toUnit(vars.quoteAmountRequired, quoteDecimals)
      )
    );

    string memory deficit;

    if (vars.BASE.balanceOf(broadcaster()) < vars.baseAmountRequired) {
      deficit = string.concat(
        "Not enough base (",
        vm.toString(address(vars.BASE)),
        "). Deficit: ",
        toUnit(vars.baseAmountRequired - vars.BASE.balanceOf(broadcaster()), baseDecimals)
      );
    }
    if (vars.QUOTE.balanceOf(broadcaster()) < vars.quoteAmountRequired) {
      deficit = string.concat(
        bytes(deficit).length > 0 ? string.concat(deficit, ". ") : "",
        "Not enough quote (",
        vm.toString(address(vars.QUOTE)),
        "). Deficit: ",
        toUnit(vars.quoteAmountRequired - vars.QUOTE.balanceOf(broadcaster()), quoteDecimals)
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
      vars.baseAmountRequired,
      vars.quoteAmountRequired
    );
    console.log(toUnit(funds, 18), "native tokens used as provision");
  }

  function calculateBaseQuote(HeapArgs memory args) public view returns (CoreKandel.Distribution memory distribution) {
    distribution = KandelLib.calculateDistribution(
      args.from,
      args.to,
      args.volume,
      args.initQuote,
      args.params.ratio,
      args.kdl.PRECISION(),
      args.params.spread,
      args.firstAskIndex,
      args.kdl.PRICE_PRECISION(),
      args.params.pricePoints
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
    vm.startPrank(broadcaster());
    (vars.pivotIds, vars.baseAmountRequired, vars.quoteAmountRequired) = KandelLib.estimatePivotsAndRequiredAmount(
      distribution, GeometricKandel(args.kdl), args.firstAskIndex, args.params, funds
    );
    vm.stopPrank();
    require(vm.revertTo(vars.snapshotId), "snapshot restore failed");
  }
}
