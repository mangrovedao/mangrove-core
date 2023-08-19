// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Test2, toFixed, Test, console, toString, vm} from "mgv_lib/Test2.sol";
import {TestTaker} from "mgv_test/lib/agents/TestTaker.sol";
import {TestSender} from "mgv_test/lib/agents/TestSender.sol";
import {TrivialTestMaker, TestMaker, OfferData} from "mgv_test/lib/agents/TestMaker.sol";
import {MakerDeployer} from "mgv_test/lib/agents/MakerDeployer.sol";
import {TestMoriartyMaker} from "mgv_test/lib/agents/TestMoriartyMaker.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {TransferLib} from "mgv_lib/TransferLib.sol";

import {AbstractMangrove} from "mgv_src/AbstractMangrove.sol";
import {MgvOfferTakingWithPermit} from "mgv_src/MgvOfferTakingWithPermit.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {InvertedMangrove} from "mgv_src/InvertedMangrove.sol";
import {
  IERC20,
  MgvLib,
  HasMgvEvents,
  IMaker,
  ITaker,
  IMgvMonitor,
  MgvStructs,
  Leaf,
  Field,
  Tick,
  LeafLib,
  FieldLib,
  TickLib
} from "mgv_src/MgvLib.sol";

struct Pair {
  AbstractMangrove mgv;
  MgvReader reader;
  address outbound_tkn;
  address inbound_tkn;
}

using PairLib for Pair global;

library PairLib {
  // function getPair
  function leafs(Pair memory pair, int index) internal view returns (Leaf) {
    return pair.mgv.leafs(pair.outbound_tkn, pair.inbound_tkn, index);
  }

  function offers(Pair memory pair, uint offerId) internal view returns (MgvStructs.OfferPacked) {
    return pair.mgv.offers(pair.outbound_tkn, pair.inbound_tkn, offerId);
  }

  function offerDetails(Pair memory pair, uint offerId) internal view returns (MgvStructs.OfferDetailPacked) {
    return pair.mgv.offerDetails(pair.outbound_tkn, pair.inbound_tkn, offerId);
  }

  function best(Pair memory pair) internal view returns (uint) {
    return pair.mgv.best(pair.outbound_tkn, pair.inbound_tkn);
  }

  function logTickTreeBranch(Pair memory pair) internal view {
    console.log("--------CURRENT TICK TREE BRANCH--------");
    MgvStructs.LocalPacked _local = pair.reader.local(pair.outbound_tkn, pair.inbound_tkn);
    Tick tick = _local.tick();
    console.log("Current tick %s", toString(tick));
    console.log("Current posInLeaf %s", tick.posInLeaf());
    int leafIndex = tick.leafIndex();
    console.log(
      "Current leaf %s (index %s)",
      toString(pair.mgv.leafs(pair.outbound_tkn, pair.inbound_tkn, leafIndex)),
      vm.toString(leafIndex)
    );
    console.log("Current level 0 %s (index %s)", toString(_local.level0()), vm.toString(tick.level0Index()));
    int level1Index = tick.level1Index();
    console.log(
      "Current level 1 %s (index %s)",
      toString(pair.mgv.level1(pair.outbound_tkn, pair.inbound_tkn, level1Index)),
      vm.toString(level1Index)
    );
    console.log("Current level 2 %s", toString(_local.level2()));
    console.log("----------------------------------------");
  }

  function nextOfferId(Pair memory pair, MgvStructs.OfferPacked offer) internal view returns (uint) {
    return pair.reader.nextOfferId(pair.outbound_tkn, pair.inbound_tkn, offer);
  }

  function nextOfferIdById(Pair memory pair, uint offerId) internal view returns (uint) {
    return pair.reader.nextOfferIdById(pair.outbound_tkn, pair.inbound_tkn, offerId);
  }

  function prevOfferId(Pair memory pair, MgvStructs.OfferPacked offer) internal view returns (uint) {
    return pair.reader.prevOfferId(pair.outbound_tkn, pair.inbound_tkn, offer);
  }

  function prevOfferIdById(Pair memory pair, uint offerId) internal view returns (uint) {
    return pair.reader.prevOfferIdById(pair.outbound_tkn, pair.inbound_tkn, offerId);
  }

  function level0(Pair memory pair, int index) internal view returns (Field) {
    return pair.mgv.level0(pair.outbound_tkn, pair.inbound_tkn, index);
  }

  function level1(Pair memory pair, int index) internal view returns (Field) {
    return pair.mgv.level1(pair.outbound_tkn, pair.inbound_tkn, index);
  }

  function level2(Pair memory pair) internal view returns (Field) {
    return pair.mgv.level2(pair.outbound_tkn, pair.inbound_tkn);
  }

  function local(Pair memory pair) internal view returns (MgvStructs.LocalPacked) {
    return pair.reader.local(pair.outbound_tkn, pair.inbound_tkn);
  }
}

/* *************************************************************** 
   import this file and inherit MangroveTest to get up and running 
   *************************************************************** */

/* This file is useful to:
 * auto-import all testing-useful contracts
 * inherit the standard forge-std/test.sol contract augmented with utilities & mangrove-specific functions
 */

contract MangroveTest is Test2, HasMgvEvents {
  // Configure the initial setup.
  // Add fields here to make MangroveTest more configurable.
  struct TokenOptions {
    string name;
    string symbol;
    uint8 decimals;
  }

  struct MangroveTestOptions {
    bool invertedMangrove;
    TokenOptions base;
    TokenOptions quote;
    uint defaultFee;
    uint gasprice;
    uint gasbase;
    uint gasmax;
    uint density;
  }

  AbstractMangrove internal mgv;
  TestMangrove internal testMgv; // FIXME: Temporary way to allows snipes in tests until all test have migrated to `clean` and `marketOrder`. See also TestMangrove further down.
  TestInvertedMangrove internal testInvertedMgv; // FIXME: Temporary way to allows snipes in tests until all test have migrated to `clean` and `marketOrder`. See also TestMangrove further down.
  MgvReader internal reader;
  TestToken internal base;
  TestToken internal quote;
  Pair pair; // base,quote pair
  Pair raip; // quote,base pair

  MangroveTestOptions internal options = MangroveTestOptions({
    invertedMangrove: false,
    base: TokenOptions({name: "Base Token", symbol: "$(A)", decimals: 18}),
    quote: TokenOptions({name: "Quote Token", symbol: "$(B)", decimals: 18}),
    defaultFee: 0,
    gasprice: 40,
    gasbase: 50_000,
    density: 10,
    gasmax: 2_000_000
  });

  constructor() {
    // generic trace labeling
    vm.label(tx.origin, "tx.origin");
    vm.label($(this), "Test runner");
  }

  /* Defaults:
  - testing contract has
    - 10 ETH funded in mangrove
  - new makers
    - have 100 ETH
  - new takers
    - have 100 ETH
  */
  function setUp() public virtual {
    // tokens
    base = new TestToken($(this), options.base.name, options.base.symbol, options.base.decimals);
    quote = new TestToken($(this), options.quote.name, options.quote.symbol, options.quote.decimals);
    // mangrove deploy
    mgv = setupMangrove(base, quote, options.invertedMangrove);

    reader = new MgvReader($(mgv));

    pair = Pair(mgv, reader, $(base), $(quote));
    raip = Pair(mgv, reader, $(quote), $(base));

    // below are necessary operations because testRunner acts as a taker/maker in some core protocol tests
    // TODO this should be done somewhere else
    //provision mangrove so that testRunner can post offers
    mgv.fund{value: 10 ether}();
    // approve mangrove so that testRunner can take offers on Mangrove
    TransferLib.approveToken(base, $(mgv), type(uint).max);
    TransferLib.approveToken(quote, $(mgv), type(uint).max);
  }

  /* Log order book */

  event OBState(
    address base, address quote, uint[] offerIds, uint[] wants, uint[] gives, address[] makerAddr, uint[] gasreqs
  );

  /**
   * Two different OB logging methods.
   *
   *  `logOrderBook` will be easy to read in traces
   *
   *  `printOrderBook` will be easy to read in the console.logs section
   */

  /* Log OB with events */
  event offers_head(address outbound, address inbound);
  event offers_line(uint id, uint wants, uint gives, address maker, uint gasreq);

  function logOrderBook(address $out, address $in, uint size) internal {
    uint offerId = mgv.best($out, $in);

    // save call results so logs are easier to read
    uint[] memory ids = new uint[](size);
    MgvStructs.OfferPacked[] memory offers = new MgvStructs.OfferPacked[](size);
    MgvStructs.OfferDetailPacked[] memory details = new MgvStructs.OfferDetailPacked[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      ids[c] = offerId;
      offers[c] = mgv.offers($out, $in, offerId);
      details[c] = mgv.offerDetails($out, $in, offerId);
      offerId = reader.nextOfferId($out, $in, offers[c]);
      c++;
    }
    c = 0;
    emit offers_head($out, $in);
    while (c < size) {
      emit offers_line(ids[c], offers[c].wants(), offers[c].gives(), details[c].maker(), details[c].gasreq());
      c++;
    }
    // emit OBState($out, $in, offerIds, wants, gives, makerAddr, gasreqs);
  }

  /* Log OB with console */
  function printOrderBook(address $out, address $in) internal view {
    uint offerId = mgv.best($out, $in);
    TestToken req_tk = TestToken($in);
    TestToken ofr_tk = TestToken($out);

    console.log(string.concat(unicode"┌────┬──Best offer: ", vm.toString(offerId), unicode"──────"));
    while (offerId != 0) {
      (MgvStructs.OfferUnpacked memory ofr, MgvStructs.OfferDetailUnpacked memory detail) =
        mgv.offerInfo($out, $in, offerId);
      console.log(
        string.concat(
          unicode"│ ",
          string.concat(offerId < 9 ? " " : "", vm.toString(offerId)), // breaks on id>99
          unicode" ┆ ",
          string.concat(toFixed(ofr.wants(), req_tk.decimals()), " ", req_tk.symbol()),
          "  /  ",
          string.concat(toFixed(ofr.gives, ofr_tk.decimals()), " ", ofr_tk.symbol()),
          " ",
          vm.toString(detail.maker)
        )
      );
      offerId = reader.nextOfferIdById($out, $in, offerId);
    }
    console.log(unicode"└────┴─────────────────────");
  }

  struct Balances {
    uint mgvBalanceWei;
    uint mgvBalanceBase;
    uint takerBalanceA;
    uint takerBalanceB;
    uint takerBalanceWei;
    uint[] makersBalanceA;
    uint[] makersBalanceB;
    uint[] makersBalanceWei;
  }

  enum Info {
    makerWants,
    makerGives,
    nextId,
    gasreqreceive_on,
    gasprice,
    gasreq
  }

  // Deploy mangrove
  function setupMangrove() public returns (AbstractMangrove) {
    return setupMangrove(false);
  }

  // Deploy mangrove, inverted or not
  function setupMangrove(bool inverted) public returns (AbstractMangrove _mgv) {
    if (inverted) {
      // FIXME: Remove once migration away from `snipes` has been completed
      _mgv = testInvertedMgv = new TestInvertedMangrove({
        governance: $(this),
        gasprice: options.gasprice,
        gasmax: options.gasmax
      });
      // _mgv = new InvertedMangrove({
      //   governance: $(this),
      //   gasprice: options.gasprice,
      //   gasmax: options.gasmax
      // });
    } else {
      // FIXME: Remove once migration away from `snipes` has been completed
      _mgv = testMgv = new TestMangrove({
        governance: $(this),
        gasprice: options.gasprice,
        gasmax: options.gasmax
      });
      // _mgv = new Mangrove({
      //   governance: $(this),
      //   gasprice: options.gasprice,
      //   gasmax: options.gasmax
      // });
    }
    vm.label($(_mgv), "Mangrove");
  }

  // Deploy mangrove with a pair
  function setupMangrove(IERC20 outbound_tkn, IERC20 inbound_tkn) public returns (AbstractMangrove) {
    return setupMangrove(outbound_tkn, inbound_tkn, false);
  }

  // Deploy mangrove with a pair, inverted or not
  function setupMangrove(IERC20 outbound_tkn, IERC20 inbound_tkn, bool inverted) public returns (AbstractMangrove _mgv) {
    _mgv = setupMangrove(inverted);
    setupMarket(address(outbound_tkn), address(inbound_tkn), _mgv);
  }

  function setupMarket(address $a, address $b, AbstractMangrove _mgv) internal {
    assertNot0x($a);
    assertNot0x($b);
    _mgv.activate($a, $b, options.defaultFee, options.density, options.gasbase);
    _mgv.activate($b, $a, options.defaultFee, options.density, options.gasbase);
    // logging
    vm.label($a, IERC20($a).symbol());
    vm.label($b, IERC20($b).symbol());
  }

  function setupMarket(address $a, address $b) internal {
    setupMarket($a, $b, mgv);
  }

  function setupMarket(IERC20 a, IERC20 b) internal {
    setupMarket(address(a), address(b), mgv);
  }

  function setupMaker(address $out, address $in, string memory label) public returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, IERC20($out), IERC20($in));
    vm.deal(address(tm), 100 ether);
    vm.label(address(tm), label);
    return tm;
  }

  function setupMakerDeployer(address $out, address $in) public returns (MakerDeployer) {
    assertNot0x($(mgv));
    return (new MakerDeployer(mgv, $out, $in));
  }

  function setupTaker(address $out, address $in, string memory label) public returns (TestTaker) {
    // FIXME: Temporary while migrating tests away from `snipes`
    // TestTaker tt = new TestTaker(mgv, IERC20($out), IERC20($in));
    TestTaker tt = new TestTaker(testMgv, IERC20($out), IERC20($in));
    vm.deal(address(tt), 100 ether);
    vm.label(address(tt), label);
    return tt;
  }

  function mockBuyOrder(uint takerGives, uint takerWants) public view returns (MgvLib.SingleOrder memory order) {
    order.outbound_tkn = $(base);
    order.inbound_tkn = $(quote);
    order.wants = takerWants;
    order.gives = takerGives;
    // complete fill (prev and next are bogus)
    order.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __wants: order.gives, __gives: order.wants});

    // order.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __tick: TickLib.tickFromVolumes(order.gives,order.wants), __gives: order.wants});
  }

  function mockBuyOrder(
    uint takerGives,
    uint takerWants,
    uint partialFill,
    IERC20 base_,
    IERC20 quote_,
    bytes32 makerData
  ) public pure returns (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) {
    order.outbound_tkn = $(base_);
    order.inbound_tkn = $(quote_);
    order.wants = takerWants;
    order.gives = takerGives;
    // complete fill (prev and next are bogus)
    order.offer = MgvStructs.Offer.pack({
      __prev: 0,
      __next: 0,
      __wants: order.gives * partialFill,
      __gives: order.wants * partialFill
    });
    result.makerData = makerData;
    result.mgvData = "mgv/tradeSuccess";
  }

  function mockSellOrder(uint takerGives, uint takerWants) public view returns (MgvLib.SingleOrder memory order) {
    order.inbound_tkn = $(base);
    order.outbound_tkn = $(quote);
    order.wants = takerWants;
    order.gives = takerGives;
    // complete fill (prev and next are bogus)
    order.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __wants: order.gives, __gives: order.wants});
  }

  function mockSellOrder(
    uint takerGives,
    uint takerWants,
    uint partialFill,
    IERC20 base_,
    IERC20 quote_,
    bytes32 makerData
  ) public pure returns (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) {
    order.inbound_tkn = $(base_);
    order.outbound_tkn = $(quote_);
    order.wants = takerWants;
    order.gives = takerGives;
    order.offer = MgvStructs.Offer.pack({
      __prev: 0,
      __next: 0,
      __wants: order.gives * partialFill,
      __gives: order.wants * partialFill
    });
    result.makerData = makerData;
    result.mgvData = "mgv/tradeSuccess";
  }

  /* **** Token conversion *** */
  /* Interpret amount as a user-friendly amount, convert to real underlying
   * amount using token decimals.
   * Example:
   * cash(usdc,1) = 1e6
   * cash(dai,1?) = 1e18
   */
  function cash(IERC20 t, uint amount) public returns (uint) {
    savePrank();
    uint decimals = t.decimals();
    restorePrank();
    return amount * 10 ** decimals;
  }

  /* Same as earlier, but divide result by 10**power */
  /* Useful to convert noninteger amounts, e.g.
     to convert 3.15 USDC, use cash(usdc,315,2) */
  function cash(IERC20 t, uint amount, uint power) public returns (uint) {
    return cash(t, amount) / 10 ** power;
  }

  /* **** Sugar for address conversion */
  function $(AbstractMangrove t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(TestTaker t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(Test t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(IERC20 t) internal pure returns (address payable) {
    return payable(address(t));
  }

  function $(TestSender t) internal pure returns (address payable) {
    return payable(address(t));
  }

  struct CheckAuthArgs {
    address[] allowed;
    address[] callers;
    address callee;
    string revertMessage;
  }

  function checkAuth(CheckAuthArgs memory args, bytes memory data) internal {
    checkAuth(args.allowed, args.callers, args.callee, args.revertMessage, data);
  }

  function checkAuth(
    address[] memory allowed,
    address[] memory callers,
    address callee,
    string memory revertMessage,
    bytes memory data
  ) internal {
    for (uint i = 0; i < callers.length; ++i) {
      bool skip = false;
      address caller = callers[i];
      for (uint j = 0; j < allowed.length; ++j) {
        if (allowed[j] == caller) {
          skip = true;
          break;
        }
      }
      if (skip) {
        continue;
      }
      vm.prank(caller);
      (bool success, bytes memory res) = callee.call(data);
      assertFalse(success, "function should revert");
      assertEq(revertMessage, getReason(res));
    }
    for (uint i = 0; i < allowed.length; i++) {
      vm.prank(allowed[i]);
      (bool success,) = callee.call(data);
      assertTrue(success, "function should not revert");
    }
  }

  /// creates `fold` offers in the (outbound, inbound) market with the same `wants`, `gives` and `gasreq` and with `caller` as maker
  function densify(address outbound, address inbound, uint wants, uint gives, uint gasreq, uint fold, address caller)
    internal
  {
    if (gives == 0) {
      return;
    }
    uint prov = reader.getProvision(outbound, inbound, gasreq, 0);
    while (fold > 0) {
      vm.prank(caller);
      mgv.newOfferByVolume{value: prov}(outbound, inbound, wants, gives, gasreq, 0);
      fold--;
    }
  }

  /// duplicates `fold` times all offers in the `outbound, inbound` list from id `fromId` and for `lenght` offers.
  function densifyRange(address outbound, address inbound, uint fromId, uint length, uint fold, address caller)
    internal
  {
    while (length > 0 && fromId != 0) {
      MgvStructs.OfferPacked offer = mgv.offers(outbound, inbound, fromId);
      MgvStructs.OfferDetailPacked detail = mgv.offerDetails(outbound, inbound, fromId);
      densify(outbound, inbound, offer.wants(), offer.gives(), detail.gasreq(), fold, caller);
      length--;
      fromId = reader.nextOfferId(outbound, inbound, offer);
    }
  }

  function assertEq(Leaf a, Leaf b) internal {
    if (!a.eq(b)) {
      emit log("Error: a == b not satisfied [Leaf]");
      emit log_named_string("      Left", toString(a));
      emit log_named_string("     Right", toString(b));
      fail();
    }
  }

  function assertEq(Leaf a, Leaf b, string memory err) internal {
    if (!a.eq(b)) {
      emit log_named_string("Error", err);
      assertEq(a, b);
    }
  }

  function assertEq(Field a, Field b) internal {
    if (!a.eq(b)) {
      emit log("Error: a == b not satisfied [Field]");
      emit log_named_string("      Left", toString(a));
      emit log_named_string("     Right", toString(b));
      fail();
    }
  }

  function assertEq(Field a, Field b, string memory err) internal {
    if (!a.eq(b)) {
      emit log_named_string("Error", err);
      assertEq(a, b);
    }
  }

  // logs an overview of the current branch
  function logTickTreeBranch(address outbound_tkn, address inbound_tkn) public view {
    Pair({mgv: mgv, reader: reader, outbound_tkn: outbound_tkn, inbound_tkn: inbound_tkn}).logTickTreeBranch();
  }
}

// FIXME: This is a temporary contract that will be removed once all tests are migrated away from the old `snipes`.
abstract contract TestSnipingMangrove is MgvOfferTakingWithPermit {
  // FIXME: The snipe code has been moved from MgvOfferTaking and MgvOfferTakingWithPermit w/o changes except renames of `snipes*` to `snipes*InTest`.
  /* The delegate version of `snipes` is `snipesFor`, which takes a `taker` address as additional argument. */
  function snipesForInTest(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants,
    address taker
  ) external returns (uint successes, uint takerGot, uint takerGave, uint bounty, uint feePaid) {
    unchecked {
      (successes, takerGot, takerGave, bounty, feePaid) =
        generalSnipes(outbound_tkn, inbound_tkn, targets, fillWants, taker);
      /* The sender's allowance is verified after the order complete so that the actual amounts are checked against the allowance, instead of the declared `takerGives`. The former may be lower.
    
    An immediate consequence is that any funds available to Mangrove through `approve` can be used to clean offers. After a `snipesFor` where all offers have failed, all token transfers have been reverted, so `takerGave=0` and the check will succeed -- but the sender will still have received the bounty of the failing offers. */
      deductSenderAllowance(outbound_tkn, inbound_tkn, taker, takerGave);
    }
  }

  /* `snipes` executes multiple offers. It takes a `uint[4][]` as penultimate argument, with each array element of the form `[offerId,tick,fillVolume,offerGasreq]`. The return parameters are of the form `(successes,snipesGot,snipesGave,bounty,feePaid)`. 
  Note that we do not distinguish further between mismatched arguments/offer fields on the one hand, and an execution failure on the other. Still, a failed offer has to pay a penalty, and ultimately transaction logs explicitly mention execution failures (see `MgvLib.sol`). */

  function snipesInTest(address outbound_tkn, address inbound_tkn, uint[4][] calldata targets, bool fillWants)
    external
    returns (uint, uint, uint, uint, uint)
  {
    unchecked {
      return generalSnipes(outbound_tkn, inbound_tkn, targets, fillWants, msg.sender);
    }
  }

  /*
     From an array of _n_ `[offerId, tick,fillVolume,gasreq]` elements, execute each snipe in sequence. Returns `(successes, takerGot, takerGave, bounty, feePaid)`. 

     Note that if this function is not internal, anyone can make anyone use Mangrove.
     Note that unlike general market order, the returned total values are _not_ `mor.totalGot` and `mor.totalGave`, since those are reset at every iteration of the `targets` array. Instead, accumulators `snipesGot` and `snipesGave` are used. */
  function generalSnipes(
    address outbound_tkn,
    address inbound_tkn,
    uint[4][] calldata targets,
    bool fillWants,
    address taker
  ) internal returns (uint successCount, uint snipesGot, uint snipesGave, uint totalPenalty, uint feePaid) {
    unchecked {
      MultiOrder memory mor;
      mor.taker = taker;
      mor.fillWants = fillWants;

      MgvLib.SingleOrder memory sor;
      sor.outbound_tkn = outbound_tkn;
      sor.inbound_tkn = inbound_tkn;
      Pair storage pair;
      (sor.global, sor.local, pair) = _config(outbound_tkn, inbound_tkn);

      /* For the snipes to even start, the market needs to be both active and not currently protected from reentrancy. */
      activeMarketOnly(sor.global, sor.local);
      unlockedMarketOnly(sor.local);

      // emit OrderStart();

      /* ### Main loop */
      //+clear+

      /* Call `internalSnipes` function. */
      (successCount, snipesGot, snipesGave) = internalSnipes(pair, mor, sor, targets);

      /* Over the course of the snipes order, a penalty reserved for `msg.sender` has accumulated in `mor.totalPenalty`. No actual transfers have occured yet -- all the ethers given by the makers as provision are owned by Mangrove. `sendPenalty` finally gives the accumulated penalty to `msg.sender`. */
      sendPenalty(mor.totalPenalty);
      //+clear+

      // emit OrderComplete(sor.outbound_tkn, sor.inbound_tkn, taker, snipesGot, snipesGave, mor.totalPenalty, mor.feePaid);
      totalPenalty = mor.totalPenalty;
      feePaid = mor.feePaid;
    }
  }

  /* ## Internal snipes */
  //+clear+
  /* `internalSnipes` works by looping over targets. Each successive offer is executed under a [reentrancy lock](#internalSnipes/liftReentrancy), then its posthook is called. Going upward, each offer's `maker` contract is called again with its remaining gas and given the chance to update its offers on the book. */
  function internalSnipes(
    Pair storage pair,
    MultiOrder memory mor,
    MgvLib.SingleOrder memory sor,
    uint[4][] calldata targets
  ) internal returns (uint successCount, uint snipesGot, uint snipesGave) {
    unchecked {
      for (uint i = 0; i < targets.length; ++i) {
        /* Reset these amounts since every snipe is treated individually. Only the total penalty is sent at the end of all snipes. */
        mor.totalGot = 0;
        mor.totalGave = 0;

        /* Initialize single order struct. */
        sor.offerId = targets[i][0];
        OfferData storage offerData = pair.offerData[sor.offerId];
        sor.offer = offerData.offer;
        sor.offerDetail = offerData.detail;

        /* If we removed the `isLive` conditional, a single expired or nonexistent offer in `targets` would revert the entire transaction (by the division by `offer.gives` below since `offer.gives` would be 0). We also check that `gasreq` is not worse than specified. A taker who does not care about `gasreq` can specify any amount larger than $2^{24}-1$. A mismatched price will be detected by `execute`. */
        if (!sor.offer.isLive() || sor.offerDetail.gasreq() > targets[i][3]) {
          /* We move on to the next offer in the array. */
          continue;
        } else {
          {
            Tick tick = Tick.wrap(int(targets[i][1]));
            require(TickLib.inRange(tick), "mgv/snipes/tick/outOfRange");
            mor.maxTick = tick;
          }
          {
            uint fillVolume = targets[i][2];
            require(uint96(fillVolume) == fillVolume, "mgv/snipes/volume/96bits");
            mor.fillVolume = fillVolume;
          }

          /* We start be enabling the reentrancy lock for this (`outbound_tkn`,`inbound_tkn`) pair. */
          sor.local = sor.local.lock(true);
          pair.local = sor.local;

          /* `execute` will adjust `sor.wants`,`sor.gives`, and may attempt to execute the offer if its price is low enough. It is crucial that an error due to `taker` triggers a revert. That way [`mgvData`](#MgvOfferTaking/statusCodes) not in `["mgv/tradeSuccess","mgv/notExecuted"]` means the failure is the maker's fault. */
          /* Post-execution, `sor.wants`/`sor.gives` reflect how much was sent/taken by the offer. */
          (uint gasused, bytes32 makerData, bytes32 mgvData) = execute(pair, mor, sor);

          if (mgvData == "mgv/tradeSuccess") {
            successCount += 1;
          }

          /* In the market order, we were able to avoid stitching back offers after every `execute` since we knew a continuous segment starting at best would be consumed. Here, we cannot do this optimisation since offers in the `targets` array may be anywhere in the book. So we stitch together offers immediately after each `execute`. */
          if (mgvData != "mgv/notExecuted") {
            // updates best&tick
            sor.local = dislodgeOffer(pair, sor.offer, sor.local, true);
          }

          /* <a id="internalSnipes/liftReentrancy"></a> Now that the current snipe is over, we can lift the lock on the book. In the same operation we
        * lift the reentrancy lock, and
        * update the storage

        so we are free from out of order storage writes.
        */
          sor.local = sor.local.lock(false);
          pair.local = sor.local;

          /* `payTakerMinusFees` keeps the fee in Mangrove, proportional to the amount purchased, and gives the rest to the taker */
          payTakerMinusFees(mor, sor);

          /* In an inverted Mangrove, amounts have been lent by each offer's maker to the taker. We now call the taker. This is a noop in a normal Mangrove. */
          executeEnd(mor, sor);

          /* After an offer execution, we may run callbacks and increase the total penalty. As that part is common to market orders and snipes, it lives in its own `postExecute` function. */
          if (mgvData != "mgv/notExecuted") {
            postExecute(mor, sor, gasused, makerData, mgvData);
          }

          snipesGot += mor.totalGot;
          snipesGave += mor.totalGave;
        }
      }
    }
  }
}

contract TestMangrove is Mangrove, TestSnipingMangrove {
  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {}
}

contract TestInvertedMangrove is InvertedMangrove, TestSnipingMangrove {
  constructor(address governance, uint gasprice, uint gasmax) InvertedMangrove(governance, gasprice, gasmax) {}
}
