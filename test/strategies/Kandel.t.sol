// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

// FIXME outstanding missing feature/tests
// * Populates:
//   * by chunks
//   * use pending and freed funds
//   * throws if not enough collateral
//   * throws if not enough provision
// * Retract offers
// * newOffer below density creates pending
// * overflow in dual offer computation is correctly managed

import "mgv_test/lib/MangroveTest.sol";
import {
  AbstractKandel, Kandel, MgvStructs, IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";
import {KandelLib} from "mgv_lib/kandel/KandelLib.sol";

contract KandelTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  Kandel kdl;

  uint constant GASREQ = 77_000;
  uint8 constant STEP = 1;
  uint initQuote;
  uint immutable initBase = uint(0.1 ether);

  event AllAsks();
  event AllBids();
  event NewKandel(address indexed owner, IMangrove indexed mgv, IERC20 indexed base, IERC20 quote);

  function setUp() public virtual override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    // deploying mangrove and opening WETH/USDC market.
    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    initQuote = cash(usdc, 100); // quote given/wanted at index from

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(weth), taker, cash(weth, 50));
    deal($(usdc), taker, cash(usdc, 70_000));

    // taker approves mangrove to be able to take offers
    vm.startPrank(taker);
    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();

    // deploy and activate
    (MgvStructs.GlobalPacked global,) = mgv.config(address(0), address(0));
    vm.expectEmit(true, true, true, true);
    emit NewKandel(maker, IMangrove($(mgv)), weth, usdc);
    vm.prank(maker);
    kdl = new Kandel({
      mgv: IMangrove($(mgv)), 
      base: weth,
      quote: usdc,
      gasreq: GASREQ,
      gasprice: 10 * global.gasprice() // covering 10 times Mangrove's gasprice at deploy time
    });

    // giving funds to Kandel strat
    deal($(weth), $(kdl), cash(weth, 10));
    deal($(usdc), $(kdl), cash(usdc, 12_000));

    // funding Kandel on Mangrove
    uint provAsk = kdl.getMissingProvision(weth, usdc, kdl.offerGasreq(), 10 * global.gasprice(), 0);
    uint provBid = kdl.getMissingProvision(usdc, weth, kdl.offerGasreq(), 10 * global.gasprice(), 0);
    deal(maker, (provAsk + provBid) * 10 ether);

    deal($(weth), address(this), 1 ether);
    deal($(usdc), address(this), cash(usdc, 10_000));

    weth.approve(address(kdl), type(uint).max);
    usdc.approve(address(kdl), type(uint).max);

    kdl.depositFunds(AbstractKandel.OfferType.Ask, 1 ether);
    kdl.depositFunds(AbstractKandel.OfferType.Bid, cash(usdc, 10_000));

    vm.startPrank(maker);
    KandelLib.populate({
      kandel: kdl,
      from: 0,
      to: 10,
      lastBidIndex: 4,
      kandelSize: 10,
      ratio: uint16(108 * 10 ** kdl.PRECISION() / 100),
      spread: STEP,
      initBase: initBase,
      initQuote: initQuote,
      pivotIds: dynamic([uint(0), 1, 2, 3, 4, 0, 1, 2, 3, 4]),
      funds: (provAsk + provBid) * 10
    });
    // call above is over provisioned. Withdrawing remainder to simplify tests below.
    kdl.withdrawFunds(Bid, pending(Bid), address(this));
    kdl.withdrawFunds(Ask, pending(Ask), address(this));
    vm.stopPrank();
  }

  function buyFromBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestAsk = mgv.best($(weth), $(usdc));
    vm.prank(taker_);
    return mgv.snipes($(weth), $(usdc), wrap_dynamic([bestAsk, amount, type(uint96).max, type(uint).max]), true);
  }

  function sellToBestAs(address taker_, uint amount) internal returns (uint, uint, uint, uint, uint) {
    uint bestBid = mgv.best($(usdc), $(weth));
    vm.prank(taker_);
    return mgv.snipes($(usdc), $(weth), wrap_dynamic([bestBid, 0, amount, type(uint).max]), false);
  }

  function snipeBuyAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(AbstractKandel.OfferType.Ask, index);
    vm.prank(taker_);
    return mgv.snipes($(weth), $(usdc), wrap_dynamic([offerId, amount, type(uint96).max, type(uint).max]), true);
  }

  function snipeSellAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(AbstractKandel.OfferType.Bid, index);
    vm.prank(taker_);
    return mgv.snipes($(usdc), $(weth), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
  }

  function assertStatus(
    uint[] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead
  ) internal {
    uint quote = initQuote;
    (, uint16 ratio,,,,) = kdl.params();
    for (uint i = 0; i < offerStatuses.length; i++) {
      // `price = quote / initBase` used in assertApproxEqRel below
      (MgvStructs.OfferPacked bid,) = kdl.getOffer(AbstractKandel.OfferType.Bid, i);
      (MgvStructs.OfferPacked ask,) = kdl.getOffer(AbstractKandel.OfferType.Ask, i);
      if (offerStatuses[i] == 0) {
        assertTrue(bid.gives() == 0 && ask.gives() == 0, "offer at index is live");
      } else {
        if (offerStatuses[i] == 1) {
          assertTrue(bid.gives() > 0 && ask.gives() == 0, "Kandel not bidding at index");
          assertApproxEqRel(
            bid.gives() * initBase, quote * bid.wants(), 1e11, "Bid price does not follow distribution within 0.00001%"
          );
        } else {
          if (offerStatuses[i] == 2) {
            assertTrue(bid.gives() == 0 && ask.gives() > 0, "Kandel is not asking at index");
            assertApproxEqRel(
              ask.wants() * initBase,
              quote * ask.gives(),
              1e11,
              "Ask price does not follow distribution within 0.00001%"
            );
          } else {
            assertTrue(bid.gives() > 0 && ask.gives() > 0, "Kandel is not crossed at index");
          }
        }
      }
      quote = (quote * uint(ratio)) / 10 ** kdl.PRECISION();
    }
  }

  function printOB() internal view {
    printOrderBook($(weth), $(usdc));
    printOrderBook($(usdc), $(weth));
    uint pendingBase = uint(kdl.pending(Ask));
    uint pendingQuote = uint(kdl.pending(Bid));

    console.log("-------", toUnit(pendingBase, 18), toUnit(pendingQuote, 6), "-------");
  }

  AbstractKandel.OfferType constant Ask = AbstractKandel.OfferType.Ask;
  AbstractKandel.OfferType constant Bid = AbstractKandel.OfferType.Bid;

  function pending(AbstractKandel.OfferType ba) internal view returns (uint) {
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

  function test_bid_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote) private {
    test_bid_complete_fill(compoundRateBase, compoundRateQuote, 4);
  }

  function test_bid_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote, uint index) private {
    vm.assume(compoundRateBase <= 10_000);
    vm.assume(compoundRateQuote <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    (MgvStructs.OfferPacked oldAsk,) = kdl.getOffer(Ask, index + STEP);
    uint oldPending = pending(Ask);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = sellToBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    (MgvStructs.OfferPacked newAsk,) = kdl.getOffer(Ask, index + STEP);
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

  function test_ask_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote) private {
    test_ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
  }

  function test_ask_complete_fill(uint16 compoundRateBase, uint16 compoundRateQuote, uint index) private {
    vm.assume(compoundRateBase <= 10_000);
    vm.assume(compoundRateQuote <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    (MgvStructs.OfferPacked oldBid,) = kdl.getOffer(Bid, index - STEP);
    uint oldPending = pending(Bid);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = buyFromBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    (MgvStructs.OfferPacked newBid,) = kdl.getOffer(Bid, index - STEP);
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
    // assertStatus([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]);
    sellToBestAs(taker, 1 ether);
    // assertStatus([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]);
    sellToBestAs(taker, 1 ether);
    // assertStatus([uint(1), 1, 1, 0, 0, 2, 2, 2, 2, 2]);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllAsks();
    sellToBestAs(taker, 1 ether);
    //assertStatus([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]);
  }

  function test_logs_all_bids() public {
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllBids();
    buyFromBestAs(taker, 1 ether);
    //assertStatus([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]);
  }

  function test_take_new_offer() public {
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    //    assertStatus([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]);
    buyFromBestAs(taker, 1 ether);
    //    assertStatus([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]);
  }

  enum ExpectedChange {
    Same,
    Increase,
    Decrease
  }

  function assertChange(ExpectedChange expectedChange, uint expected, uint actual, string memory descriptor) private {
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
  ) private {
    deal($(weth), taker, cash(weth, 5000));
    deal($(usdc), taker, cash(usdc, 7000000));
    uint initialTotalVolumeBase;
    uint initialTotalVolumeQuote;
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    for (uint i = 0; i < loops; i++) {
      test_ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      if (i == 0) {
        // With the ask filled, what is the current volume for bids?
        initialTotalVolumeQuote = kdl.offeredVolume(AbstractKandel.OfferType.Bid);
        console.log("Initial bids");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(
          quoteVolumeChange, initialTotalVolumeQuote, kdl.offeredVolume(AbstractKandel.OfferType.Bid), "quote volume"
        );
        console.log("Final bids");
        printOB();
      }

      test_bid_complete_fill(compoundRateBase, compoundRateQuote, 4);

      assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      if (i == 0) {
        // With the bid filled, what is the current volume for asks?
        initialTotalVolumeBase = kdl.offeredVolume(AbstractKandel.OfferType.Ask);
        console.log("Initial asks");
        printOB();
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(
          baseVolumeChange, initialTotalVolumeBase, kdl.offeredVolume(AbstractKandel.OfferType.Ask), "base volume"
        );
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
}
