// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/single_user/market_making/mango/Mango.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract MangoTest is MangroveTest {
  struct Book {
    uint[] bids;
    uint[] asks;
  }

  uint constant BASE0 = 0.34 ether;
  uint constant BASE1 = 1000 * 10**6; //because usdc decimals?
  uint constant NSLOTS = 10;
  // price increase is delta/BASE_0
  uint constant DELTA = 34 * 10**6; // because usdc decimals?

  TestToken weth;
  TestToken usdc;
  address payable maker;
  address payable taker;
  Mango mgo;

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
    vm.deal(maker, 10 ether); // to provision Mango

    taker = freshAddress("taker");
    deal($(weth), taker, cash(weth, 50));
    deal($(usdc), taker, cash(usdc, 100_000));

    // taker approves mangrove to be able to take offers
    vm.startPrank(taker);
    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    vm.stopPrank();

    vm.startPrank(maker);
    mgo = new Mango({
      mgv: IMangrove($(mgv)), // TODO: remove IMangrove dependency?
      base: weth,
      quote: usdc,
      base_0: cash(weth, 34, 2),
      quote_0: cash(usdc, 1000),
      nslots: NSLOTS,
      price_incr: DELTA,
      deployer: maker
    });
    vm.stopPrank();
  }

  /* combine all tests wince they rely on non-zero state */
  function test_all() public {
    part_deploy_strat();
    part_market_order();
    part_negative_shift();
    part_positive_shift();
    part_partial_fill();
    part_text_residual_1();
    part_text_residual_2();
    part_kill();
    part_restart_fixed_shift();
  }

  function part_deploy_strat() public prank(maker) {
    // reserve has to approve liquidity router of Mango for ETH and USDC transfer
    // since reserve here is an EOA we do it direclty
    usdc.approve($(mgo.router()), type(uint).max);
    weth.approve($(mgo.router()), type(uint).max);

    // funds come from maker's wallet by default
    // liquidity router will pull the funds from the wallet when needed
    deal($(weth), maker, cash(weth, 17));
    deal($(usdc), maker, cash(usdc, 50000));

    uint prov = mgo.getMissingProvision({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      gasreq: mgo.ofr_gasreq(),
      gasprice: 0,
      offerId: 0
    });

    mgv.fund{value: prov * 20}($(mgo));

    init(cash(usdc, 1000), cash(weth, 3, 1));

    Book memory book = get_offers(false);

    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(1), 2, 3, 4, 5, 0, 0, 0, 0, 0])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 0, 0, 0, 0, 1, 2, 3, 4, 5])
    );
  }

  function part_market_order() public prank(taker) {
    (uint got, uint gave, uint bounty, ) = mgv.marketOrder(
      $(weth),
      $(usdc),
      cash(weth, 5, 1),
      cash(usdc, 3000),
      true
    );

    Book memory book = get_offers(false);
    assertEq(
      got,
      minusFee($(weth), $(usdc), 0.5 ether),
      "incorrect received amount"
    );
    assertEq(bounty, 0, "taker should not receive bounty");
    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(1), 2, 3, 4, 5, 6, 0, 0, 0, 0])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 0, 0, 0, 0, -1, 2, 3, 4, 5])
    );

    (got, gave, bounty, ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 3500),
      cash(weth, 15, 1),
      true
    );

    assertEq(
      got,
      minusFee($(usdc), $(weth), cash(usdc, 3500)),
      "incorrect received amount"
    );

    assertEq(bounty, 0, "taker should not receive bounty");

    book = get_offers(false);

    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(1), 2, 3, 4, -5, -6, 0, 0, 0, 0])
    );

    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 0, 0, 0, 6, 1, 2, 3, 4, 5])
    );
  }

  function part_negative_shift() public prank(maker) {
    mgo.set_shift({
      s: -2,
      withBase: false,
      amounts: dynamic([cash(usdc, 1000), cash(usdc, 1000)])
    });

    Book memory book = get_offers(false);

    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(8), 7, 1, 2, 3, 4, -5, -6, 0, 0])
    );

    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(-4), -5, 0, 0, 0, 0, 6, 1, 2, 3])
    );
  }

  function part_positive_shift() public prank(maker) {
    mgo.set_shift({
      s: 3,
      withBase: true,
      amounts: dynamic([cash(weth, 3, 1), cash(weth, 3, 1), cash(weth, 3, 1)])
    });

    Book memory book = get_offers(false);

    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(2), 3, 4, -5, -6, 0, 0, -8, -7, -1])
    );

    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 0, 0, 6, 1, 2, 3, 4, 5, 7])
    );
  }

  function part_partial_fill() public {
    // scenario:
    // - set density so high that offer can no longer be updated
    // - run a market order and check that bid is not updated after ask is being consumed
    // - verify takerGave is pending
    // - put back the density and run another market order
    mgv.setDensity($(weth), $(usdc), cash(weth, 1));

    vm.prank(taker);
    (uint got, uint gave, uint bounty, ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 1, 2),
      cash(weth, 1),
      true
    );

    uint best_id = mgv.best($(weth), $(usdc));
    P.Offer.t best_offer = mgv.offers($(weth), $(usdc), best_id);
    uint old_gives = best_offer.gives();

    vm.prank(maker);
    uint pendingBase = mgo.pending()[0];

    assertEq(pendingBase, gave, "Taker liquidity should be pending");

    vm.prank(taker);
    (got, gave, bounty, ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 1, 2),
      cash(weth, 1),
      true
    );

    vm.prank(maker);
    uint pendingBase_ = mgo.pending()[0];

    assertEq(pendingBase_, pendingBase + gave, "Missing pending base");

    mgv.setDensity($(weth), $(usdc), 100);

    vm.prank(taker);
    mgv.marketOrder($(usdc), $(weth), cash(usdc, 1, 2), cash(weth, 1), true);

    vm.prank(maker);
    uint pendingBase__ = mgo.pending()[0];

    assertEq(pendingBase__, 0, "There should be no more pending base");

    best_id = mgv.best($(weth), $(usdc));
    best_offer = mgv.offers($(weth), $(usdc), best_id);

    assertEq(
      best_offer.gives(),
      old_gives + pendingBase_ + gave,
      "Incorrect given amount"
    );
  }

  function part_text_residual_1() public {
    mgv.setDensity($(usdc), $(weth), cash(usdc, 1));
    mgv.setDensity($(weth), $(usdc), cash(weth, 1));

    // market order will take the following best offer
    uint best_id = mgv.best($(usdc), $(weth));
    P.Offer.t best_offer = mgv.offers($(usdc), $(weth), best_id);

    vm.prank(taker);
    (uint got, uint gave, uint bounty, ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 100),
      cash(weth, 1),
      true
    );

    // because density reqs are so high on both semi order book, best will not be able to self repost
    // and residual will be added to USDC (quote) pending pool
    // and what taker gave will not be added in the dual offer and added to the WETH (base) pending pool

    vm.startPrank(maker);
    uint pendingBase = mgo.pending()[0];
    uint pendingQuote = mgo.pending()[1];
    vm.stopPrank();

    assertEq(gave, pendingBase, "gave was not added to pending base pool");

    assertEq(
      best_offer.gives() - cash(usdc, 100),
      pendingQuote,
      "Residual was not added to pending quote pool"
    );

    // second market order should produce the same effect (best has changed because old best was not able to repost)
    best_id = mgv.best($(usdc), $(weth));
    best_offer = mgv.offers($(usdc), $(weth), best_id);

    vm.prank(taker);
    (got, gave, bounty, ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 100),
      cash(weth, 1),
      true
    );

    vm.startPrank(maker);
    uint pendingBase_ = mgo.pending()[0];
    uint pendingQuote_ = mgo.pending()[1];
    vm.stopPrank();

    assertEq(
      pendingBase + gave,
      pendingBase_,
      "gave was not added to pending base pool"
    );
    assertEq(
      best_offer.gives() - cash(usdc, 100) + pendingQuote,
      pendingQuote_,
      "Residual was not added to pending quote pool"
    );

    // putting density back to normal
    mgv.setDensity($(usdc), $(weth), 100);
    mgv.setDensity($(weth), $(usdc), 100);

    // Offer 3 and 4 were unable to repost so they should be out of the book

    Book memory book = get_offers(false);
    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(2), -3, -4, -5, -6, 0, 0, -8, -7, -1])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 0, 0, 6, 1, 2, 3, 4, 5, 7])
    );
  }

  function part_text_residual_2() public {
    vm.startPrank(maker);
    uint pendingBase_ = mgo.pending()[0];
    uint pendingQuote_ = mgo.pending()[1];
    vm.stopPrank();

    // this market order should produce the following observables:
    // - offer 2 is now going to repost its residual which will be augmented with the content of the USDC pending pool
    // - the dual offer of offer 2 will be created with id 8 and will offer takerGave + the content of the WETH pending pool
    // - both pending pools should be empty

    P.Offer.t old_offer2 = mgv.offers($(usdc), $(weth), 2);

    vm.prank(taker);
    (, uint gave, , ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 100),
      cash(weth, 1),
      true
    );

    Book memory book = get_offers(false);
    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(2), -3, -4, -5, -6, 0, 0, -8, -7, -1])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 8, 0, 6, 1, 2, 3, 4, 5, 7])
    );

    vm.startPrank(maker);
    uint pendingBase__ = mgo.pending()[0];
    uint pendingQuote__ = mgo.pending()[1];
    vm.stopPrank();

    assertEq(pendingBase__, 0, "Pending base pool should be empty");
    assertEq(pendingQuote__, 0, "Pending quote pool should be empty");

    uint best_id = mgv.best($(weth), $(usdc));
    P.Offer.t offer8 = mgv.offers($(weth), $(usdc), best_id);
    assertEq(best_id, 8, "Best offer on WETH,USDC offer list should be #8");

    assertEq(offer8.gives(), gave + pendingBase_, "Incorrect offer gives");

    P.Offer.t offer2 = mgv.offers($(usdc), $(weth), 2);

    assertEq(
      offer2.gives(),
      pendingQuote_ + old_offer2.gives() - cash(usdc, 100),
      "Incorrect offer gives"
    );
  }

  function part_kill() public {
    vm.prank(maker);
    mgo.pause();

    vm.prank(taker);
    (uint got, uint gave, , ) = mgv.marketOrder(
      $(usdc),
      $(weth),
      cash(usdc, 2500),
      cash(weth, 15, 1),
      true
    );

    assertEq(got, 0, "got should be 0");
    assertEq(gave, 0, "gave should be 0");

    Book memory book = get_offers(false);
    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(-2), -3, -4, -5, -6, 0, 0, -8, -7, -1])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), 8, 0, 6, 1, 2, 3, 4, 5, 7])
    );
  }

  function part_restart_fixed_shift() public {
    vm.startPrank(maker);
    mgo.restart();
    init(cash(usdc, 500), cash(weth, 15, 2));
    vm.stopPrank();

    Book memory book = get_offers(false);
    checkOB(
      $(usdc),
      $(weth),
      book.bids,
      dynamic([int(2), 3, 4, 5, 6, 0, 0, -8, -7, -1])
    );
    checkOB(
      $(weth),
      $(usdc),
      book.asks,
      dynamic([int(0), -8, 0, -6, -1, 2, 3, 4, 5, 7])
    );
  }

  /* ********* Utility methods ************ */

  // get internal view of mango's offers
  function get_offers(bool liveOnly) internal view returns (Book memory) {
    uint[][2] memory res = mgo.get_offers(liveOnly);
    return Book({bids: res[0], asks: res[1]});
  }

  // given offerIds and offerStatuses, for id in offerStatuses,
  // * check that offers[abs(id)] is live iff id > 0
  // * check that abs(id)==offerIds[i]
  function checkOB(
    address $out,
    address $in,
    uint[] memory offerIds,
    int[] memory offerStatuses
  ) internal {
    int sid;

    for (uint i = 0; i < offerStatuses.length; i++) {
      sid = offerStatuses[i];
      assertEq(
        mgv.offers($out, $in, abs(sid)).gives() > 0,
        sid > 0,
        string.concat("wrong offer status ", int2str(sid))
      );
      assertEq(offerIds[i], abs(sid), "Offer misplaced");
    }
  }

  // init procedure
  // TODO explain
  function init(uint bidAmount, uint askAmount) internal {
    uint slice = NSLOTS / 2; // require(NSLOTS%2==0)?
    uint[] memory pivotIds = new uint[](NSLOTS);
    uint[] memory amounts = new uint[](NSLOTS);
    for (uint i = 0; i < NSLOTS; i++) {
      amounts[i] = i < NSLOTS / 2 ? bidAmount : askAmount;
    }

    for (uint i = 0; i < 2; i++) {
      mgo.initialize({
        reset: true,
        lastBidPosition: 4,
        from: slice * i,
        to: slice * (i + 1),
        pivotIds: [pivotIds, pivotIds],
        tokenAmounts: amounts
      });
    }
  }
}
