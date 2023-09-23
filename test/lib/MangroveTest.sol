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
import {TickLib} from "mgv_lib/TickLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {
  IERC20,
  MgvLib,
  Tick,
  HasMgvEvents,
  IMaker,
  ITaker,
  IMgvMonitor,
  MgvStructs,
  Leaf,
  Field,
  Bin,
  LeafLib,
  FieldLib,
  BinLib,
  OLKey
} from "mgv_src/MgvLib.sol";

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
    uint defaultBinScale;
    uint gasprice;
    uint gasbase;
    uint gasmax;
    uint density96X32;
  }

  IMangrove internal mgv;
  MgvReader internal reader;
  TestToken internal base;
  TestToken internal quote;
  OLKey olKey; // base,quote
  OLKey lo; //quote,base

  MangroveTestOptions internal options = MangroveTestOptions({
    invertedMangrove: false,
    base: TokenOptions({name: "Base Token", symbol: "$(A)", decimals: 18}),
    quote: TokenOptions({name: "Quote Token", symbol: "$(B)", decimals: 18}),
    defaultFee: 0,
    defaultBinScale: 1,
    gasprice: 40,
    //Update `gasbase` by measuring using the test run `forge test --mc OfferGasBaseTest_Generic_A_B -vv`
    gasbase: 184048,
    density96X32: 2 ** 32,
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
    olKey = OLKey($(base), $(quote), options.defaultBinScale);
    lo = OLKey($(quote), $(base), options.defaultBinScale);

    mgv = setupMangrove(olKey, options.invertedMangrove);
    reader = new MgvReader($(mgv));

    // below are necessary operations because testRunner acts as a taker/maker in some core protocol tests
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
   *  `printOfferList` will be easy to read in the console.logs section
   */

  /* Log OB with events */
  event offers_head(address outbound, address inbound);
  event offers_line(uint id, uint wants, uint gives, address maker, uint gasreq);

  function logOrderBook(OLKey memory _ol, uint size) internal {
    uint offerId = mgv.best(_ol);

    // save call results so logs are easier to read
    uint[] memory ids = new uint[](size);
    MgvStructs.OfferPacked[] memory offers = new MgvStructs.OfferPacked[](size);
    MgvStructs.OfferDetailPacked[] memory details = new MgvStructs.OfferDetailPacked[](size);
    uint c = 0;
    while ((offerId != 0) && (c < size)) {
      ids[c] = offerId;
      (offers[c], details[c]) = mgv.offerData(_ol, offerId);
      offerId = reader.nextOfferId(_ol, offers[c]);
      c++;
    }
    c = 0;
    emit offers_head(olKey.outbound, olKey.inbound);
    while (c < size) {
      emit offers_line(ids[c], offers[c].wants(), offers[c].gives(), details[c].maker(), details[c].gasreq());
      c++;
    }
    // emit OBState(olKey.outbound, olKey.inbound, offerIds, wants, gives, makerAddr, gasreqs);
  }

  /* Log offer list to console */
  function printOfferList(OLKey memory _ol) internal view {
    uint offerId = mgv.best(_ol);
    TestToken req_tk = TestToken(_ol.inbound);
    TestToken ofr_tk = TestToken(_ol.outbound);

    console.log(string.concat(unicode"┌────┬──Best offer: ", vm.toString(offerId), unicode"──────"));
    while (offerId != 0) {
      (MgvStructs.OfferUnpacked memory ofr, MgvStructs.OfferDetailUnpacked memory detail) =
        reader.offerInfo(_ol, offerId);
      console.log(
        string.concat(
          unicode"│ ",
          string.concat(offerId <= 9 ? " " : "", vm.toString(offerId)), // breaks on id>99
          unicode" ┆ ",
          string.concat(toFixed(ofr.wants(), req_tk.decimals()), " ", req_tk.symbol()),
          "  /  ",
          string.concat(toFixed(ofr.gives, ofr_tk.decimals()), " ", ofr_tk.symbol()),
          string.concat(" (", toString(ofr.tick), ") "),
          vm.toString(detail.maker)
        )
      );
      offerId = reader.nextOfferIdById(_ol, offerId);
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
  function setupMangrove() public returns (IMangrove) {
    return setupMangrove(false);
  }

  // Deploy mangrove, inverted or not
  function setupMangrove(bool inverted) public returns (IMangrove _mgv) {
    if (inverted) {
      _mgv = IMangrove(
        $(
          new InvertedMangrove({
          governance: $(this),
          gasprice: options.gasprice,
          gasmax: options.gasmax
          })
        )
      );
    } else {
      _mgv = IMangrove(
        $(
          new Mangrove({
          governance: $(this),
          gasprice: options.gasprice,
          gasmax: options.gasmax
          })
        )
      );
    }
    vm.label($(_mgv), "Mangrove");
  }

  // Deploy mangrove with an offerList
  function setupMangrove(OLKey memory _ol) public returns (IMangrove) {
    return setupMangrove(_ol, false);
  }

  // Deploy mangrove with an offerList
  function setupMangrove(OLKey memory _ol, bool inverted) public returns (IMangrove _mgv) {
    _mgv = setupMangrove(inverted);
    setupMarket(IMangrove($(_mgv)), _ol);
  }

  function setupMarket(IMangrove _mgv, OLKey memory _ol) internal {
    assertNot0x(olKey.outbound);
    assertNot0x(olKey.inbound);
    _mgv.activate(_ol, options.defaultFee, options.density96X32, options.gasbase);
    _mgv.activate(lo, options.defaultFee, options.density96X32, options.gasbase);
    // logging
    vm.label(olKey.outbound, IERC20(olKey.outbound).symbol());
    vm.label(olKey.inbound, IERC20(olKey.inbound).symbol());
  }

  function setupMarket(OLKey memory _ol) internal {
    setupMarket(mgv, _ol);
  }

  function setupMaker(OLKey memory _ol, string memory label) public returns (TestMaker) {
    TestMaker tm = new TestMaker(mgv, _ol);
    vm.deal(address(tm), 100 ether);
    vm.label(address(tm), label);
    return tm;
  }

  function setupMakerDeployer(OLKey memory _ol) public returns (MakerDeployer) {
    assertNot0x($(mgv));
    return (new MakerDeployer(mgv, _ol));
  }

  function setupTaker(OLKey memory _ol, string memory label) public returns (TestTaker) {
    return setupTaker(_ol, label, mgv);
  }

  function setupTaker(OLKey memory _ol, string memory label, IMangrove _mgv) public returns (TestTaker) {
    TestTaker tt = new TestTaker(_mgv, _ol);
    vm.deal(address(tt), 100 ether);
    vm.label(address(tt), label);
    return tt;
  }

  function mockCompleteFillBuyOrder(uint takerWants, Tick tick) public view returns (MgvLib.SingleOrder memory sor) {
    sor.olKey = olKey;
    // complete fill (prev and next are bogus)
    sor.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __tick: tick, __gives: takerWants});
    sor.takerWants = sor.offer.gives();
    sor.takerGives = sor.offer.wants();
  }

  function mockPartialFillBuyOrder(
    uint takerWants,
    Tick tick,
    uint partialFill,
    OLKey memory _olBaseQuote,
    bytes32 makerData
  ) public pure returns (MgvLib.SingleOrder memory sor, MgvLib.OrderResult memory result) {
    sor.olKey = _olBaseQuote;
    sor.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __tick: tick, __gives: takerWants * partialFill});
    sor.takerWants = takerWants;
    sor.takerGives = TickLib.inboundFromOutboundUp(tick, takerWants);
    result.makerData = makerData;
    result.mgvData = "mgv/tradeSuccess";
  }

  function mockCompleteFillSellOrder(uint takerWants, Tick tick) public view returns (MgvLib.SingleOrder memory sor) {
    sor.olKey = lo;
    // complete fill (prev and next are bogus)
    sor.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __tick: tick, __gives: takerWants});
    sor.takerWants = sor.offer.gives();
    sor.takerGives = sor.offer.wants();
  }

  function mockPartialFillSellOrder(
    uint takerWants,
    Tick tick,
    uint partialFill,
    OLKey memory _olBaseQuote,
    bytes32 makerData
  ) public pure returns (MgvLib.SingleOrder memory sor, MgvLib.OrderResult memory result) {
    sor.olKey = _olBaseQuote.flipped();
    sor.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __tick: tick, __gives: takerWants * partialFill});
    sor.takerWants = takerWants;
    sor.takerGives = TickLib.inboundFromOutboundUp(tick, takerWants);
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

  function $(IMangrove t) internal pure returns (address payable) {
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

  /// creates `fold` offers in the (outbound, inbound) market with the same `tick`, `gives` and `gasreq` and with `caller` as maker
  function densify(OLKey memory _ol, Tick tick, uint gives, uint gasreq, uint fold, address caller) internal {
    if (gives == 0) {
      return;
    }
    uint prov = reader.getProvision(_ol, gasreq, 0);
    while (fold > 0) {
      vm.prank(caller);
      mgv.newOfferByTick{value: prov}(_ol, tick, gives, gasreq, 0);
      fold--;
    }
  }

  /// duplicates `fold` times all offers in the `outbound, inbound` list from id `fromId` and for `length` offers.
  function densifyRange(OLKey memory _ol, uint fromId, uint length, uint fold, address caller) internal {
    while (length > 0 && fromId != 0) {
      MgvStructs.OfferPacked offer = mgv.offers(_ol, fromId);
      MgvStructs.OfferDetailPacked detail = mgv.offerDetails(_ol, fromId);
      densify(_ol, offer.tick(), offer.gives(), detail.gasreq(), fold, caller);
      length--;
      fromId = reader.nextOfferId(_ol, offer);
    }
  }

  function assertEq(Tick a, Tick b) internal {
    if (!a.eq(b)) {
      emit log("Error: a == b not satisfied [TIck]");
      emit log_named_string("      Left", toString(a));
      emit log_named_string("     Right", toString(b));
      fail();
    }
  }

  function assertEq(Tick a, Tick b, string memory err) internal {
    if (!a.eq(b)) {
      emit log_named_string("Error", err);
      assertEq(a, b);
    }
  }

  function assertEq(Bin a, Bin b) internal {
    if (!a.eq(b)) {
      emit log("Error: a == b not satisfied [Bin]");
      emit log_named_string("      Left", toString(a));
      emit log_named_string("     Right", toString(b));
      fail();
    }
  }

  function assertEq(Bin a, Bin b, string memory err) internal {
    if (!a.eq(b)) {
      emit log_named_string("Error", err);
      assertEq(a, b);
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
  function logTickTreeBranch(OLKey memory _ol) public view {
    logTickTreeBranch(mgv, _ol);
  }

  function logTickTreeBranch(IMangrove _mgv, OLKey memory _ol) internal view {
    console.log("--------CURRENT tick tree BRANCH--------");
    MgvStructs.LocalPacked _local = _mgv.local(_ol);
    Bin bin = _local.bestBin();
    console.log("Current bin %s", toString(bin));
    console.log("Current posInLeaf %s", bin.posInLeaf());
    int leafIndex = bin.leafIndex();
    console.log("Current leaf %s (index %s)", toString(_mgv.leafs(_ol, leafIndex)), vm.toString(leafIndex));
    console.log("Current level 3 %s (index %s)", toString(_local.level3()), vm.toString(bin.level3Index()));
    console.log(
      "Current level 2 %s (index %s)", toString(_mgv.level2(_ol, bin.level2Index())), vm.toString(bin.level2Index())
    );
    console.log("Current level 1 %s (index %s)", toString(_local.level1()), vm.toString(bin.level1Index()));
    console.log("Current root %s", toString(_local.root()));
    console.log("----------------------------------------");
  }
}
