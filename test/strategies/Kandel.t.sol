// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  AbstractKandel, Kandel, MgvStructs, IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

contract ExplicitKandelTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  Kandel kdl;
  uint[] baseDist = new uint[](10);
  uint[] quoteDist = new uint[](10);

  uint constant GASREQ = 160_000;

  event AllAsks(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);

  function setUp() public override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;
    options.defaultFee = 30;

    // deploying mangrove and opening WETH/USDC market.
    super.setUp();
    // rename for convenience
    weth = base;
    usdc = quote;

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(weth), taker, cash(weth, 50));
    deal($(usdc), taker, cash(usdc, 100_000));

    // taker approves mangrove to be able to take offers
    vm.startPrank(taker);
    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();

    // deploy and activate
    vm.prank(maker);
    kdl = new Kandel({
      mgv: IMangrove($(mgv)), 
      base: weth,
      quote: usdc,
      nslots: 10,
      gasreq: GASREQ
    });

    // giving funds to Kandel strat
    deal($(weth), $(kdl), cash(weth, 10));
    deal($(usdc), $(kdl), cash(usdc, 12_000));

    // funding Kandel on Mangrove
    uint provAsk = kdl.getMissingProvision(weth, usdc, kdl.offerGasreq(), 0, 0);
    uint provBid = kdl.getMissingProvision(usdc, weth, kdl.offerGasreq(), 0, 0);
    deal(maker, (provAsk + provBid) * 10 ether);

    deal($(weth), address(this), 1 ether);
    deal($(usdc), address(this), cash(usdc, 10_000));

    weth.approve(address(kdl), type(uint).max);
    usdc.approve(address(kdl), type(uint).max);

    kdl.depositFunds(AbstractKandel.OrderType.Ask, 1 ether);
    kdl.depositFunds(AbstractKandel.OrderType.Bid, cash(usdc, 10_000));

    vm.startPrank(maker);
    kdl.populate{value: (provAsk + provBid) * 10}({
      from: 0,
      to: 10,
      lastBidIndex: 4,
      ratio: uint16(108 * 10 ** kdl.PRECISION() / 100),
      spread: 1,
      gasprice: 0,
      initQuote: cash(usdc, 100), // quote given/wanted at index from
      baseDist: dynamic(
        [
          uint(0.1 ether),
          0.1 ether,
          0.1 ether,
          0.1 ether,
          0.1 ether,
          uint(0.1 ether),
          0.1 ether,
          0.1 ether,
          0.1 ether,
          0.1 ether
        ]
        ), // base distribution in [from, to[
      pivotIds: dynamic([uint(0), 1, 2, 3, 4, 0, 1, 2, 3, 4])
    });
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
    uint offerId = kdl.offerIdOfIndex(AbstractKandel.OrderType.Ask, index);
    vm.prank(taker_);
    return mgv.snipes($(weth), $(usdc), wrap_dynamic([offerId, amount, type(uint96).max, type(uint).max]), true);
  }

  function snipeSellAs(address taker_, uint amount, uint index) internal returns (uint, uint, uint, uint, uint) {
    uint offerId = kdl.offerIdOfIndex(AbstractKandel.OrderType.Bid, index);
    vm.prank(taker_);
    return mgv.snipes($(usdc), $(weth), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
  }

  function assertStatus(
    uint[10] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead
  ) internal {
    for (uint i = 0; i < 10; i++) {
      (MgvStructs.OfferPacked bid,) = kdl.getOffer(AbstractKandel.OrderType.Bid, i);
      (MgvStructs.OfferPacked ask,) = kdl.getOffer(AbstractKandel.OrderType.Ask, i);
      if (offerStatuses[i] == 0) {
        assertTrue(bid.gives() == 0 && ask.gives() == 0, "offer at index is live");
      } else {
        if (offerStatuses[i] == 1) {
          assertTrue(bid.gives() > 0 && ask.gives() == 0, "Kandel not bidding at index");
        } else {
          if (offerStatuses[i] == 2) {
            assertTrue(bid.gives() == 0 && ask.gives() > 0, "Kandel is not asking at index");
          } else {
            assertTrue(bid.gives() > 0 && ask.gives() > 0, "Kandel is not crossed at index");
          }
        }
      }
    }
  }

  function printOB() internal view {
    printOrderBook($(weth), $(usdc));
    printOrderBook($(usdc), $(weth));
    (uint pendingBase, uint pendingQuote,,,) = kdl.params();

    console.log("-------", toUnit(pendingBase, 18), toUnit(pendingQuote, 6), "-------");
  }

  AbstractKandel.OrderType constant Ask = AbstractKandel.OrderType.Ask;
  AbstractKandel.OrderType constant Bid = AbstractKandel.OrderType.Bid;

  function pending(AbstractKandel.OrderType ba) internal view returns (uint) {
    (uint pendingBase, uint pendingQuote,,,) = kdl.params();
    return ba == Ask ? pendingBase : pendingQuote;
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]);
  }

  function test_bid_complete_fill(uint16 c) public {
    vm.assume(c <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRate(c);

    (uint successes, uint takerGot, uint takerGave,,) = sellToBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]);
    (MgvStructs.OfferPacked offer,) = kdl.getOffer(Ask, 5);
    if (c == 10_000) {
      assertEq(pending(Ask), 0, "Full compounding should not yield pending");
    } else {
      if (c == 0) {
        assertEq(offer.gives(), takerGave, "No compounding should give what taker gave");
      }
      assertTrue(pending(Ask) > 0, "Partial auto compounding should yield pending");
      assertTrue(offer.gives() > takerGave, "Auto compounding should give more than what taker gave");
    }
  }

  function test_ask_complete_fill(uint16 c) public {
    vm.assume(c <= 10_000);
    vm.prank(maker);
    kdl.setCompoundRate(c);

    (MgvStructs.OfferPacked oldBid,) = kdl.getOffer(Bid, 4);

    (uint successes, uint takerGot, uint takerGave,, uint fee) = buyFromBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    //assertStatus([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]);
    (MgvStructs.OfferPacked newBid,) = kdl.getOffer(Bid, 4);
    assertTrue(newBid.gives() <= takerGave + oldBid.gives(), "Cannot give more than what was received");
    assertEq(pending(Bid) + newBid.gives(), oldBid.gives() + takerGave, "Incorrect net promised asset");
    if (c == 10_000) {
      assertEq(pending(Bid), 0, "Full compounding should not yield pending");
    } else {
      assertTrue(pending(Bid) > 0, "Partial auto compounding should yield pending");
      assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should give more than what taker gave");
    }
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]);
  }

  function test_logs_all_asks() public {
    // taking all bids
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllAsks(IMangrove($(mgv)), weth, usdc);
    sellToBestAs(taker, 1 ether);
    assertStatus([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]);
  }

  function test_logs_all_bids() public {
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllBids(IMangrove($(mgv)), weth, usdc);
    buyFromBestAs(taker, 1 ether);
    assertStatus([uint(0), 1, 1, 1, 1, 1, 1, 1, 1, 1]);
  }

  function test_take_new_offer() public {
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    assertStatus([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]);
    buyFromBestAs(taker, 1 ether);
    assertStatus([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]);
  }
}
