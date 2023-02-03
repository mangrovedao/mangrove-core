// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// FIXME outstanding missing feature/tests
// * Populates:
//   * throws if not enough provision
// * newOffer below density creates pending
// * overflow in dual offer computation is correctly managed

import "mgv_test/lib/MangroveTest.sol";
import {
  CoreKandel,
  Kandel,
  MgvStructs,
  IMangrove,
  OfferType,
  HasIndexedOffers
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";
import {console2} from "forge-std/Test.sol";
import {SimpleRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";

contract CoreKandelTest is MangroveTest {
  address payable maker;
  address payable taker;
  CoreKandel kdl;
  uint8 constant STEP = 1;
  uint initQuote;
  uint initBase = 0.1 ether;
  uint globalGasprice;
  uint bufferedGasprice;

  event AllAsks();
  event AllBids();
  event NewKandel(address indexed owner, IMangrove indexed mgv, IERC20 indexed base, IERC20 quote);
  event SetParams(uint kandelSize, uint spread, uint ratio);
  //  event BidNearMidPopulated(uint index, uint gives, uint96 wants);

  // sets base and quote
  function __setForkEnvironment__() internal virtual {
    // no fork
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;
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
    vm.startPrank(taker);
    base.approve($(mgv), type(uint).max);
    quote.approve($(mgv), type(uint).max);
    vm.stopPrank();

    // deploy and activate
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    globalGasprice = global.gasprice();
    bufferedGasprice = globalGasprice * 10; // covering 10 times Mangrove's gasprice at deploy time

    kdl = __deployKandel__(maker);

    // funding Kandel on Mangrove
    uint provAsk = kdl.getMissingProvision(base, quote, kdl.offerGasreq(), bufferedGasprice, 0);
    uint provBid = kdl.getMissingProvision(quote, base, kdl.offerGasreq(), bufferedGasprice, 0);
    deal(maker, (provAsk + provBid) * 10 ether);

    vm.startPrank(maker);
    base.approve(address(kdl), type(uint).max);
    quote.approve(address(kdl), type(uint).max);

    uint16 ratio = uint16(108 * 10 ** kdl.PRECISION() / 100);

    (CoreKandel.Distribution memory distribution1, uint lastQuote) =
      KandelLib.calculateDistribution(0, 5, initBase, initQuote, ratio, kdl.PRECISION());

    (CoreKandel.Distribution memory distribution2,) =
      KandelLib.calculateDistribution(5, 10, initBase, lastQuote, ratio, kdl.PRECISION());

    kdl.populate{value: (provAsk + provBid) * 10}(
      distribution1, dynamic([uint(0), 1, 2, 3, 4]), 4, 10, ratio, STEP, new IERC20[](0), new uint[](0)
    );

    kdl.populateChunk(distribution2, dynamic([uint(0), 1, 2, 3, 4]), 4);

    uint pendingBase = uint(-kdl.pending(Ask));
    uint pendingQuote = uint(-kdl.pending(Bid));
    deal($(base), maker, pendingBase);
    deal($(quote), maker, pendingQuote);
    kdl.depositFunds(dynamic([IERC20(base), quote]), dynamic([pendingBase, pendingQuote]));

    vm.stopPrank();
  }

  function __deployKandel__(address deployer) internal virtual returns (CoreKandel kdl_) {
    uint GASREQ = 128_000; // can be 77_000 when all offers are initialized.

    HasIndexedOffers.MangroveWithBaseQuote memory mangroveWithBaseQuote =
      HasIndexedOffers.MangroveWithBaseQuote({mgv: IMangrove($(mgv)), base: base, quote: quote});

    vm.prank(deployer);
    kdl_ = new Kandel({
      mangroveWithBaseQuote: mangroveWithBaseQuote,
      gasreq: GASREQ,
      gasprice: bufferedGasprice,
      owner: deployer
    });
  }

  function buyFromBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestAsk = mgv.best($(base), $(quote));
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([bestAsk, amount, type(uint96).max, type(uint).max]), true);
  }

  function sellToBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestBid = mgv.best($(quote), $(base));
    vm.prank(taker_);
    return mgv.snipes($(quote), $(base), wrap_dynamic([bestBid, 0, amount, type(uint).max]), false);
  }

  function snipeBuyAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(Ask, index);
    vm.prank(taker_);
    return mgv.snipes($(base), $(quote), wrap_dynamic([offerId, amount, type(uint96).max, type(uint).max]), true);
  }

  function snipeSellAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(Bid, index);
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
            bid.gives() * b, q * bid.wants(), 1e11, "Bid price does not follow distribution within 0.00001%"
          );
        }
      } else {
        if (status == OfferStatus.Ask) {
          assertTrue(!bidLive && askLive, "Kandel is not asking at index");
          if (q != type(uint).max) {
            assertApproxEqRel(
              ask.wants() * b, q * ask.gives(), 1e11, "Ask price does not follow distribution within 0.00001%"
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
    Kandel.Params memory params = GetParams(kdl);
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

  function pending(OfferType ba) internal view returns (uint) {
    return uint(kdl.pending(ba));
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_bid_complete_fill_compound_1() public {
    test_bid_complete_fill(10_000, 0);
  }

  function test_bid_complete_fill_compound_0() public {
    test_bid_complete_fill(0, 10_000);
  }

  function test_bid_complete_fill_compound_half() public {
    test_bid_complete_fill(5_000, 10_000);
  }

  function test_ask_complete_fill_compound_1() public {
    test_ask_complete_fill(0, 10_000);
  }

  function test_ask_complete_fill_compound_0() public {
    test_ask_complete_fill(10_000, 0);
  }

  function test_ask_complete_fill_compound_half() public {
    test_ask_complete_fill(0, 5_000);
  }

  function test_bid_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote) public {
    test_bid_complete_fill(compoundRateBase, compoundRateQuote, 4);
  }

  function test_bid_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote, uint index) internal {
    vm.assume(compoundRateBase <= 10_000);
    vm.assume(compoundRateQuote <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldAsk = kdl.getOffer(Ask, index + STEP);
    uint oldPending = pending(Ask);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = sellToBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newAsk = kdl.getOffer(Ask, index + STEP);
    assertTrue(newAsk.gives() <= takerGave + oldAsk.gives(), "Cannot give more than what was received");
    uint pendingDelta = pending(Ask) - oldPending;
    assertEq(pendingDelta + newAsk.gives(), oldAsk.gives() + takerGave, "Incorrect net promised asset");
    if (compoundRateBase == 10_000) {
      assertEq(pendingDelta, 0, "Full compounding should not yield pending");
      assertTrue(newAsk.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
      //      assertTrue(newAsk.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    }
  }

  function test_ask_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote) public {
    test_ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
  }

  function test_ask_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote, uint index) internal {
    vm.assume(compoundRateBase <= 10_000);
    vm.assume(compoundRateQuote <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldBid = kdl.getOffer(Bid, index - STEP);
    uint oldPending = pending(Bid);

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
    uint pendingDelta = pending(Bid) - oldPending;
    assertEq(pendingDelta + newBid.gives(), oldBid.gives() + takerGave, "Incorrect net promised asset");
    if (compoundRateQuote == 10_000) {
      assertEq(pendingDelta, 0, "Full compounding should not yield pending");
      assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    } else {
      assertTrue(pendingDelta > 0, "Partial auto compounding should yield pending");
      // assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    }
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_logs_all_asks() public {
    // taking all bids
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 0, 2, 2, 2, 2, 2, 2, 2, 2]));
    expectFrom(address(kdl));
    emit AllAsks();
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]));
  }

  function test_logs_all_bids() public {
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllBids();
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]));
  }

  function test_all_bids_all_asks_and_back() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    vm.startPrank(taker);
    mgv.marketOrder($(base), $(quote), type(uint96).max, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]));
    mgv.marketOrder($(quote), $(base), 1 ether, type(uint96).max, false);
    assertStatus(dynamic([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]));
    uint askVol = kdl.offeredVolume(Ask);
    mgv.marketOrder($(base), $(quote), askVol / 2, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    vm.stopPrank();
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
    vm.startPrank(maker);
    kdl.retractOffers(0, 5);
    kdl.retractOffers(0, 10);

    assertEq(0, kdl.offeredVolume(Ask), "All ask volume should be retracted");
    assertEq(0, kdl.offeredVolume(Bid), "All bid volume should be retracted");
    assertGt(mgv.balanceOf(address(kdl)), preMgvBalance, "Kandel should have balance on mgv after retract");
    assertEq(maker.balance, preBalance, "maker should not be credited yet");

    kdl.withdrawFromMangrove(type(uint).max, maker);
    assertGt(maker.balance, preBalance, "maker should be credited");
    vm.stopPrank();
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
    uint16 compoundRateBase,
    uint16 compoundRateQuote,
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
    test_take_full_bid_and_ask_repeatedly(10, 10_000, 10_000, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_zero_quote_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 10_000, 0, ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_zero_base_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 0, 10_000, ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_close_to_zero_base_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 1, 10_000, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_increasing_boundary() public {
    test_take_full_bid_and_ask_repeatedly(10, 4904, 4904, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_decreasing_boundary() public {
    test_take_full_bid_and_ask_repeatedly(10, 4903, 4903, ExpectedChange.Decrease, ExpectedChange.Decrease);
  }

  function test_take_full_bid_and_ask_10_times_zero_compound() public {
    test_take_full_bid_and_ask_repeatedly(10, 0, 0, ExpectedChange.Decrease, ExpectedChange.Decrease);
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
    Kandel.Params memory params = GetParams(kdl);

    uint[] memory indicesPre = new uint[](params.length);
    quoteAtIndex = new uint[](params.length);
    numBids = 0;

    uint quote = initQuote;

    // find missing offers
    uint numDead = 0;
    for (uint i = 0; i < params.length; i++) {
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
    //TODO does not support no bids
    //TODO Uses initQuote/initBase as starting point - not available on-chain
    //TODO assumes mid-price and bid/asks on the book are not crossed.

    uint baseDensity = densityBid;
    uint quoteDensity = densityAsk;

    (uint[] memory indices, uint[] memory quoteAtIndex, uint numBids) = getDeadOffers(midGives, midWants);

    // build arrays for populate
    uint[] memory quoteDist = new uint[](indices.length);
    uint[] memory baseDist = new uint[](indices.length);

    uint pendingQuote = uint(kdl.pending(Bid));
    uint pendingBase = uint(kdl.pending(Ask));

    if (numBids > 0 && baseDensity * numBids < pendingQuote) {
      baseDensity = pendingQuote / numBids; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (int i = int(numBids) - 1; i >= 0; i--) {
      uint d = pendingQuote < baseDensity ? pendingQuote : baseDensity;
      pendingQuote -= d;
      quoteDist[uint(i)] = d;
      baseDist[uint(i)] = initBase * d / quoteAtIndex[indices[uint(i)]];
    }

    uint numAsks = indices.length - numBids;
    if (numAsks > 0 && quoteDensity * numAsks < pendingBase) {
      quoteDensity = pendingBase / numAsks; // fill up (a tiny bit lost to rounding)
    }
    // fill up close to mid price first
    for (uint i = numBids; i < indices.length; i++) {
      uint d = pendingBase < quoteDensity ? pendingBase : quoteDensity;
      pendingBase -= d;
      baseDist[uint(i)] = d;
      quoteDist[uint(i)] = quoteAtIndex[indices[uint(i)]] * d / initBase;
    }

    uint lastBidIndex = numBids > 0 ? indices[numBids - 1] : indices[0] - 1;
    uint[] memory pivotIds = new uint[](indices.length);
    CoreKandel.Distribution memory distribution;
    distribution.indices = indices;
    distribution.baseDist = baseDist;
    distribution.quoteDist = quoteDist;
    vm.prank(maker);
    kdl.populateChunk(distribution, pivotIds, lastBidIndex);
  }

  function withdrawFunds(IERC20 token, uint amount, address recipient) internal {
    kdl.withdrawFunds(dynamic([token]), dynamic([amount]), recipient);
  }

  function test_heal_ba(OfferType ba, uint failures, uint[] memory expectedMidStatus) internal {
    (uint midWants, uint midGives) = getMidPrice();
    (MgvStructs.OfferPacked bestBid, MgvStructs.OfferPacked bestAsk) = getBestOffers();
    uint densityMidBid = bestBid.gives();
    uint densityMidAsk = bestAsk.gives();
    // make offer fail (too little balance)
    uint offeredVolume = kdl.offeredVolume(ba);
    IERC20 outbound = ba == OfferType.Ask ? base : quote;
    vm.prank(maker);
    withdrawFunds(outbound, offeredVolume, maker);

    for (uint i = 0; i < failures; i++) {
      // This will emit LogIncident and OfferFail
      (uint successes,,,,) = ba == Ask ? buyFromBestAs(taker, 1 ether) : sellToBestAs(taker, 1 ether);
      assertTrue(successes == 0, "Snipe should fail");
    }

    // verify offers have gone
    assertStatus(expectedMidStatus);

    // send funds back
    // outbound.transfer(address(kdl), offeredVolume);
    vm.startPrank(maker);
    kdl.depositFunds(dynamic([IERC20(outbound)]), dynamic([uint(offeredVolume)]));
    // Only allow filling up with half the volume.
    // fixme strange to do a deposit and then a withdraw
    withdrawFunds(outbound, uint(kdl.pending(ba)) / 2, maker);
    vm.stopPrank();

    heal(midWants, midGives, densityMidBid / 2, densityMidAsk / 2);

    // verify status and prices
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_heal_ask_1() public {
    test_heal_ba(Ask, 1, dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
  }

  function test_heal_bid_1() public {
    test_heal_ba(Bid, 1, dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_heal_ask_3() public {
    test_heal_ba(Ask, 3, dynamic([uint(1), 1, 1, 1, 1, 0, 0, 0, 2, 2]));
  }

  function test_heal_bid_3() public {
    test_heal_ba(Bid, 3, dynamic([uint(1), 1, 0, 0, 0, 2, 2, 2, 2, 2]));
  }

  function populateSingle(uint index, uint base, uint quote, uint pivotId, uint lastBidIndex, bytes memory expectRevert)
    internal
  {
    Kandel.Params memory params = GetParams(kdl);
    populateSingle(index, base, quote, pivotId, lastBidIndex, params.length, params.ratio, params.spread, expectRevert);
  }

  function populateSingle(
    uint index,
    uint base,
    uint quote,
    uint pivotId,
    uint lastBidIndex,
    uint kandelSize,
    uint ratio,
    uint spread,
    bytes memory expectRevert
  ) internal {
    CoreKandel.Distribution memory distribution;
    distribution.indices = new uint[](1);
    distribution.baseDist = new uint[](1);
    distribution.quoteDist = new uint[](1);
    uint[] memory pivotIds = new uint[](1);

    distribution.indices[0] = index;
    distribution.baseDist[0] = base;
    distribution.quoteDist[0] = quote;
    pivotIds[0] = pivotId;
    vm.prank(maker);
    if (expectRevert.length > 0) {
      vm.expectRevert(expectRevert);
    }
    kdl.populate{value: 0.1 ether}(
      distribution,
      pivotIds,
      lastBidIndex,
      uint8(kandelSize),
      uint16(ratio),
      uint8(spread),
      new IERC20[](0),
      new uint[](0)
    );
  }

  function test_populate_retracts_at_zero() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);

    populateSingle(index, 123, 0, 0, 5, bytes(""));
    // Bid should be retracted
    assertStatus(index, OfferStatus.Dead);
  }

  function test_populate_density_too_low_reverted() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    populateSingle(index, 1, 123, 0, 5, "mgv/writeOffer/density/tooLow");
  }

  function test_populate_existing_offer_is_updated() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    uint offerId = kdl.offerIdOfIndex(Bid, index);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);

    populateSingle(index, bid.wants() * 2, bid.gives() * 2, 0, 5, "");

    uint offerIdPost = kdl.offerIdOfIndex(Bid, index);
    assertEq(offerIdPost, offerId, "offerId should be unchanged (offer updated)");
    MgvStructs.OfferPacked bidPost = kdl.getOffer(Bid, index);
    assertEq(bidPost.gives(), bid.gives() * 2, "gives should be changed");
  }

  function test_posthook_density_too_low_still_posts_to_dual() public {
    uint index = 4;
    uint offerId = kdl.offerIdOfIndex(Bid, index);

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
    uint offerId = kdl.offerIdOfIndex(Bid, index);

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
    uint offerId = kdl.offerIdOfIndex(Bid, index);

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

  function GetParams(CoreKandel aKandel) internal view returns (Kandel.Params memory params) {
    (
      uint16 gasprice,
      uint24 gasreq,
      uint16 ratio,
      uint16 compoundRateBase,
      uint16 compoundRateQuote,
      uint8 spread,
      uint8 length
    ) = aKandel.params();

    params.gasprice = gasprice;
    params.gasreq = gasreq;
    params.ratio = ratio;
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;
    params.spread = spread;
    params.length = length;
  }

  CoreKandel.Distribution emptyDist;
  uint[] empty = new uint[](0);

  function test_populate_can_get_set_params_keeps_offers() public {
    Kandel.Params memory params = GetParams(kdl);

    uint offeredVolumeBase = kdl.offeredVolume(Ask);
    uint offeredVolumeQuote = kdl.offeredVolume(Bid);

    vm.startPrank(maker);
    // expectFrom(address(kdl));
    // emit SetParams(params.length, params.spread + 1, params.ratio + 1);

    kdl.populate(
      emptyDist, empty, 0, params.length, params.ratio + 1, params.spread + 1, new IERC20[](0), new uint[](0)
    );
    kdl.setCompoundRates(params.compoundRateBase + 1, params.compoundRateQuote + 1);
    vm.stopPrank();

    Kandel.Params memory params_ = GetParams(kdl);

    assertEq(params_.gasprice, params.gasprice, "gasprice cannot be changed");
    assertEq(params_.length, params.length, "length should not be changed");
    assertEq(params_.ratio, params.ratio + 1, "ratio should be changed");
    assertEq(params_.compoundRateBase, params.compoundRateBase + 1, "compoundRateBase should be changed");
    assertEq(params_.compoundRateQuote, params.compoundRateQuote + 1, "compoundRateQuote should be changed");
    assertEq(params_.spread, params.spread + 1, "spread should be changed");
    assertEq(offeredVolumeBase, kdl.offeredVolume(Ask), "ask volume should be unchanged");
    assertEq(offeredVolumeQuote, kdl.offeredVolume(Bid), "ask volume should be unchanged");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]), type(uint).max, type(uint).max);
  }

  function test_populate_throws_on_invalid_ratio() public {
    uint precision = kdl.PRECISION();
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidRatio");
    kdl.populate(emptyDist, empty, 0, 10, uint16(10 ** precision - 1), 0, new IERC20[](0), new uint[](0));
  }

  function test_populate_throws_on_invalid_spread_low() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.populate(emptyDist, empty, 0, 10, 10800, 0, new IERC20[](0), new uint[](0));
  }

  function test_populate_throws_on_invalid_spread_high() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.populate(emptyDist, empty, 0, 10, 10800, 9, new IERC20[](0), new uint[](0));
  }

  function test_setCompoundRatesBase_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateBase");
    kdl.setCompoundRates(2 ** 16 - 1, 0);
  }

  function test_setCompoundRatesQuote_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateQuote");
    kdl.setCompoundRates(0, 2 ** 16 - 1);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate0() public {
    test_populate_can_repopulate_other_size_and_other_params(0, 0);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate1() public {
    test_populate_can_repopulate_other_size_and_other_params(10_000, 10_000);
  }

  function test_populate_can_repopulate_other_size_and_other_params(uint16 compoundRateBase, uint16 compoundRateQuote)
    internal
  {
    vm.startPrank(maker);
    kdl.retractOffers(0, 10);

    uint16 ratio = uint16(102 * 10 ** kdl.PRECISION() / 100);
    (CoreKandel.Distribution memory distribution,) =
      KandelLib.calculateDistribution(0, 5, initBase, initQuote, ratio, kdl.PRECISION());

    kdl.populate(distribution, dynamic([uint(0), 1, 2, 3, 4]), 2, 5, ratio, 2, new IERC20[](0), new uint[](0));

    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);
    vm.stopPrank();
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

  function test_setGasprice() public {
    vm.prank(maker);
    kdl.setGasprice(42);
    (uint16 gasprice,,,,,,) = kdl.params();
    assertEq(gasprice, uint16(42), "Incorrect gasprice in params");
  }

  function test_setGasreq() public {
    vm.prank(maker);
    kdl.setGasreq(42);
    (, uint24 gasreq,,,,,) = kdl.params();
    assertEq(gasreq, uint24(42), "Incorrect gasprice in params");
  }

  function deployOtherKandel(uint base0, uint quote0, uint16 ratio, uint8 spread, uint8 kandelSize) internal {
    address otherMaker = freshAddress();

    CoreKandel otherKandel = __deployKandel__(otherMaker);

    vm.startPrank(otherMaker);
    base.approve(address(otherKandel), type(uint).max);
    quote.approve(address(otherKandel), type(uint).max);
    vm.stopPrank();

    uint totalProvision = (
      otherKandel.getMissingProvision(base, quote, otherKandel.offerGasreq(), bufferedGasprice, 0)
        + otherKandel.getMissingProvision(quote, base, otherKandel.offerGasreq(), bufferedGasprice, 0)
    ) * 10 ether;

    deal(otherMaker, totalProvision);

    (CoreKandel.Distribution memory distribution,) =
      KandelLib.calculateDistribution(0, kandelSize, base0, quote0, ratio, otherKandel.PRECISION());

    vm.startPrank(otherMaker);
    otherKandel.populate{value: totalProvision}(
      distribution, new uint[](kandelSize), kandelSize / 2, kandelSize, ratio, spread, new IERC20[](0), new uint[](0)
    );
    vm.stopPrank();

    uint pendingBase = uint(-otherKandel.pending(Ask));
    uint pendingQuote = uint(-otherKandel.pending(Bid));
    deal($(base), otherMaker, pendingBase);
    deal($(quote), otherMaker, pendingQuote);

    vm.startPrank(otherMaker);
    otherKandel.depositFunds(dynamic([IERC20(base), quote]), dynamic([pendingBase, pendingQuote]));
    vm.stopPrank();
  }

  struct TestPivot {
    uint8 kandelSize;
    uint lastBidIndex;
    uint funds;
    uint16 ratio;
    uint[] pivotIds;
    uint gas0Pivot;
    uint gasPivots;
    uint baseAmountRequired;
    uint quoteAmountRequired;
    uint snapshotId;
  }

  function test_estimate_pivots_saves_gas() public {
    vm.startPrank(maker);
    kdl.retractOffers(0, 10);
    withdrawFunds(quote, uint(kdl.pending(Bid)), address(this));
    withdrawFunds(base, uint(kdl.pending(Ask)), address(this));
    vm.stopPrank();

    TestPivot memory t;
    t.ratio = uint16(108 * 10 ** kdl.PRECISION() / 100);
    t.kandelSize = 100;
    t.lastBidIndex = t.kandelSize / 2;
    t.funds = 20 ether;

    // Make sure there are some other offers that can end up as pivots
    deployOtherKandel(initBase + 1, initQuote + 1, t.ratio, STEP, t.kandelSize);
    deployOtherKandel(initBase + 100, initQuote + 100, t.ratio, STEP, t.kandelSize);

    (CoreKandel.Distribution memory distribution,) = KandelLib.calculateDistribution({
      from: 0,
      to: t.kandelSize,
      initBase: initBase,
      initQuote: initQuote,
      ratio: t.ratio,
      precision: kdl.PRECISION()
    });

    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    (t.pivotIds, t.baseAmountRequired, t.quoteAmountRequired) =
      KandelLib.estimatePivotsAndRequiredAmount(distribution, kdl, t.lastBidIndex, t.kandelSize, t.ratio, 1, t.funds);
    require(vm.revertTo(t.snapshotId), "snapshot restore failed");

    deal($(base), maker, t.baseAmountRequired);
    deal($(quote), maker, t.quoteAmountRequired);
    IERC20[] memory depositTokens = dynamic([IERC20(base), quote]);
    uint[] memory depositAmounts = dynamic([uint(t.baseAmountRequired), t.quoteAmountRequired]);

    // with 0 pivots
    t.snapshotId = vm.snapshot();
    vm.prank(maker);
    t.gas0Pivot = gasleft();
    kdl.populate{value: t.funds}({
      distribution: distribution,
      lastBidIndex: t.lastBidIndex,
      kandelSize: t.kandelSize,
      ratio: t.ratio,
      spread: 1,
      pivotIds: new uint[](t.kandelSize),
      depositTokens: depositTokens,
      depositAmounts: depositAmounts
    });
    t.gas0Pivot = t.gas0Pivot - gasleft();

    require(vm.revertTo(t.snapshotId), "second snapshot restore failed");

    // with pivots
    vm.prank(maker);
    t.gasPivots = gasleft();
    kdl.populate{value: t.funds}({
      distribution: distribution,
      lastBidIndex: t.lastBidIndex,
      kandelSize: t.kandelSize,
      ratio: t.ratio,
      spread: 1,
      pivotIds: t.pivotIds,
      depositTokens: depositTokens,
      depositAmounts: depositAmounts
    });
    t.gasPivots = t.gasPivots - gasleft();

    assertEq(0, kdl.pending(OfferType.Ask), "required base amount should be deposited");
    assertEq(0, kdl.pending(OfferType.Bid), "required quote amount should be deposited");

    console.log("No pivot populate: %s PivotPopulate: %s", t.gas0Pivot, t.gasPivots);

    assertLt(t.gasPivots, t.gas0Pivot, "Providing pivots should save gas");
  }
}
