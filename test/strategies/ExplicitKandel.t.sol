// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  AbstractKandel,
  ExplicitKandel,
  MgvStructs,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";

contract ExplicitKandelTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  ExplicitKandel kdl;
  uint[] baseDist = new uint[](12);
  uint[] quoteDist = new uint[](12);

  uint constant GASREQ = 160_000;

  event AllAsks(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);

  function fillGeometricDist(uint startValue, uint ratio, uint from, uint to, uint[] storage dist) internal {
    dist[from] = startValue;
    for (uint i = from + 1; i < to; i++) {
      dist[i] = (dist[i - 1] * ratio) / 100;
    }
  }

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
    vm.startPrank(maker);
    kdl = new ExplicitKandel({
      mgv: IMangrove($(mgv)), 
      base: weth,
      quote: usdc,
      nslots: 12,
      gasreq: GASREQ
    });
    kdl.activate(dynamic([IERC20(weth), usdc]));
    vm.stopPrank();

    // giving funds to Kandel strat
    deal($(weth), $(kdl), cash(weth, 10));
    deal($(usdc), $(kdl), cash(usdc, 12_000));

    // volume distribution between index [0,5[ and [5,10[ are geometric progression with ratio 1.1 and 1/1.1 respectively
    fillGeometricDist(0.1 ether, 110, 0, 6, baseDist);
    fillGeometricDist(baseDist[4], 91, 6, 12, baseDist);
    // pmin = 800 USDC/ETH ; pmax = 1600 USDC/ETH
    // qmin/bmin = 800 --> qmin = 800*0.1 = 80
    // pmax = 1600 = pmin*r**9 --> r**9 = 2 --> r = e^log(2)/9 ~ 1.08
    fillGeometricDist(cash(usdc, 800), 108, 0, 12, quoteDist);
    //turning price distribution into quote volumes
    for (uint i = 0; i < 12; i++) {
      quoteDist[i] = (quoteDist[i] * baseDist[i]) / (10 ** 18);
    }
    uint[][2] memory dist;
    dist[0] = baseDist;
    dist[1] = quoteDist;

    // funding Kandel on Mangrove
    uint provAsk = kdl.getMissingProvision(weth, usdc, kdl.offerGasreq(), 0, 0);
    uint provBid = kdl.getMissingProvision(usdc, weth, kdl.offerGasreq(), 0, 0);
    deal(maker, (provAsk + provBid) * 12 ether);

    vm.startPrank(maker);
    kdl.setDistribution(0, 12, dist);
    // leaving first and last price slot unpopulated
    kdl.populate{value: (provAsk + provBid) * 12}(1, 11, 5, 0, dynamic([uint(0), 1, 2, 3, 4, 0, 1, 2, 3, 4]));
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
    uint[12] memory offerStatuses // 1:bid 2:ask 3:crossed 0:dead
  ) internal {
    for (uint i = 0; i < 12; i++) {
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
    console.log("-------", toUnit(kdl.pendingBase(), 18), toUnit(kdl.pendingQuote(), 6), "-------");
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 0]);
  }

  function test_first_bid_complete_fill() public {
    (uint successes, uint takerGot, uint takerGave,,) = sellToBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(0), 1, 1, 1, 1, 0, 2, 2, 2, 2, 2, 0]);
    // since ask[5] is already there (at the correct volume) all the base brought by taker become pending
    assertEq(kdl.pendingBase(), takerGave, "Incorrect pending");
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 0]);
  }

  function test_first_ask_complete_fill() public {
    (uint successes, uint takerGot, uint takerGave,,) = buyFromBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(0), 1, 1, 1, 1, 1, 0, 2, 2, 2, 2, 0]);
    // since bid[4] is already there (at the correct volume) all the quote brought by taker become pending
    assertEq(kdl.pendingQuote(), takerGave, "Incorrect pending");
  }

  function test_bid_produces_an_ask() public {
    sellToBestAs(taker, 1 ether);
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(0), 1, 1, 1, 0, 2, 2, 2, 2, 2, 2, 0]);
  }

  function test_pendingBase_is_used_for_asks() public {
    printOB();
    //assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 0]);
    vm.startPrank(maker);
    kdl.pushPending(AbstractKandel.OrderType.Ask, 0.5 ether);
    kdl.setDistribution(6, 7, [dynamic([uint(3 ether)]), dynamic([uint(cash(usdc, 1000))])]);
    vm.stopPrank();

    sellToBestAs(taker, 1 ether);
    // this second offer should tap into pending to post the ask
    printOB();
    assertEq(kdl.pendingBase(), 0, "Incorrect pending");
  }

  function test_ask_produces_a_bid() public {
    buyFromBestAs(taker, 1 ether);
    (uint successes, uint takerGot,,,) = buyFromBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(0), 1, 1, 1, 1, 1, 1, 0, 2, 2, 2, 0]);
  }

  function test_pendingQuote_is_used_for_bids() public {
    //assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 0]);
    vm.startPrank(maker);
    kdl.pushPending(AbstractKandel.OrderType.Bid, 10 ** 6);
    kdl.setDistribution(5, 6, [dynamic([uint(2 ether)]), dynamic([uint(cash(usdc, 10000))])]);
    vm.stopPrank();

    buyFromBestAs(taker, 1 ether);
    assertEq(kdl.pendingQuote(), 0, "Incorrect pending");
  }

  function test_logs_all_asks() public {
    // filling first price slot
    vm.startPrank(maker);
    kdl.populate(0, 1, 5, 0, dynamic([kdl.offerIdOfIndex(AbstractKandel.OrderType.Bid, 1)]));
    vm.stopPrank();
    // taking all bids
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllAsks(IMangrove($(mgv)), weth, usdc);
    sellToBestAs(taker, 1 ether);
    assertStatus([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0]);
  }

  function test_logs_all_bids() public {
    // filling last price slot
    vm.startPrank(maker);
    kdl.populate(11, 12, 5, 0, dynamic([kdl.offerIdOfIndex(AbstractKandel.OrderType.Ask, 10)]));
    vm.stopPrank();
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    expectFrom(address(kdl));
    emit AllBids(IMangrove($(mgv)), weth, usdc);
    buyFromBestAs(taker, 1 ether);
    assertStatus([uint(0), 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0]);
  }

  function multiplyVolumeAtIndex(uint index, uint factor) internal view returns (uint[][2] memory dist) {
    dist[1] = dynamic([(kdl.quoteOfIndex(index) * factor) / 100]);
    dist[0] = dynamic([(kdl.baseOfIndex(index) * factor) / 100]);
  }

  function test_change_and_populate_dist_index() public {
    vm.startPrank(maker);
    (uint old_base, uint old_quote) = (kdl.baseOfIndex(4), kdl.quoteOfIndex(4));
    uint[][2] memory dist = multiplyVolumeAtIndex(4, 200);
    kdl.setDistribution(4, 5, dist);
    kdl.populate(4, 5, 4, 0, dynamic([kdl.offerIdOfIndex(AbstractKandel.OrderType.Bid, 4)]));
    vm.stopPrank();
    (MgvStructs.OfferPacked offer,) = kdl.getOffer(AbstractKandel.OrderType.Bid, 4);
    assertEq(offer.gives(), old_quote * 2, "Incorrect gives");
    assertEq(offer.wants(), old_base * 2, "incorrect wants");
  }

  function test_change_and_lazy_populate_dist_index() public {
    sellToBestAs(taker, 1 ether);
    // MM state:
    // [0, 1, 1, 1, 1, 0, 2, 2, 2, 2, 2,0]);
    // pendingBase > 0
    vm.startPrank(maker);
    (uint old_base, uint old_quote) = (kdl.baseOfIndex(5), kdl.quoteOfIndex(5));
    uint[][2] memory dist = multiplyVolumeAtIndex(5, 200);
    kdl.setDistribution(5, 6, dist);
    // putting 1000$ in pendingQuote so that Kandel auto updates volume
    kdl.pushPending(AbstractKandel.OrderType.Bid, 1000 * 10 ** 6);
    vm.stopPrank();
    buyFromBestAs(taker, 1 ether);
    (MgvStructs.OfferPacked offer,) = kdl.getOffer(AbstractKandel.OrderType.Bid, 5);
    assertEq(offer.gives(), old_quote * 2, "Incorrect gives");
    assertEq(offer.wants(), old_base * 2, "incorrect wants");
  }

  function test_snipeSell_does_not_use_pending() public {
    vm.startPrank(maker);
    kdl.pushPending(AbstractKandel.OrderType.Ask, 1 ether);
    kdl.retractOffer(AbstractKandel.OrderType.Bid, 2, false);
    vm.stopPrank();

    assertStatus([uint(0), 1, 0, 1, 1, 1, 2, 2, 2, 2, 2, 0]);

    (uint successes,, uint takerGave,,) = snipeSellAs(taker, 1 ether, 1);
    assertTrue(successes == 1, "snipe failed");
    assertStatus([uint(0), 0, 2, 1, 1, 1, 2, 2, 2, 2, 2, 0]);
    (MgvStructs.OfferPacked offer,) = kdl.getOffer(AbstractKandel.OrderType.Ask, 2);
    assertEq(offer.gives(), takerGave, "wrong gives");
    assertEq(1 ether, kdl.pendingBase(), "incorrect pending");
  }

  function test_populate_at_zero_retracts_offer() public {
    vm.prank(maker);
    kdl.setDistribution(7, 8, [dynamic([uint(0)]), dynamic([uint(0)])]);

    vm.prank(maker);
    kdl.populate(7, 8, 5, 0, dynamic([uint(0)]));
    assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 0, 2, 2, 2, 0]);
  }

  function test_snipeBuy_does_not_use_pending() public {
    // [0, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2,0]);
    vm.startPrank(maker);
    kdl.pushPending(AbstractKandel.OrderType.Bid, 1000 * 10 ** 6);
    kdl.retractOffer(AbstractKandel.OrderType.Ask, 7, false);
    vm.stopPrank();
    assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 0, 2, 2, 2, 0]);
    // call below posts a (dual) bid at index 7
    (uint successes,, uint takerGave,,) = snipeBuyAs(taker, 1 ether, 8);
    assertTrue(successes == 1, "snipe failed");
    assertStatus([uint(0), 1, 1, 1, 1, 1, 2, 1, 0, 2, 2, 0]);
    (MgvStructs.OfferPacked offer,) = kdl.getOffer(AbstractKandel.OrderType.Bid, 7);
    assertEq(offer.gives(), takerGave, "wrong gives");
    assertEq(1000 * 10 ** 6, kdl.pendingQuote(), "incorrect pending");
  }

  function test_take_new_offer() public {
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    assertStatus([uint(0), 1, 1, 1, 0, 2, 2, 2, 2, 2, 2, 0]);
    buyFromBestAs(taker, 1 ether);
    assertStatus([uint(0), 1, 1, 1, 1, 0, 2, 2, 2, 2, 2, 0]);
  }
}
