// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvStructs, MgvLib} from "mgv_src/MgvLib.sol";
import {OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/TradesBaseQuotePair.sol";
import {CoreKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";
import {console} from "forge-std/Test.sol";
import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {AllMethodIdentifiersTest} from "mgv_test/lib/AllMethodIdentifiersTest.sol";

abstract contract CoreKandelTest is MangroveTest {
  address payable maker;
  address payable taker;
  GeometricKandel kdl;
  uint8 constant STEP = 1;
  uint initQuote;
  uint initBase = 0.1 ether;
  uint globalGasprice;
  uint bufferedGasprice;

  event Mgv(IMangrove mgv);
  event Pair(IERC20 base, IERC20 quote);
  event NewKandel(address indexed owner, IMangrove indexed mgv, IERC20 indexed base, IERC20 quote);
  event SetGeometricParams(uint spread, uint ratio);
  event SetCompoundRates(uint compoundRateBase, uint compoundRateQuote);
  event SetLength(uint value);
  event SetGasreq(uint value);
  event Credit(IERC20 indexed token, uint amount);
  event Debit(IERC20 indexed token, uint amount);
  event PopulateStart();
  event PopulateEnd();
  event RetractStart();
  event RetractEnd();
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  // sets base and quote
  function __setForkEnvironment__() internal virtual {
    // no fork
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;
    options.gasprice = 40;
    MangroveTest.setUp();
  }

  function setUp() public virtual override {
    /// sets base, quote, opens a market (base,quote) on Mangrove
    __setForkEnvironment__();
    require(reader != MgvReader(address(0)), "Could not get reader");

    initQuote = cash(quote, 100); // quote given/wanted at index from

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(base), taker, cash(base, 50));
    deal($(quote), taker, cash(quote, 70_000));

    // taker approves mangrove to be able to take offers
    vm.prank(taker);
    base.approve($(mgv), type(uint).max);
    vm.prank(taker);
    quote.approve($(mgv), type(uint).max);

    // deploy and activate
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    globalGasprice = global.gasprice();
    bufferedGasprice = globalGasprice * 10; // covering 10 times Mangrove's gasprice at deploy time

    kdl = __deployKandel__(maker, maker);

    // funding Kandel on Mangrove
    uint provAsk = reader.getProvision($(base), $(quote), kdl.offerGasreq(), bufferedGasprice);
    uint provBid = reader.getProvision($(quote), $(base), kdl.offerGasreq(), bufferedGasprice);
    deal(maker, (provAsk + provBid) * 10 ether);

    // maker approves Kandel to be able to deposit funds on it
    vm.prank(maker);
    base.approve(address(kdl), type(uint).max);
    vm.prank(maker);
    quote.approve(address(kdl), type(uint).max);

    uint24 ratio = uint24(108 * 10 ** kdl.PRECISION() / 100);

    CoreKandel.Distribution memory distribution1 = KandelLib.calculateDistribution(
      0, 5, initBase, initQuote, ratio, kdl.PRECISION(), STEP, 5, kdl.PRICE_PRECISION(), 10
    );

    CoreKandel.Distribution memory distribution2 = KandelLib.calculateDistribution(
      5, 10, initBase, initQuote, ratio, kdl.PRECISION(), STEP, 5, kdl.PRICE_PRECISION(), 10
    );

    GeometricKandel.Params memory params;
    params.ratio = ratio;
    params.spread = STEP;
    params.pricePoints = 10;
    vm.prank(maker);
    kdl.populate{value: (provAsk + provBid) * 10}(
      distribution1, dynamic([uint(0), 1, 2, 3, 4, 0, 1, 2, 3, 4]), 5, params, 0, 0
    );

    vm.prank(maker);
    kdl.populateChunk(distribution2, dynamic([uint(0), 1, 2, 3, 4]), 5);

    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);

    expectFrom($(kdl));
    emit Credit(base, pendingBase);
    expectFrom($(kdl));
    emit Credit(quote, pendingQuote);
    vm.prank(maker);
    kdl.depositFunds(pendingBase, pendingQuote);
  }

  function __deployKandel__(address deployer, address reserveId) internal virtual returns (GeometricKandel kdl_);

  function buyFromBestAs(address taker_, uint amount) public returns (uint, uint, uint, uint, uint) {
    uint bestAsk = mgv.best($(base), $(quote));
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([bestAsk, amount, type(uint96).max, type(uint).max]), true);
  }

  function sellToBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestBid = mgv.best($(quote), $(base));
    vm.prank(taker_);
    return mgv.snipes($(quote), $(base), wrap_dynamic([bestBid, 0, amount, type(uint).max]), false);
  }

  function offerIdOfIndex(CoreKandel kdl_, OfferType ba, uint index) internal view returns (uint offerId) {
    (offerId,) = kdl_.offerIdOfIndex(ba, index);
  }

  function snipeBuyAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = offerIdOfIndex(kdl, Ask, index);
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([offerId, amount, type(uint96).max, type(uint).max]), true);
  }

  function snipeSellAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = offerIdOfIndex(kdl, Bid, index);
    vm.prank(taker_);
    return mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
  }

  enum OfferStatus {
    Dead, // both dead
    Bid, // live bid
    Ask, // live ask
    Crossed // both live
  }

  ///@notice asserts status of index.
  function assertStatus(uint index, OfferStatus status) internal {
    assertStatus(index, status, type(uint).max, type(uint).max);
  }

  ///@notice asserts status of index and verifies price based on geometric progressing quote.
  function assertStatus(uint index, OfferStatus status, uint q, uint b) internal {
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index);
    bool bidLive = mgv.isLive(bid);
    bool askLive = mgv.isLive(ask);

    if (status == OfferStatus.Dead) {
      assertTrue(!bidLive && !askLive, "offer at index is live");
    } else {
      if (status == OfferStatus.Bid) {
        assertTrue(bidLive && !askLive, "Kandel not bidding at index");
        if (q != type(uint).max) {
          assertApproxEqRel(
            bid.gives() * b,
            q * bid.wants(),
            1e11,
            string.concat("Bid price does not follow distribution within 0.00001% index=", vm.toString(index))
          );
        }
      } else {
        if (status == OfferStatus.Ask) {
          assertTrue(!bidLive && askLive, "Kandel is not asking at index");
          if (q != type(uint).max) {
            assertApproxEqRel(
              ask.wants() * b,
              q * ask.gives(),
              1e11,
              string.concat("Ask price does not follow distribution within 0.00001% index=", vm.toString(index))
            );
          }
        } else {
          assertTrue(bidLive && askLive, "Kandel is not crossed at index");
        }
      }
    }
  }

  function assertStatus(
    uint[] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
  ) internal {
    assertStatus(offerStatuses, initQuote, initBase);
  }

  function assertStatus(
    uint[] memory offerStatuses, // 1:bid 2:ask 3:crossed 0:dead - see OfferStatus
    uint q, // initial quote at first price point, type(uint).max to ignore in verification
    uint b // initial base at first price point, type(uint).max to ignore in verification
  ) internal {
    uint expectedBids = 0;
    uint expectedAsks = 0;
    GeometricKandel.Params memory params = getParams(kdl);
    for (uint i = 0; i < offerStatuses.length; i++) {
      // `price = quote / initBase` used in assertApproxEqRel below
      OfferStatus offerStatus = OfferStatus(offerStatuses[i]);
      assertStatus(i, offerStatus, q, b);
      if (q != type(uint).max) {
        q = (q * uint(params.ratio)) / (10 ** kdl.PRECISION());
      }
      if (offerStatus == OfferStatus.Ask) {
        expectedAsks++;
      } else if (offerStatus == OfferStatus.Bid) {
        expectedBids++;
      } else if (offerStatus == OfferStatus.Crossed) {
        expectedAsks++;
        expectedBids++;
      }
    }

    (, uint[] memory bidIds,,) = reader.offerList(address(quote), address(base), 0, 1000);
    (, uint[] memory askIds,,) = reader.offerList(address(base), address(quote), 0, 1000);
    assertEq(expectedBids, bidIds.length, "Unexpected number of live bids on book");
    assertEq(expectedAsks, askIds.length, "Unexpected number of live asks on book");
  }

  function printOB() internal view {
    printOrderBook($(base), $(quote));
    printOrderBook($(quote), $(base));
    uint pendingBase = uint(kdl.pending(Ask));
    uint pendingQuote = uint(kdl.pending(Bid));

    console.log("-------", toUnit(pendingBase, 18), toUnit(pendingQuote, 6), "-------");
  }

  OfferType constant Ask = OfferType.Ask;
  OfferType constant Bid = OfferType.Bid;

  function test_init() public {
    assertEq(kdl.pending(Ask), kdl.pending(Bid), "Incorrect initial pending");
    assertEq(kdl.pending(Ask), 0, "Incorrect initial pending");
  }

  function full_compound() internal view returns (uint24) {
    return uint24(10 ** kdl.PRECISION());
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_bid_complete_fill_compound_1() public {
    test_bid_complete_fill(full_compound(), 0);
  }

  function test_bid_complete_fill_compound_0() public {
    test_bid_complete_fill(0, full_compound());
  }

  function test_bid_complete_fill_compound_half() public {
    test_bid_complete_fill(5_000, full_compound());
  }

  function test_ask_complete_fill_compound_1() public {
    test_ask_complete_fill(0, full_compound());
  }

  function test_ask_complete_fill_compound_0() public {
    test_ask_complete_fill(full_compound(), 0);
  }

  function test_ask_complete_fill_compound_half() public {
    test_ask_complete_fill(0, full_compound() / 2);
  }

  function test_bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote) public {
    test_bid_complete_fill(compoundRateBase, compoundRateQuote, 4);
  }

  function precisionForAssert() internal pure virtual returns (uint);

  function test_bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index) internal {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateQuote <= full_compound());
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldAsk = kdl.getOffer(Ask, index + STEP);
    int oldPending = kdl.pending(Ask);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = sellToBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newAsk = kdl.getOffer(Ask, index + STEP);
    assertTrue(newAsk.gives() <= takerGave + oldAsk.gives(), "Cannot give more than what was received");
    int pendingDelta = kdl.pending(Ask) - oldPending;
    // Allow a discrepancy of 1 for aave router shares
    assertApproxEqAbs(
      pendingDelta + int(newAsk.gives()),
      int(oldAsk.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );
    if (compoundRateBase == full_compound()) {
      assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "Full compounding should not yield pending");
      assertTrue(newAsk.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
    }
  }

  function test_ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote) public {
    test_ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
  }

  function test_update_compoundRateQuote(uint24 compoundRateQuote) public {
    vm.assume(compoundRateQuote <= full_compound());
    vm.assume(compoundRateQuote > 0);

    GeometricKandel.Params memory params = getParams(kdl);
    // taking ask #5
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);
    // updates bid #4
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants(),
      takerWants: ask.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = offerIdOfIndex(kdl, Ask, 5);
    order.offer = ask;

    MgvStructs.OfferPacked bid_;
    uint gives_for_0;
    uint snapshotId = vm.snapshot();
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    bid_ = kdl.getOffer(Bid, 4);
    gives_for_0 = bid_.gives();
    require(vm.revertTo(snapshotId), "snapshot restore failed");

    // at 0% compounding, one wants to buy back what was sent
    // computation might have rounding error because bid_.wants is derived from bid_.gives
    console.log(bid_.wants(), bid.wants(), ask.gives());
    assertApproxEqRel(bid_.wants(), bid.wants() + ask.gives(), 10 ** 10, "Incorrect wants when 0% compounding");

    // changing compoundRates
    vm.prank(maker);
    kdl.setCompoundRates(params.compoundRateBase, compoundRateQuote);
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);

    bid_ = kdl.getOffer(Bid, 4);
    if (compoundRateQuote == full_compound()) {
      // 100% compounding, one gives what one got
      assertEq(bid_.gives(), bid.gives() + ask.wants(), "Incorrect gives when 100% compounding");
    } else {
      // in between one just checks that one is giving more than before
      assertTrue(bid_.gives() > gives_for_0, "Incorrect gives compounding");
    }
  }

  function test_update_compoundRateBase(uint24 compoundRateBase) public {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateBase > 0);

    GeometricKandel.Params memory params = getParams(kdl);
    // taking bid #4
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);
    // updates ask #5
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = offerIdOfIndex(kdl, Bid, 4);
    order.offer = bid;

    MgvStructs.OfferPacked ask_;
    uint gives_for_0;
    uint snapshotId = vm.snapshot();
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    ask_ = kdl.getOffer(Ask, 5);
    gives_for_0 = ask_.gives();
    require(vm.revertTo(snapshotId), "snapshot restore failed");

    // at 0% compounding, one wants to buy back what was sent
    // computation might have rounding error because ask_.wants is derived from ask_.gives
    console.log(ask_.wants(), ask.wants(), bid.gives());
    assertEq(ask_.wants(), ask.wants() + bid.gives(), "Incorrect wants when 0% compounding");

    // changing compoundRates
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, params.compoundRateQuote);
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);

    ask_ = kdl.getOffer(Ask, 5);
    if (compoundRateBase == full_compound()) {
      // 100% compounding, one gives what one got
      assertEq(ask_.gives(), ask.gives() + bid.wants(), "Incorrect gives when 100% compounding");
    } else {
      // in between one just checks that one is giving more than before
      assertTrue(ask_.gives() > gives_for_0, "Incorrect gives compounding");
    }
  }

  function test_ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index) internal {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateQuote <= full_compound());
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldBid = kdl.getOffer(Bid, index - STEP);
    int oldPending = kdl.pending(Bid);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = buyFromBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newBid = kdl.getOffer(Bid, index - STEP);
    assertTrue(newBid.gives() <= takerGave + oldBid.gives(), "Cannot give more than what was received");
    int pendingDelta = kdl.pending(Bid) - oldPending;
    assertApproxEqAbs(
      pendingDelta + int(newBid.gives()),
      int(oldBid.gives() + takerGave),
      precisionForAssert(),
      "Incorrect net promised asset"
    );
    if (compoundRateQuote == full_compound()) {
      assertApproxEqAbs(pendingDelta, 0, precisionForAssert(), "Full compounding should not yield pending");
      assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
    }
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill() public {
    (uint successes, uint takerGot,,,) = buyFromBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill_existingDual() public {
    partial_fill(Ask, true);
  }

  function test_bid_partial_fill_existingDual() public {
    partial_fill(Bid, true);
  }

  function test_ask_partial_fill_noDual() public {
    partial_fill(Ask, false);
  }

  function test_bid_partial_fill_noDual() public {
    partial_fill(Bid, false);
  }

  function testFail_ask_partial_fill_noDual_noIncident() public {
    vm.expectEmit(false, false, false, false, $(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, 0, "", "");
    partial_fill(Ask, false);
  }

  function partial_fill(OfferType ba, bool existingDual) internal {
    // Arrange
    uint successes;
    uint takerGot;
    if (!existingDual) {
      // Completely fill dual
      (successes, takerGot,,,) = ba == Bid ? buyFromBestAs(taker, 1000 ether) : sellToBestAs(taker, 1000 ether);
      assertTrue(successes == 1 && takerGot > 0, "Snipe of dual failed");
    }

    // Act
    (successes, takerGot,,,) = ba == Ask ? buyFromBestAs(taker, 1 wei) : sellToBestAs(taker, 1 wei);

    // Assert
    assertTrue(successes == 1, "Snipe failed");
    if (ba == Ask) {
      // taker gets nothing for Bid due to sending so little and rounding
      assertTrue(takerGot > 0, "Taker did not get expected");
    }
    if (existingDual) {
      // a tiny bit ends up as pending - but all offers still live
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    } else {
      // the dual offer could not be made live due to too little transported - but residual still reposted
      if (ba == Ask) {
        assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      } else {
        assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      }
    }
  }

  function test_all_bids_all_asks_and_back() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    vm.prank(taker);
    mgv.marketOrder($(base), $(quote), type(uint96).max, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]));
    vm.prank(taker);
    mgv.marketOrder($(quote), $(base), 1 ether, type(uint96).max, false);
    assertStatus(dynamic([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]));
    uint askVol = kdl.offeredVolume(Ask);
    vm.prank(taker);
    mgv.marketOrder($(base), $(quote), askVol / 2, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_take_new_offer() public {
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    assertStatus(dynamic([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_retractOffers() public {
    uint preBalance = maker.balance;
    uint preMgvBalance = mgv.balanceOf(address(kdl));

    expectFrom($(kdl));
    emit RetractStart();
    expectFrom($(mgv));
    emit OfferRetract(address(quote), address(base), offerIdOfIndex(kdl, Bid, 0));
    expectFrom($(kdl));
    emit RetractEnd();

    vm.prank(maker);
    kdl.retractOffers(0, 5);
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    assertEq(0, kdl.offeredVolume(Ask), "All ask volume should be retracted");
    assertEq(0, kdl.offeredVolume(Bid), "All bid volume should be retracted");
    assertGt(mgv.balanceOf(address(kdl)), preMgvBalance, "Kandel should have balance on mgv after retract");
    assertEq(maker.balance, preBalance, "maker should not be credited yet");

    vm.prank(maker);
    kdl.withdrawFromMangrove(type(uint).max, maker);
    assertGt(maker.balance, preBalance, "maker should be credited");
  }

  enum ExpectedChange {
    Same,
    Increase,
    Decrease
  }

  function assertChange(ExpectedChange expectedChange, uint expected, uint actual, string memory descriptor) internal {
    if (expectedChange == ExpectedChange.Same) {
      assertApproxEqRel(expected, actual, 1e11, string.concat(descriptor, " should be unchanged to within 0.00001%"));
    } else if (expectedChange == ExpectedChange.Decrease) {
      assertGt(expected, actual, string.concat(descriptor, " should have decreased"));
    } else {
      assertLt(expected, actual, string.concat(descriptor, " should have increased"));
    }
  }

  function test_take_full_bid_and_ask_repeatedly(
    uint loops,
    uint24 compoundRateBase,
    uint24 compoundRateQuote,
    ExpectedChange baseVolumeChange,
    ExpectedChange quoteVolumeChange
  ) internal {
    deal($(base), taker, cash(base, 5000));
    deal($(quote), taker, cash(quote, 7000000));
    uint initialTotalVolumeBase;
    uint initialTotalVolumeQuote;
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    for (uint i = 0; i < loops; i++) {
      test_ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      if (i == 0) {
        // With the ask filled, what is the current volume for bids?
        initialTotalVolumeQuote = kdl.offeredVolume(Bid);
        console.log("Initial bids");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(quoteVolumeChange, initialTotalVolumeQuote, kdl.offeredVolume(Bid), "quote volume");
        console.log("Final bids");
        printOB();
      }

      test_bid_complete_fill(compoundRateBase, compoundRateQuote, 4);

      assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      if (i == 0) {
        // With the bid filled, what is the current volume for asks?
        initialTotalVolumeBase = kdl.offeredVolume(Ask);
        console.log("Initial asks");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(baseVolumeChange, initialTotalVolumeBase, kdl.offeredVolume(Ask), "base volume");
        console.log("Final asks");
        printOB();
      }
    }
  }

  function test_take_full_bid_and_ask_10_times_full_compound() public {
    test_take_full_bid_and_ask_repeatedly(
      10, full_compound(), full_compound(), ExpectedChange.Increase, ExpectedChange.Increase
    );
  }

  function test_take_full_bid_and_ask_10_times_zero_quote_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, full_compound(), 0, ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_zero_base_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 0, full_compound(), ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_close_to_zero_base_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 1, full_compound(), ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_increasing_boundary() public {
    test_take_full_bid_and_ask_repeatedly(10, 49040, 49040, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_decreasing_boundary() public {
    test_take_full_bid_and_ask_repeatedly(10, 49030, 49030, ExpectedChange.Decrease, ExpectedChange.Decrease);
  }

  function test_take_full_bid_and_ask_10_times_zero_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 0, 0, ExpectedChange.Decrease, ExpectedChange.Decrease);
  }

  function retractDefaultSetup() internal {
    uint baseFunds = kdl.offeredVolume(Ask) + uint(kdl.pending(Ask));
    uint quoteFunds = kdl.offeredVolume(Bid) + uint(kdl.pending(Bid));
    vm.prank(maker);
    kdl.retractAndWithdraw(0, 10, baseFunds, quoteFunds, type(uint).max, maker);
  }

  function test_reserveBalance_withoutOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function populateFixedDistribution() internal {
    uint pricePrecision = kdl.PRICE_PRECISION();
    CoreKandel.Distribution memory distribution;
    distribution.indices = dynamic([uint(0), 1, 2, 3]);
    distribution.gives = dynamic([uint(5 ether), 6 ether, 3 ether, 4 ether]);
    distribution.prices = dynamic(
      [
        (uint(5 ether) * pricePrecision) / (1 ether),
        ((6 ether) * pricePrecision) / (2 ether),
        ((7 ether) * pricePrecision) / (3 ether),
        ((8 ether) * pricePrecision) / (5 ether)
      ]
    );
    distribution.dualPrices = distribution.prices;

    GeometricKandel.Params memory params = getParams(kdl);
    vm.prank(maker);
    kdl.populate{value: maker.balance}(distribution, new uint[](4), 2, params, 0, 0);
  }

  function test_reserveBalance_withOffers_returnsFundAmount() public {
    // Arrange
    retractDefaultSetup();
    populateFixedDistribution();

    assertEq(kdl.reserveBalance(Ask), 0, "Base balance should be empty");
    assertEq(kdl.reserveBalance(Bid), 0, "Quote balance should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.reserveBalance(Ask), 42, "Base balance should be correct");
    assertEq(kdl.reserveBalance(Bid), 43, "Quote balance should be correct");
  }

  function test_offeredVolume_withOffers_returnsSumOfGives() public {
    // Arrange
    retractDefaultSetup();

    populateFixedDistribution();

    // Act/assert
    assertEq(kdl.offeredVolume(Bid), 5 ether + 6 ether, "Bid volume should be sum of quote dist");
    assertEq(kdl.offeredVolume(Ask), 3 ether + 4 ether, "Ask volume should be sum of quote dist");
  }

  function test_pending_withoutOffers_returnsReserveBalance() public {
    // Arrange
    retractDefaultSetup();
    assertEq(kdl.pending(Ask), 0, "Base pending should be empty");
    assertEq(kdl.pending(Bid), 0, "Quote pending should be empty");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    // Act/assert
    assertEq(kdl.pending(Ask), 42, "Base pending should be correct");
    assertEq(kdl.pending(Bid), 43, "Quote pending should be correct");
  }

  function test_pending_withOffers_disregardsOfferedVolume() public {
    // Arrange
    retractDefaultSetup();
    populateFixedDistribution();

    assertEq(-kdl.pending(Ask), 3 ether + 4 ether, "Base pending should be correct");
    assertEq(-kdl.pending(Bid), 5 ether + 6 ether, "Quote pending should be correct");

    vm.prank(maker);
    kdl.depositFunds(42, 43);

    assertEq(-kdl.pending(Ask), 3 ether + 4 ether - 42, "Base pending should be correct");
    assertEq(-kdl.pending(Bid), 5 ether + 6 ether - 43, "Quote pending should be correct");
  }

  function test_populate_allBids_successful() public {
    test_populate_allBidsAsks_successful(true);
  }

  function test_populate_allAsks_successful() public {
    test_populate_allBidsAsks_successful(false);
  }

  function test_populate_allBidsAsks_successful(bool bids) internal {
    retractDefaultSetup();

    CoreKandel.Distribution memory distribution;
    uint pricePrecision = kdl.PRICE_PRECISION();
    distribution.indices = dynamic([uint(0), 1, 2, 3]);
    distribution.gives = dynamic([uint(1 ether), 1 ether, 1 ether, 1 ether]);
    distribution.prices = dynamic([pricePrecision, pricePrecision, pricePrecision, pricePrecision]);
    distribution.dualPrices = dynamic([pricePrecision, pricePrecision, pricePrecision, pricePrecision]);

    uint firstAskIndex = bids ? 4 : 0;
    vm.prank(maker);
    mgv.fund{value: maker.balance}($(kdl));
    vm.prank(maker);
    kdl.populateChunk(distribution, new uint[](4), firstAskIndex);

    uint status = bids ? uint(OfferStatus.Bid) : uint(OfferStatus.Ask);
    assertStatus(dynamic([status, status, status, status]), type(uint).max, type(uint).max);
  }

  function getBestOffers() internal view returns (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) {
    uint bestAskId = mgv.best($(base), $(quote));
    uint bestBidId = mgv.best($(quote), $(base));
    bestBid = mgv.offers($(quote), $(base), bestBidId);
    bestAsk = mgv.offers($(base), $(quote), bestAskId);
  }

  function getMidPrice() internal view returns (uint midWants, uint midGives) {
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();

    midWants = bestBid.wants() * bestAsk.wants() + bestBid.gives() * bestAsk.gives();
    midGives = bestAsk.gives() * bestBid.wants() * 2;
  }

  function getDeadOffers(uint midGives, uint midWants)
    internal
    view
    returns (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids)
  {
    GeometricKandel.Params memory params = getParams(kdl);

    uint[] memory indicesPre = new uint[](params.pricePoints);
    quoteAtIndex = new uint[](params.pricePoints);
    numBids = 0;

    uint quote = initQuote;

    // find missing offers
    uint numDead = 0;
    for (uint i = 0; i < params.pricePoints; i++) {
      OfferType ba = quote * midGives <= initBase * midWants ? Bid : Ask;
      MgvStructs.OfferPacked offer = kdl.getOffer(ba, i);
      if (!mgv.isLive(offer)) {
        if (ba == Bid) {
          numBids++;
        }
        indicesPre[numDead] = i;
        numDead++;
      }
      quoteAtIndex[i] = quote;
      quote = (quote * uint(params.ratio)) / 10 ** kdl.PRECISION();
    }

    // truncate indices - cannot do push to memory array
    indices = new uint[](numDead);
    for (uint i = 0; i < numDead; i++) {
      indices[i] = indicesPre[i];
    }
  }

  function heal(uint midWants, uint midGives, uint densityBid, uint densityAsk) internal {
    // user can adjust pending by withdrawFunds or transferring to Kandel, then invoke heal.
    // heal fills up offers to some designated volume starting from mid-price.
    // Designated volume should either be equally divided between holes, or be based on Kandel Density
    // Here we assume its some constant.
    // Note this example implementation
    // * does not support no bids
    // * uses initQuote/initBase as starting point - not available on-chain
    // * assumes mid-price and bid/asks on the book are not crossed.

    uint baseDensity = densityBid;
    uint quoteDensity = densityAsk;

    (uint[] memory indices,, uint numBids) = getDeadOffers(midGives, midWants);

    // build arrays for populate
    CoreKandel.Distribution memory distribution;
    distribution.indices = indices;
    distribution.gives = new uint[](indices.length);
    distribution.prices = new uint[](indices.length);
    distribution.dualPrices = new uint[](indices.length);

    uint pendingQuote = uint(kdl.pending(Bid));
    uint pendingBase = uint(kdl.pending(Ask));

    if (numBids > 0 && baseDensity * numBids < pendingQuote) {
      baseDensity = pendingQuote / numBids; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (int i = int(numBids) - 1; i >= 0; i--) {
      uint d = pendingQuote < baseDensity ? pendingQuote : baseDensity;
      pendingQuote -= d;
      distribution.gives[uint(i)] = d;
      distribution.prices[uint(i)] = kdl.getPriceOfIndex(distribution.indices[uint(i)]);
      distribution.dualPrices[uint(i)] = kdl.getPriceOfIndex(distribution.indices[uint(i)] + 1);
    }

    uint numAsks = indices.length - numBids;
    if (numAsks > 0 && quoteDensity * numAsks < pendingBase) {
      quoteDensity = pendingBase / numAsks; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (uint i = numBids; i < indices.length; i++) {
      uint d = pendingBase < quoteDensity ? pendingBase : quoteDensity;
      pendingBase -= d;
      distribution.gives[uint(i)] = d;
      distribution.prices[uint(i)] = kdl.getPriceOfIndex(distribution.indices[uint(i)]);
      distribution.dualPrices[uint(i)] = kdl.getPriceOfIndex(distribution.indices[uint(i)] - 1);
    }

    uint firstAskIndex = numAsks > 0 ? indices[numBids] : indices[indices.length - 1] + 1;
    uint[] memory pivotIds = new uint[](indices.length);
    vm.prank(maker);
    kdl.populateChunk(distribution, pivotIds, firstAskIndex);
  }

  function test_heal_someFailedOffers_reposts(OfferType ba, uint failures, uint[] memory expectedMidStatus) internal {
    // Arrange
    (uint midWants, uint midGives) = getMidPrice();
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();
    uint densityMidBid = bestBid.gives();
    uint densityMidAsk = bestAsk.gives();
    IERC20 outbound = ba == OfferType.Ask ? base : quote;

    // Fail some offers - make offers fail by removing approval
    vm.prank(maker);
    kdl.approve(outbound, $(mgv), 0);
    for (uint i = 0; i < failures; i++) {
      // This will emit LogIncident and OfferFail
      (uint successes,,,,) = ba == Ask ? buyFromBestAs(taker, 1 ether) : sellToBestAs(taker, 1 ether);
      assertTrue(successes == 0, "Snipe should fail");
    }

    // verify offers have gone
    assertStatus(expectedMidStatus);

    // reduce pending volume to let heal only use some of the original volume when healing
    uint halfPending = uint(kdl.pending(ba)) / 2;
    vm.prank(maker);
    uint baseAmount = ba == Ask ? halfPending : 0;
    uint quoteAmount = ba == Ask ? 0 : halfPending;
    kdl.withdrawFunds(baseAmount, quoteAmount, maker);

    // Act
    heal(midWants, midGives, densityMidBid / 2, densityMidAsk / 2);

    // Assert - verify status and prices
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_heal_1FailedAsk_reposts() public {
    test_heal_someFailedOffers_reposts(Ask, 1, dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
  }

  function test_heal_1FailedBid_reposts() public {
    test_heal_someFailedOffers_reposts(Bid, 1, dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_heal_3FailedAsk_reposts() public {
    test_heal_someFailedOffers_reposts(Ask, 3, dynamic([uint(1), 1, 1, 1, 1, 0, 0, 0, 2, 2]));
  }

  function test_heal_3FailedBid_reposts() public {
    test_heal_someFailedOffers_reposts(Bid, 3, dynamic([uint(1), 1, 0, 0, 0, 2, 2, 2, 2, 2]));
  }

  function test_populateChunk_invalidArrayLength_reverts() public {
    vm.prank(maker);
    // pivot
    vm.expectRevert();
    CoreKandel.Distribution memory dist;
    dist.indices = new uint[](1);
    dist.gives = new uint[](1);
    dist.prices = new uint[](1);
    dist.dualPrices = new uint[](1);
    kdl.populateChunk(dist, new uint[](0), 0);

    // gives
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.gives = new uint[](0);
    dist.prices = new uint[](1);
    dist.dualPrices = new uint[](1);
    kdl.populateChunk(dist, new uint[](1), 0);

    // prices
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.gives = new uint[](1);
    dist.prices = new uint[](0);
    dist.dualPrices = new uint[](1);
    kdl.populateChunk(dist, new uint[](1), 0);

    // dual prices
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.gives = new uint[](1);
    dist.prices = new uint[](1);
    dist.dualPrices = new uint[](0);
    kdl.populateChunk(dist, new uint[](1), 0);
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint gives,
    uint price,
    uint dualPrice,
    uint pivotId,
    uint firstAskIndex,
    bytes memory expectRevert
  ) internal {
    GeometricKandel.Params memory params = getParams(kdl);
    populateSingle(
      kandel,
      index,
      gives,
      price,
      dualPrice,
      pivotId,
      firstAskIndex,
      params.pricePoints,
      params.ratio,
      params.spread,
      expectRevert
    );
  }

  function populateSingle(
    GeometricKandel kandel,
    uint index,
    uint gives,
    uint price,
    uint dualPrice,
    uint pivotId,
    uint firstAskIndex,
    uint pricePoints,
    uint ratio,
    uint spread,
    bytes memory expectRevert
  ) internal {
    CoreKandel.Distribution memory distribution;
    distribution.indices = new uint[](1);
    distribution.prices = new uint[](1);
    distribution.dualPrices = new uint[](1);
    distribution.gives = new uint[](1);
    uint[] memory pivotIds = new uint[](1);

    distribution.indices[0] = index;
    distribution.prices[0] = price;
    distribution.dualPrices[0] = dualPrice;
    distribution.gives[0] = gives;
    pivotIds[0] = pivotId;
    vm.prank(maker);
    if (expectRevert.length > 0) {
      vm.expectRevert(expectRevert);
    }
    GeometricKandel.Params memory params;
    params.pricePoints = uint8(pricePoints);
    params.ratio = uint24(ratio);
    params.spread = uint8(spread);

    kandel.populate{value: 0.1 ether}(distribution, pivotIds, firstAskIndex, params, 0, 0);
  }

  function test_populate_retracts_at_zero() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);

    populateSingle(kdl, index, 0, 42, 42, 0, 5, bytes(""));
    // Bid should be retracted
    assertStatus(index, OfferStatus.Dead);
  }

  function test_populate_density_too_low_reverted() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    populateSingle(kdl, index, 1, 42, 42, 0, 5, "mgv/writeOffer/density/tooLow");
  }

  function test_populate_existing_offer_is_updated() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    uint offerId = offerIdOfIndex(kdl, Bid, index);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);

    populateSingle(kdl, index, bid.gives() * 2, kdl.PRICE_PRECISION(), kdl.PRICE_PRECISION(), 0, 5, "");

    uint offerIdPost = offerIdOfIndex(kdl, Bid, index);
    assertEq(offerIdPost, offerId, "offerId should be unchanged (offer updated)");
    MgvStructs.OfferPacked bidPost = kdl.getOffer(Bid, index);
    assertEq(bidPost.gives(), bid.gives() * 2, "gives should be changed");
  }

  function test_step_higher_than_kandel_size_jumps_to_last() public {
    uint n = getParams(kdl).pricePoints;
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, n - 1);
    // placing a bid on the last position
    // dual of this bid will try to place an ask at n+1 and should place it at n-1 instead of n
    populateSingle(kdl, n - 1, ask.wants(), kdl.getPriceOfIndex(n - 1), kdl.getPriceOfIndex(n - 1), 0, n, "");
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, n - 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = offerIdOfIndex(kdl, Bid, n - 1);
    order.offer = bid;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked ask_ = kdl.getOffer(Ask, n - 1);

    assertTrue(ask.gives() < ask_.gives(), "Ask was not updated");
    assertApproxEqRel(ask.gives() * ask_.wants(), ask.wants() * ask_.gives(), 10 ** 10, "Incorrect price");
  }

  function test_transport_below_min_price_accumulates_at_index_0() public {
    // setting params.spread to 4
    GeometricKandel.Params memory params = getParams(kdl);
    params.spread = 4;

    CoreKandel.Distribution memory distribution1 = KandelLib.calculateDistribution(
      0, 5, initBase, initQuote, params.ratio, kdl.PRECISION(), params.spread, 5, kdl.PRICE_PRECISION(), 10
    );

    CoreKandel.Distribution memory distribution2 = KandelLib.calculateDistribution(
      5, 10, initBase, initQuote, params.ratio, kdl.PRECISION(), params.spread, 5, kdl.PRICE_PRECISION(), 10
    );

    // repopulating to update the spread (but with the same distribution)
    vm.prank(maker);
    kdl.populate{value: 1 ether}(distribution1, dynamic([uint(0), 1, 2, 3, 4]), 5, params, 0, 0);
    vm.prank(maker);
    kdl.populateChunk(distribution2, dynamic([uint(0), 1, 2, 3, 4]), 5);
    // placing an ask at index 1
    // dual of this ask will try to place a bid at -1 and should place it at 0
    populateSingle(kdl, 1, 0.1 ether, distribution1.prices[1], distribution1.prices[0], 0, 0, "");
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants(),
      takerWants: ask.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = offerIdOfIndex(kdl, Ask, 1);
    order.offer = ask;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked bid_ = kdl.getOffer(Bid, 0);
    assertTrue(bid.gives() < bid_.gives(), "Bid was not updated");
  }

  function test_fail_to_create_dual_offer_logs_incident() public {
    // closing bid market
    vm.prank(mgv.governance());
    mgv.deactivate(address(base), address(quote));
    // taking a bid
    uint offerId = offerIdOfIndex(kdl, Bid, 3);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 3);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });

    order.offerId = offerId;
    order.offer = bid;

    expectFrom($(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, 0, "Kandel/newOfferFailed", "mgv/inactive");
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
  }

  function test_fail_to_update_dual_offer_logs_incident() public {
    // closing bid market
    vm.prank(mgv.governance());
    mgv.deactivate(address(base), address(quote));
    // taking a bid that already has a dual ask
    uint offerId = offerIdOfIndex(kdl, Bid, 4);
    uint offerId_ = offerIdOfIndex(kdl, Ask, 5);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });

    order.offerId = offerId;
    order.offer = bid;

    expectFrom($(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, offerId_, "Kandel/updateOfferFailed", "mgv/inactive");
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
  }

  function test_posthook_density_too_low_still_posts_to_dual() public {
    uint index = 4;
    uint offerId = offerIdOfIndex(kdl, Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    // Take almost all - offer will not be reposted due to density too low
    uint amount = bid.wants() - 1;
    vm.prank(taker);
    mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);

    // verify dual is increased
    MgvStructs.OfferPacked askPost = kdl.getOffer(Ask, index + STEP);
    assertGt(askPost.gives(), ask.gives(), "Dual should offer more even though bid failed to post");
  }

  function test_posthook_dual_density_too_low_not_posted_via_newOffer() public {
    //assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    sellToBestAs(taker, 1000 ether);
    // assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));

    uint index = 3;
    uint offerId = offerIdOfIndex(kdl, Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    assertTrue(mgv.isLive(bid), "bid should be live");
    assertTrue(!mgv.isLive(ask), "ask should not be live");

    // Take very little and expect dual posting to fail.
    uint amount = 10000;
    vm.prank(taker);
    (uint successes,,,,) = mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
    assertTrue(successes == 1, "Snipe failed");
    ask = kdl.getOffer(Ask, index + STEP);
    assertTrue(!mgv.isLive(ask), "ask should still not be live");
  }

  function test_posthook_dual_density_too_low_not_posted_via_updateOffer() public {
    // make previous live ask dead
    buyFromBestAs(taker, 1000 ether);

    uint index = 4;
    uint offerId = offerIdOfIndex(kdl, Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    assertTrue(mgv.isLive(bid), "bid should be live");
    assertTrue(!mgv.isLive(ask), "ask should not be live");

    // Take very little and expect dual posting to fail.
    uint amount = 10000;
    vm.prank(taker);
    (uint successes,,,,) = mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
    assertTrue(successes == 1, "Snipe failed");

    ask = kdl.getOffer(Ask, index + STEP);
    assertTrue(!mgv.isLive(ask), "ask should still not be live");
  }

  function getParams(GeometricKandel aKandel) internal view returns (GeometricKandel.Params memory params) {
    (
      uint16 gasprice,
      uint24 gasreq,
      uint24 ratio,
      uint24 compoundRateBase,
      uint24 compoundRateQuote,
      uint8 spread,
      uint8 pricePoints
    ) = aKandel.params();

    params.gasprice = gasprice;
    params.gasreq = gasreq;
    params.ratio = ratio;
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;
    params.spread = spread;
    params.pricePoints = pricePoints;
  }

  CoreKandel.Distribution emptyDist;
  uint[] empty = new uint[](0);

  function test_populate_can_get_set_params_keeps_offers() public {
    GeometricKandel.Params memory params = getParams(kdl);

    uint offeredVolumeBase = kdl.offeredVolume(Ask);
    uint offeredVolumeQuote = kdl.offeredVolume(Bid);

    GeometricKandel.Params memory paramsNew;
    paramsNew.pricePoints = params.pricePoints;
    paramsNew.ratio = params.ratio + 1;
    paramsNew.spread = params.spread + 1;
    paramsNew.compoundRateBase = params.compoundRateBase + 1;
    paramsNew.compoundRateQuote = params.compoundRateQuote + 2;
    paramsNew.gasprice = params.gasprice + 1;
    paramsNew.gasreq = params.gasreq + 1;

    expectFrom(address(kdl));
    emit SetGeometricParams(paramsNew.spread, paramsNew.ratio);
    expectFrom(address(kdl));
    emit SetGasprice(paramsNew.gasprice);
    expectFrom(address(kdl));
    emit SetGasreq(paramsNew.gasreq);
    expectFrom(address(kdl));
    emit SetCompoundRates(paramsNew.compoundRateBase, paramsNew.compoundRateQuote);

    vm.prank(maker);
    kdl.populate(emptyDist, empty, 0, paramsNew, 0, 0);

    GeometricKandel.Params memory params_ = getParams(kdl);

    assertEq(params_.gasprice, paramsNew.gasprice, "gasprice should be changed");
    assertEq(params_.gasreq, paramsNew.gasreq, "gasreq should be changed");
    assertEq(params_.pricePoints, params.pricePoints, "pricePoints should not be changed");
    assertEq(params_.ratio, paramsNew.ratio, "ratio should be changed");
    assertEq(params_.compoundRateBase, paramsNew.compoundRateBase, "compoundRateBase should be changed");
    assertEq(params_.compoundRateQuote, paramsNew.compoundRateQuote, "compoundRateQuote should be changed");
    assertEq(params_.spread, params.spread + 1, "spread should be changed");
    assertEq(offeredVolumeBase, kdl.offeredVolume(Ask), "ask volume should be unchanged");
    assertEq(offeredVolumeQuote, kdl.offeredVolume(Bid), "ask volume should be unchanged");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]), type(uint).max, type(uint).max);
  }

  function test_populate_throws_on_invalid_ratio() public {
    uint precision = kdl.PRECISION();
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** precision - 1);
    params.spread = 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidRatio");
    kdl.populate(emptyDist, empty, 0, params, 0, 0);
  }

  function test_populate_throws_on_invalid_spread_low() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** kdl.PRECISION());
    params.spread = 0;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.populate(emptyDist, empty, 0, params, 0, 0);
  }

  function test_populate_throws_on_invalid_spread_high() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** kdl.PRECISION());
    params.spread = 9;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.populate(emptyDist, empty, 0, params, 0, 0);
  }

  function test_populate_invalidCompoundRatesBase_reverts() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** kdl.PRECISION());
    params.spread = 1;
    params.compoundRateBase = uint24(10 ** kdl.PRECISION() + 1);
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateBase");
    kdl.populate(emptyDist, empty, 0, params, 0, 0);
  }

  function test_populate_invalidCompoundRatesQuote_reverts() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** kdl.PRECISION());
    params.spread = 1;
    params.compoundRateQuote = uint24(10 ** kdl.PRECISION() + 1);
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateQuote");
    kdl.populate(emptyDist, empty, 0, params, 0, 0);
  }

  function test_setCompoundRatesBase_reverts() public {
    uint wrong_rate = 10 ** kdl.PRECISION() + 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateBase");
    kdl.setCompoundRates(wrong_rate, 0);
  }

  function test_setCompoundRatesQuote_reverts() public {
    uint wrong_rate = 10 ** kdl.PRECISION() + 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateQuote");
    kdl.setCompoundRates(0, wrong_rate);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate0() public {
    test_populate_can_repopulate_other_size_and_other_params(0, 0);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate1() public {
    test_populate_can_repopulate_other_size_and_other_params(full_compound(), full_compound());
  }

  function test_populate_can_repopulate_other_size_and_other_params(uint24 compoundRateBase, uint24 compoundRateQuote)
    internal
  {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    GeometricKandel.Params memory params;
    params.pricePoints = 5;
    params.ratio = uint24(102 * 10 ** kdl.PRECISION() / 100);
    params.spread = 2;
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;

    CoreKandel.Distribution memory distribution = KandelLib.calculateDistribution(
      0,
      5,
      initBase,
      initQuote,
      params.ratio,
      kdl.PRECISION(),
      params.spread,
      3,
      kdl.PRICE_PRECISION(),
      params.pricePoints
    );

    expectFrom(address(kdl));
    emit SetLength(params.pricePoints);
    vm.prank(maker);
    kdl.populate(distribution, dynamic([uint(0), 1, 2, 3, 4]), 3, params, 0, 0);

    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    // This only verifies KandelLib
    assertStatus(dynamic([uint(1), 1, 1, 2, 2]));

    sellToBestAs(taker, 1 ether);

    // This verifies dualWantsGivesOfOffer
    assertStatus(dynamic([uint(1), 1, 0, 2, 2]));
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 0, 0, 2, 2]));
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(0), 0, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 0, 0]));
  }

  function test_populates_emits() public {
    expectFrom($(kdl));
    emit PopulateStart();
    vm.expectEmit(false, false, false, false, $(mgv));
    emit OfferWrite(address(0), address(0), address(0), 0, 0, 0, 0, 0, 0);
    expectFrom($(kdl));
    emit PopulateEnd();
    populateSingle(kdl, 1, 1 ether, kdl.PRICE_PRECISION(), 42, 0, 2, bytes(""));
  }

  function test_setGasprice_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasprice(42);
    vm.prank(maker);
    kdl.setGasprice(42);
    (uint16 gasprice,,,,,,) = kdl.params();
    assertEq(gasprice, uint16(42), "Incorrect gasprice in params");
  }

  function test_setGasprice_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gaspriceTooHigh");
    kdl.setGasprice(2 ** 16);
  }

  function test_setGasreq_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasreq(42);
    vm.prank(maker);
    kdl.setGasreq(42);
    (, uint24 gasreq,,,,,) = kdl.params();
    assertEq(gasreq, uint24(42), "Incorrect gasprice in params");
  }

  function test_setGasreq_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gasreqTooHigh");
    kdl.setGasreq(2 ** 24);
  }

  function test_retractAndWithdraw() public {
    address payable recipient = freshAddress();
    uint baseBalance = kdl.reserveBalance(Ask);
    uint quoteBalance = kdl.reserveBalance(Bid);
    expectFrom($(kdl));
    emit Debit(base, baseBalance);
    expectFrom($(kdl));
    emit Debit(quote, quoteBalance);
    vm.prank(maker);
    kdl.retractAndWithdraw(0, 10, baseBalance, quoteBalance, type(uint).max, recipient);

    assertEq(quoteBalance, quote.balanceOf(recipient), "quote balance should be sent to recipient");
    assertEq(baseBalance, base.balanceOf(recipient), "quote balance should be sent to recipient");
    assertGt(recipient.balance, 0, "wei should be at recipient");
    assertEq(0, kdl.offeredVolume(Bid), "no bids should be live");
    assertEq(0, kdl.offeredVolume(Ask), "no bids should be live");
  }

  function test_depositFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    base.approve($(kdl), baseAmount);
    quote.approve($(kdl), quoteAmount);

    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    kdl.depositFunds(baseAmount, quoteAmount);

    assertApproxEqRel(baseBalance + baseAmount, kdl.reserveBalance(Ask), 10 ** 10, "Incorrect base deposit");
    assertApproxEqRel(quoteBalance + quoteAmount, kdl.reserveBalance(Bid), 10 ** 10, "Incorrect base deposit");
  }

  function test_deposit0Funds() public {
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);
    kdl.depositFunds(0, 0);
    assertEq(kdl.reserveBalance(Ask), baseBalance, "Incorrect base deposit");
    assertEq(kdl.reserveBalance(Bid), quoteBalance, "Incorrect quote deposit");
  }

  function test_withdrawFunds(uint96 baseAmount, uint96 quoteAmount) public {
    deal($(base), address(this), baseAmount);
    deal($(quote), address(this), quoteAmount);
    base.approve($(kdl), baseAmount);
    quote.approve($(kdl), quoteAmount);

    kdl.depositFunds(baseAmount, quoteAmount);

    vm.prank(maker);
    kdl.withdrawFunds(baseAmount, quoteAmount, address(this));
    assertEq(base.balanceOf(address(this)), baseAmount, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteAmount, "Incorrect quote withdrawl");
  }

  function test_withdrawAll() public {
    deal($(base), address(this), 1 ether);
    deal($(quote), address(this), 100 * 10 ** 6);
    base.approve($(kdl), 1 ether);
    quote.approve($(kdl), 100 * 10 ** 6);

    kdl.depositFunds(1 ether, 100 * 10 ** 6);
    uint quoteBalance = kdl.reserveBalance(Bid);
    uint baseBalance = kdl.reserveBalance(Ask);

    vm.prank(maker);
    kdl.withdrawFunds(type(uint).max, type(uint).max, address(this));
    assertEq(base.balanceOf(address(this)), baseBalance, "Incorrect base withdrawal");
    assertEq(quote.balanceOf(address(this)), quoteBalance, "Incorrect quote withdrawl");
  }

  function test_marketOrder_dualOfferUpdate_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(false, 87985);
  }

  function test_marketOrder_dualOfferNew_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(true, 0);
  }

  function marketOrder_dualOffer_expectedGasreq(bool dualNew, uint deltaGasForNew) internal {
    // Arrange
    MgvLib.SingleOrder memory order = mockBuyOrder({takerGives: cash(quote, 100), takerWants: 0.1 ether});
    order.offerId = offerIdOfIndex(kdl, Ask, dualNew ? 6 : 5);

    // Act
    vm.prank($(mgv));
    uint gasTemp = gasleft();
    bytes32 makerData = kdl.makerExecute(order);
    uint makerExecuteCost = gasTemp - gasleft();

    assertTrue(makerData == bytes32(0) || makerData == "IS_FIRST_PULLER", "Unexpected returned data");

    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: makerData, mgvData: "mgv/tradeSuccess"});

    vm.prank($(mgv));
    gasTemp = gasleft();
    kdl.makerPosthook(order, result);
    uint posthookCost = gasTemp - gasleft();
    // Assert
    (, MgvStructs.LocalPacked local) = mgv.config(address(base), address(quote));
    console.log("makerExecute: %d, posthook: %d, deltaGasForNew", makerExecuteCost, posthookCost, deltaGasForNew);
    console.log(
      "Strat gasreq (%d), mockup (%d)",
      kdl.offerGasreq() + local.offer_gasbase(),
      makerExecuteCost + posthookCost + deltaGasForNew
    );
    //assertTrue(makerExecuteCost + posthookCost <= kdl.offerGasreq() + local.offer_gasbase(), "Strat is spending more gas");
  }

  function deployOtherKandel(uint base0, uint quote0, uint24 ratio, uint8 spread, uint8 pricePoints) internal {
    address otherMaker = freshAddress();

    GeometricKandel otherKandel = __deployKandel__(otherMaker, otherMaker);

    vm.prank(otherMaker);
    base.approve(address(otherKandel), type(uint).max);
    vm.prank(otherMaker);
    quote.approve(address(otherKandel), type(uint).max);

    uint totalProvision = (
      reader.getProvision($(base), $(quote), otherKandel.offerGasreq(), bufferedGasprice)
        + reader.getProvision($(quote), $(base), otherKandel.offerGasreq(), bufferedGasprice)
    ) * 10 ether;

    deal(otherMaker, totalProvision);

    uint firstAskIndex = pricePoints / 2;
    CoreKandel.Distribution memory distribution = KandelLib.calculateDistribution(
      0,
      pricePoints,
      base0,
      quote0,
      ratio,
      otherKandel.PRECISION(),
      spread,
      firstAskIndex,
      kdl.PRICE_PRECISION(),
      pricePoints
    );

    GeometricKandel.Params memory params;
    params.pricePoints = pricePoints;
    params.ratio = ratio;
    params.spread = spread;
    vm.prank(otherMaker);
    otherKandel.populate{value: totalProvision}(distribution, new uint[](pricePoints), firstAskIndex, params, 0, 0);

    uint pendingBase = uint(-otherKandel.pending(Ask));
    uint pendingQuote = uint(-otherKandel.pending(Bid));
    deal($(base), otherMaker, pendingBase);
    deal($(quote), otherMaker, pendingQuote);

    vm.prank(otherMaker);
    otherKandel.depositFunds(pendingBase, pendingQuote);
  }

  struct TestPivot {
    uint firstAskIndex;
    uint funds;
    uint[] pivotIds;
    uint gas0Pivot;
    uint gasPivots;
    uint baseAmountRequired;
    uint quoteAmountRequired;
    uint snapshotId;
  }

  function test_estimatePivotsAndRequiredAmount_withPivots_savesGas() public {
    // Arrange
    retractDefaultSetup();

    // Use a large number of price points - the rest of the parameters are not too important
    GeometricKandel.Params memory params;
    params.ratio = uint24(108 * 10 ** kdl.PRECISION() / 100);
    params.pricePoints = 100;
    params.spread = STEP;

    TestPivot memory t;
    t.firstAskIndex = params.pricePoints / 2;
    t.funds = 20 ether;

    // Make sure there are some other offers that can end up as pivots - we deploy a couple of Kandels
    deployOtherKandel(initBase + 1, initQuote + 1, params.ratio, params.spread, params.pricePoints);
    deployOtherKandel(initBase + 100, initQuote + 100, params.ratio, params.spread, params.pricePoints);

    CoreKandel.Distribution memory distribution = KandelLib.calculateDistribution({
      from: 0,
      to: params.pricePoints,
      initBase: initBase,
      initQuote: initQuote,
      ratio: params.ratio,
      precision: kdl.PRECISION(),
      spread: params.spread,
      firstAskIndex: t.firstAskIndex,
      pricePrecision: kdl.PRICE_PRECISION(),
      pricePoints: params.pricePoints
    });

    // Get some reasonable pivots (use a snapshot to avoid actually posting offers yet)
    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    (t.pivotIds, t.baseAmountRequired, t.quoteAmountRequired) =
      KandelLib.estimatePivotsAndRequiredAmount(distribution, kdl, t.firstAskIndex, params, t.funds);
    require(vm.revertTo(t.snapshotId), "snapshot restore failed");

    // Make sure we have enough funds
    deal($(base), maker, t.baseAmountRequired);
    deal($(quote), maker, t.quoteAmountRequired);

    // Act

    // Populate with 0-pivots
    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    t.gas0Pivot = gasleft();
    kdl.populate{value: t.funds}({
      distribution: distribution,
      firstAskIndex: t.firstAskIndex,
      parameters: params,
      pivotIds: new uint[](params.pricePoints),
      baseAmount: t.baseAmountRequired,
      quoteAmount: t.quoteAmountRequired
    });
    t.gas0Pivot = t.gas0Pivot - gasleft();

    require(vm.revertTo(t.snapshotId), "second snapshot restore failed");

    // Populate with pivots
    vm.prank(maker);
    t.gasPivots = gasleft();
    kdl.populate{value: t.funds}({
      distribution: distribution,
      firstAskIndex: t.firstAskIndex,
      parameters: params,
      pivotIds: t.pivotIds,
      baseAmount: t.baseAmountRequired,
      quoteAmount: t.quoteAmountRequired
    });
    t.gasPivots = t.gasPivots - gasleft();

    // Assert

    assertApproxEqAbs(0, kdl.pending(OfferType.Ask), precisionForAssert(), "required base amount should be deposited");
    assertApproxEqAbs(0, kdl.pending(OfferType.Bid), precisionForAssert(), "required quote amount should be deposited");

    //   console.log("No pivot populate: %s PivotPopulate: %s", t.gas0Pivot, t.gasPivots);

    assertLt(t.gasPivots, t.gas0Pivot, "Providing pivots should save gas");
  }

  function test_dualWantsGivesOfOffer_maxBitsPartialTakeFullCompound_correctCalculation() public {
    test_dualWantsGivesOfOffer_maxBits_correctCalculation(true, 2, true);
  }

  function test_dualWantsGivesOfOffer_maxBitsPartialTakeZeroCompound_correctCalculation() public {
    test_dualWantsGivesOfOffer_maxBits_correctCalculation(true, 2, false);
  }

  function test_dualWantsGivesOfOffer_maxBitsFullTakeZeroCompound_correctCalculation() public {
    test_dualWantsGivesOfOffer_maxBits_correctCalculation(false, 2, false);
  }

  function test_dualWantsGivesOfOffer_maxBitsFullTakeFullCompound_correctCalculation() public {
    test_dualWantsGivesOfOffer_maxBits_correctCalculation(false, 2, true);
  }

  function test_dualWantsGivesOfOffer_maxBits_correctCalculation(bool partialTake, uint numTakes, bool fullCompound)
    internal
  {
    // With partialTake false we verify uint160(givesR) != givesR in dualWantsGivesOfOffer
    // With partialTake true we verify the edge cases
    // uint160(givesR) != givesR
    // uint96(wants) != wants
    // uint96(gives) != gives
    // in dualWantsGivesOfOffer

    uint8 spread = 8;
    uint8 pricePoints = type(uint8).max;

    uint precision = kdl.PRECISION();

    uint compoundRate = fullCompound ? 10 ** precision : 0;

    vm.prank(maker);
    kdl.retractOffers(0, 10);

    for (uint i = 0; i < numTakes; i++) {
      populateSingle({
        kandel: kdl,
        index: 0,
        gives: type(uint96).max,
        price: (type(uint96).max * kdl.PRICE_PRECISION()) / type(uint96).max,
        dualPrice: (((2 * 10 ** precision) ** spread) * kdl.PRICE_PRECISION()) / ((10 ** precision) ** spread),
        pivotId: 0,
        firstAskIndex: 2,
        pricePoints: pricePoints,
        ratio: 2 * 10 ** precision,
        spread: spread,
        expectRevert: bytes("")
      });

      vm.prank(maker);
      kdl.setCompoundRates(compoundRate, compoundRate);
      // This only verifies KandelLib

      MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);

      deal($(quote), address(kdl), bid.gives());
      deal($(base), address(taker), bid.wants());

      uint amount = partialTake ? 1 ether : bid.wants();

      (uint successes,,,,) = sellToBestAs(taker, amount);
      assertEq(successes, 1, "offer should be sniped");
    }
    uint askOfferId = mgv.best($(base), $(quote));
    (uint askIndex,) = kdl.indexOfOfferId(Ask, askOfferId);

    uint[] memory statuses = new uint[](askIndex+2);
    if (partialTake) {
      MgvStructs.OfferPacked ask = kdl.getOffer(Ask, askIndex);
      if (fullCompound) {
        assertEq(1 ether * numTakes, ask.gives(), "ask should offer the provided 1 ether for each take");
      } else {
        assertGt(
          1 ether * numTakes, ask.gives(), "due to low compound ask should not offer the full ether for each take"
        );
      }
      statuses[0] = uint(OfferStatus.Bid);
    }
    statuses[askIndex] = uint(OfferStatus.Ask);
    assertStatus(statuses, type(uint96).max, type(uint96).max);
  }

  function test_dualWantsGivesOfOffer_bidNearBoundary_correctPrice() public {
    test_dualWantsGivesOfOffer_nearBoundary_correctPrice(Bid);
  }

  function test_dualWantsGivesOfOffer_askNearBoundary_correctPrice() public {
    test_dualWantsGivesOfOffer_nearBoundary_correctPrice(Ask);
  }

  function test_dualWantsGivesOfOffer_nearBoundary_correctPrice(OfferType ba) internal {
    uint8 spread = 3;
    uint8 pricePoints = 6;

    uint precision = kdl.PRECISION();
    uint ratio = 2 * 10 ** precision;

    vm.prank(maker);
    kdl.retractOffers(0, 10);

    populateSingle({
      kandel: kdl,
      index: ba == Bid ? 4 : 1,
      gives: ba == Bid ? initQuote : initBase,
      price: (initQuote * kdl.PRICE_PRECISION()) / initBase,
      dualPrice: ba == Bid
        ? (ratio * (initQuote * kdl.PRICE_PRECISION()) / initBase) / (10 ** precision)
        : ((10 ** precision) * (initQuote * kdl.PRICE_PRECISION()) / initBase) / ratio,
      pivotId: 0,
      firstAskIndex: ba == Bid ? pricePoints : 0,
      pricePoints: pricePoints,
      ratio: ratio,
      spread: spread,
      expectRevert: bytes("")
    });
    uint compoundRate = full_compound();
    vm.prank(maker);
    kdl.setCompoundRates(compoundRate, compoundRate);

    (uint successes,,,,) = ba == Bid ? sellToBestAs(taker, 1 ether) : buyFromBestAs(taker, 1 ether);
    assertEq(successes, 1, "offer should be sniped");

    if (ba == Bid) {
      MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);
      assertEq(ask.gives(), initBase);
      assertApproxEqAbs(ask.wants(), ask.gives() * 2 / 1000000000, 1, "incorrect wants");
    } else {
      MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);
      assertApproxEqAbs(bid.gives(), initQuote, 1, "incorrect gives");
      assertEq(bid.wants(), bid.gives() * 2 * 1000000000);
    }
  }

  function getAbiPath() internal pure virtual returns (string memory);

  function test_allExternalFunctions_differentCallers_correctAuth() public virtual {
    // Arrange
    bytes[] memory selectors = AllMethodIdentifiersTest.getAllMethodIdentifiers(vm, getAbiPath());

    assertGt(selectors.length, 0, "Some functions should be loaded");

    for (uint i = 0; i < selectors.length; i++) {
      // Assert that all are called - to decode the selector search in the abi file
      vm.expectCall(address(kdl), selectors[i]);
    }

    // Act/assert - invoke all functions - if any are missing, add them.

    // No auth
    kdl.BASE();
    kdl.MGV();
    kdl.NO_ROUTER();
    kdl.OFFER_GASREQ();
    kdl.PRECISION();
    kdl.PRICE_PRECISION();
    kdl.QUOTE();
    kdl.RESERVE_ID();
    kdl.admin();
    kdl.checkList(new IERC20[](0));
    kdl.depositFunds(0, 0);
    kdl.getOffer(Ask, 0);
    kdl.indexOfOfferId(Ask, 42);
    kdl.offerIdOfIndex(Ask, 0);
    kdl.getPriceOfIndex(0);
    kdl.offerGasreq();
    kdl.offeredVolume(Ask);
    kdl.params();
    kdl.pending(Ask);
    kdl.reserveBalance(Ask);
    kdl.provisionOf(base, quote, 0);
    kdl.router();

    CoreKandel.Distribution memory dist;
    CheckAuthArgs memory args;
    args.callee = $(kdl);
    args.callers = dynamic([address($(mgv)), maker, $(this)]);
    args.revertMessage = "AccessControlled/Invalid";

    // Only admin
    args.allowed = dynamic([address(maker)]);
    checkAuth(args, abi.encodeCall(kdl.activate, dynamic([IERC20(base)])));
    checkAuth(args, abi.encodeCall(kdl.activate, dynamic([IERC20(base)])));
    checkAuth(args, abi.encodeCall(kdl.approve, (base, taker, 42)));
    checkAuth(args, abi.encodeCall(kdl.setAdmin, (maker)));
    checkAuth(args, abi.encodeCall(kdl.retractAndWithdraw, (0, 0, 0, 0, 0, maker)));
    checkAuth(args, abi.encodeCall(kdl.setGasprice, (42)));
    checkAuth(args, abi.encodeCall(kdl.setGasreq, (42)));
    checkAuth(args, abi.encodeCall(kdl.setRouter, (kdl.router())));
    checkAuth(args, abi.encodeCall(kdl.populate, (dist, new uint[](0), 0, getParams(kdl), 0, 0)));
    checkAuth(args, abi.encodeCall(kdl.populateChunk, (dist, new uint[](0), 42)));
    checkAuth(args, abi.encodeCall(kdl.retractOffers, (0, 0)));
    checkAuth(args, abi.encodeCall(kdl.withdrawFromMangrove, (0, maker)));
    checkAuth(args, abi.encodeCall(kdl.withdrawFunds, (0, 0, maker)));
    checkAuth(args, abi.encodeCall(kdl.setCompoundRates, (0, 0)));

    // Only Mgv
    MgvLib.OrderResult memory oResult = MgvLib.OrderResult({makerData: bytes32(0), mgvData: ""});
    args.allowed = dynamic([address($(mgv))]);
    checkAuth(args, abi.encodeCall(kdl.makerExecute, mockBuyOrder(1, 1)));
    checkAuth(args, abi.encodeCall(kdl.makerPosthook, (mockBuyOrder(1, 1), oResult)));
  }
}
