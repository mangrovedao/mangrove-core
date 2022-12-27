// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  ExplicitKandel,
  AbstractKandel,
  MgvStructs,
  IMangrove
} from "mgv_src/strategies/offer_maker/market_making/kandel/ExplicitKandel.sol";

contract ExplicitKandelTest is MangroveTest {
  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  ExplicitKandel kdl;
  uint[] baseDist = new uint[](10);
  uint[] quoteDist = new uint[](10);

  uint constant GASREQ = 150_000;

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
      nslots: 10,
      gasreq: GASREQ
    });
    kdl.activate(dynamic([IERC20(weth), usdc]));
    vm.stopPrank();

    // giving funds to Kandel strat
    deal($(weth), $(kdl), cash(weth, 10));
    deal($(usdc), $(kdl), cash(usdc, 12_000));

    // funding Kandel on Mangrove
    uint provAsk = kdl.getMissingProvision(weth, usdc, 0, kdl.offerGasreq(), 0);
    uint provBid = kdl.getMissingProvision(usdc, weth, 0, kdl.offerGasreq(), 0);
    mgv.fund{value: (provAsk + provBid) * 10}(address(kdl));

    // volume distribution between index [0,5[ and [5,10[ are geometric progression with ratio 1.1 and 1/1.1 respectively
    fillGeometricDist(0.1 ether, 110, 0, 5, baseDist);
    fillGeometricDist(baseDist[4], 91, 5, 10, baseDist);
    // pmin = 800 USDC/ETH ; pmax = 1600 USDC/ETH
    // qmin/bmin = 800 --> qmin = 800*0.1 = 80
    // pmax = 1600 = pmin*r**9 --> r**9 = 2 --> r = e^log(2)/9 ~ 1.08
    fillGeometricDist(cash(usdc, 800), 108, 0, 10, quoteDist);
    //turning price distribution into quote volumes
    for (uint i = 0; i < 10; i++) {
      quoteDist[i] = (quoteDist[i] * baseDist[i]) / (10 ** 18);
    }
    uint[][2] memory dist;
    dist[0] = baseDist;
    dist[1] = quoteDist;
    vm.startPrank(maker);
    kdl.setDistribution(0, 10, dist);
    kdl.populate(0, 10, 4, 0, dynamic([uint(0), 1, 2, 3, 4, 0, 1, 2, 3, 4]));
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

  function test_populates_order_book_correctly() public {
    printOrderBook($(weth), $(usdc));
    printOrderBook($(usdc), $(weth));
    assertStatus([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]);
  }

  function test_first_bid_complete_fill() public {
    (uint successes, uint takerGot, uint takerGave,,) = sellToBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]);
    // since ask[5] is already there (at the correct volume) all the base brought by taker become pending
    assertEq(kdl.pendingBase(), takerGave, "Incorrect pending");
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]);
  }

  function test_first_ask_complete_fill() public {
    (uint successes, uint takerGot, uint takerGave,,) = buyFromBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]);
    // since bid[4] is already there (at the correct volume) all the quote brought by taker become pending
    assertEq(kdl.pendingQuote(), takerGave, "Incorrect pending");
  }

  function test_bid_produces_an_ask() public {
    sellToBestAs(taker, 1 ether);
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]);
  }

  function test_pendingBase_is_used_for_asks() public {
    sellToBestAs(taker, 1 ether);
    // this generates pendingBase because the dual of the first bid is already posted
    uint pending = kdl.pendingBase();
    sellToBestAs(taker, 1 ether);
    // this second offer should tap into pending to post the ask
    assertTrue(pending > kdl.pendingBase(), "Incorrect pending");
  }

  function test_ask_produces_a_bid() public {
    buyFromBestAs(taker, 1 ether);
    (uint successes, uint takerGot,,,) = buyFromBestAs(taker, 1 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus([uint(1), 1, 1, 1, 1, 1, 0, 2, 2, 2]);
  }

  function test_pendingQuote_is_used_for_bids() public {
    buyFromBestAs(taker, 1 ether);
    uint pending = kdl.pendingQuote();
    buyFromBestAs(taker, 1 ether);
    assertTrue(pending > kdl.pendingQuote(), "Incorrect pending");
  }

  function test_logs_all_asks() public {
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
    assertStatus([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]);
  }
}
