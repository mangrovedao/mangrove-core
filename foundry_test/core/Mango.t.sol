// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/OfferLogics/SingleUser/Deployable/MarketMaking/Mango/Mango.sol";
import "mgv_src/strategies/OfferLogics/SingleUser/Deployable/MarketMaking/Routers/nonCustodial/EOARouter.sol";

contract MangoTest is MangroveTest {
  struct Book {
    uint[] bids;
    uint[] asks;
  }

  uint constant BASE0 = 0.34 ether;
  uint constant BASE1 = 1000 * 10**6; //because usdc decimals?
  uint constant NSLOTS = 10;
  uint constant DELTA = 34 * 10**6; // because usdc decimals?

  uint constant WETH_DECS = 10**18;
  uint constant USDC_DECS = 10**6;

  TestToken weth;
  TestToken usdc;
  address payable $weth;
  address payable $usdc;
  address payable maker;
  address payable taker;
  Mango mgo;
  address payable $mgo;
  EOARouter eoa_router;

  function setUp() public override {
    options.base.symbol = "WETH";
    options.quote.symbol = "USDC";
    options.quote.decimals = 6;

    super.setUp();
    // rename for convenience
    weth = base;
    $weth = $base;
    usdc = quote;
    $usdc = $quote;

    mgv.setFee($weth, $usdc, 30);

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($weth, taker, 50 * WETH_DECS);
    deal($usdc, taker, 100000 * USDC_DECS);

    vm.startPrank(maker);
    mgo = new Mango({
      mgv: IMangrove($mgv), // TODO: remove IMangrove dependency?
      base: IEIP20($weth),
      quote: IEIP20($usdc),
      base_0: (34 * WETH_DECS) / 100,
      quote_0: 1000 * USDC_DECS,
      nslots: NSLOTS,
      price_incr: DELTA,
      deployer: maker
    });
    $mgo = payable(address(mgo));
    eoa_router = new EOARouter({deployer: maker});
    eoa_router.bind($mgo);
    mgo.set_liquidity_router(eoa_router, mgo.OFR_GASREQ());
    vm.stopPrank();
  }

  function test_all() public {
    part_deploy_strat();
    part_market_order();
  }

  function part_deploy_strat() public {
    vm.startPrank(maker);
    weth.approve(address(mgo.liquidity_router()), type(uint).max);
    usdc.approve(address(mgo.liquidity_router()), type(uint).max);

    deal($weth, maker, 17 * WETH_DECS);
    deal($usdc, maker, 50000 * USDC_DECS);

    uint prov = mgo.getMissingProvision({
      outbound_tkn: IEIP20($weth),
      inbound_tkn: IEIP20($usdc),
      gasreq: mgo.OFR_GASREQ(),
      gasprice: 0,
      offerId: 0
    });
    vm.stopPrank();

    mgv.fund{value: prov * 20}($mgo);

    vm.startPrank(maker); // prank all calls in init
    init(1000 * USDC_DECS, (3 * WETH_DECS) / 10);
    vm.stopPrank();

    Book memory book = get_offers(false);

    checkOB(
      $usdc,
      $weth,
      book.bids,
      asDyn([int(1), 2, 3, 4, 5, 0, 0, 0, 0, 0])
    );
    checkOB(
      $weth,
      $usdc,
      book.asks,
      asDyn([int(0), 0, 0, 0, 0, 1, 2, 3, 4, 5])
    );
  }

  function part_market_order() public {
    vm.prank(taker);
    weth.approve($mgv, type(uint).max);
    vm.prank(taker);
    usdc.approve($mgv, type(uint).max);

    printOfferBook($weth, $usdc);
    vm.prank(taker);
    (uint got, uint gave, uint bounty, uint _fee) = mgv.marketOrder(
      $weth,
      $usdc,
      (5 * WETH_DECS) / 10,
      3000 * USDC_DECS,
      true
    );

    Book memory book = get_offers(false);
    printOfferBook($usdc, $weth);
    // logary(book.bids);
    assertEq(
      got,
      0.5 ether - ((0.5 ether * 30) / 10000),
      "incorrect received amount"
    );
    assertEq(bounty, 0, "taker should not receive bounty");
    checkOB(
      $usdc,
      $weth,
      book.bids,
      asDyn([int(1), 2, 3, 4, 5, 6, 0, 0, 0, 0])
    );
    checkOB(
      $weth,
      $usdc,
      book.asks,
      asDyn([int(0), 0, 0, 0, 0, -1, 2, 3, 4, 5])
    );
  }

  /* check ... */
  function get_offers(bool liveOnly) internal returns (Book memory) {
    uint[][2] memory res = mgo.get_offers(liveOnly);
    uint[] memory bids = res[0];
    uint[] memory asks = res[1];
    return Book({bids: res[0], asks: res[1]});
  }

  function checkOB(
    address $out,
    address $in,
    uint[] memory offerIds,
    int[] memory offerStatuses
  ) internal {
    uint id;

    // logary(offerIds);
    // logary(offerStatuses);

    for (uint i = 0; i < offerStatuses.length; i++) {
      id = abs(offerStatuses[i]);
      console.log("offer", mgv.offers($out, $in, id).gives());
      if (offerStatuses[i] <= 0) {
        assertEq(
          mgv.offers($out, $in, id).gives(),
          0,
          "Offer should not be on the book"
        );
      } else {
        assertGt(
          mgv.offers($out, $in, id).gives(),
          0,
          "Offer should be on the book"
        );
      }

      assertEq(offerIds[i], id, "Offer misplaced");
    }
  }

  /* init procedure */
  function init(uint bidAmount, uint askAmount) internal {
    uint slice = NSLOTS / 2; // require(NSLOTS%2==0)?
    uint[] memory pivotIds = new uint[](NSLOTS);
    uint[] memory amounts = new uint[](NSLOTS);
    for (uint i = 0; i < NSLOTS; i++) {
      if (i < NSLOTS / 2) {
        amounts[i] = bidAmount;
      } else {
        amounts[i] = askAmount;
      }
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
