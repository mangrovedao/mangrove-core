// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestMaker, TestTaker, TestSender, console} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MangroveOrder as MgvOrder, SimpleRouter} from "mgv_src/strategies/MangroveOrder.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IOrderLogic} from "mgv_src/strategies/interfaces/IOrderLogic.sol";
import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

contract MangroveOrder_Test is MangroveTest {
  uint constant GASREQ = 35_000;

  // to check ERC20 logging
  event Transfer(address indexed from, address indexed to, uint value);

  event OrderSummary(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    address indexed taker,
    bool fillOrKill,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    bool restingOrder,
    uint expiryDate,
    uint takerGot,
    uint takerGave,
    uint bounty,
    uint fee,
    uint restingOrderId
  );

  MgvOrder internal mgo;
  TestMaker internal ask_maker;
  TestMaker internal bid_maker;

  TestTaker internal sell_taker;
  PinnedPolygonFork internal fork;

  IOrderLogic.TakerOrderResult internal cold_buyResult;
  IOrderLogic.TakerOrderResult internal cold_sellResult;

  receive() external payable {}

  function setUp() public override {
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("DAI"));
    setupMarket(base, quote);

    // this contract is admin of MgvOrder and its router
    mgo = new MgvOrder(IMangrove(payable(mgv)), $(this), GASREQ);
    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    mgo.activate(tokens);

    // `this` contract will act as `MgvOrder` user
    deal($(base), $(this), 10 ether);
    deal($(quote), $(this), 10_000 ether);

    // user approves `mgo` to pull quote or base when doing a market order
    TransferLib.approveToken(quote, $(mgo.router()), 10_000 ether);
    TransferLib.approveToken(base, $(mgo.router()), 10 ether);

    // `sell_taker` will take resting bid
    sell_taker = setupTaker($(quote), $(base), "sell-taker");
    deal($(base), $(sell_taker), 10 ether);

    // if seller wants to sell directly on mangrove
    vm.prank($(sell_taker));
    TransferLib.approveToken(base, $(mgv), 10 ether);
    // if seller wants to sell via mgo
    vm.prank($(sell_taker));
    TransferLib.approveToken(quote, $(mgv), 10 ether);

    // populating order book with offers
    ask_maker = setupMaker($(base), $(quote), "ask-maker");
    vm.deal($(ask_maker), 10 ether);

    bid_maker = setupMaker($(quote), $(base), "bid-maker");
    vm.deal($(bid_maker), 10 ether);

    deal($(base), $(ask_maker), 10 ether);
    deal($(quote), $(bid_maker), 10000 ether);

    // pre populating book with cold maker offers.
    ask_maker.approveMgv(base, 10 ether);
    ask_maker.newOfferWithFunding( /*wants quote*/ 2000 ether, /*gives base*/ 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(2001 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(2002 ether, 1 ether, 50_000, 0, 0, 0.1 ether);

    bid_maker.approveMgv(quote, 10000 ether);
    bid_maker.newOfferWithFunding(1 ether, 1990 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding(1 ether, 1989 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding( /*wants base*/ 1 ether, /*gives quote*/ 1988 ether, 50_000, 0, 0, 0.1 ether);

    IOrderLogic.TakerOrder memory buyOrder;
    IOrderLogic.TakerOrder memory sellOrder;
    // depositing a cold MangroveOrder offer.
    buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1991 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 1
    });

    sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1999 ether,
      takerGives: 1 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 1
    });

    cold_buyResult = mgo.take{value: 0.1 ether}(buyOrder);
    cold_sellResult = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(cold_buyResult.offerId * cold_sellResult.offerId > 0, "Resting offer failed to be published on mangrove");
    // mgo ask
    // 4 ┆ 1999 DAI  /  1 WETH 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker asks
    // 1 ┆ 2000 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 2 ┆ 2001 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // 3 ┆ 2002 DAI  /  1 WETH 0x1d1499e622D69689cdf9004d05Ec547d650Ff211
    // ------------------------------------------------------------------
    // mgo bid
    // 4 ┆ 1 WETH  /  1991 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // maker bids
    // 1 ┆ 1 WETH  /  1990 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 2 ┆ 1 WETH  /  1989 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
    // 3 ┆ 1 WETH  /  1988 DAI 0xA4AD4f68d0b91CFD19687c881e50f3A00242828c
  }

  function test_admin() public {
    assertEq(mgv.governance(), mgo.admin(), "Invalid admin address");
  }

  function freshTaker(uint balBase, uint balQuote) internal returns (address fresh_taker) {
    fresh_taker = freshAddress("MgvOrderTester");
    deal($(quote), fresh_taker, balQuote);
    deal($(base), fresh_taker, balBase);
    deal(fresh_taker, 1 ether);
    vm.startPrank(fresh_taker);
    quote.approve(address(mgo.router()), type(uint).max);
    base.approve(address(mgo.router()), type(uint).max);
    vm.stopPrank();
  }

  ////////////////////////
  /// Tests taker side ///
  ////////////////////////

  function test_partial_filled_buy_order_is_transferred_to_taker() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 1999 ether * 2,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 4000 ether);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee($(base), $(quote), 1 ether), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, 1999 ether, "Incorrect partial fill of taker order");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "Funds were not transferred to taker");
  }

  function test_partial_filled_buy_order_reverts_when_FoK_enabled() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: true,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 1999 ether * 2,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 4000 ether);
    vm.prank(fresh_taker);
    vm.expectRevert("mgvOrder/partialFill");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_order_reverts_when_expiry_date_is_in_the_past() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: true,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 1999 ether * 2,
      restingOrder: false,
      pivotId: 0,
      expiryDate: block.timestamp - 1
    });
    address fresh_taker = freshTaker(0, 4000 ether);
    vm.prank(fresh_taker);
    vm.expectRevert("mgvOrder/expired");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_partial_filled_returns_value_and_remaining_inbound() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 1999 ether * 2,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 4000 ether);
    uint balBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(balBefore, fresh_taker.balance, "Take function did not return value to taker");
    assertEq(4000 ether - 1999 ether, quote.balanceOf(fresh_taker), "Take did not return remainder to taker");
  }

  function test_partial_filled_order_returns_bounty() public {
    ask_maker.shouldRevert(true);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 3 ether,
      takerGives: 12000 ether,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 12000 ether);
    uint balBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.bounty > 0, "Bounty should not be zero");
    assertEq(balBefore + res.bounty, fresh_taker.balance, "Take function did not return bounty");
  }

  function test_filled_resting_buy_order_ignores_resting_option_and_returns_value() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1999 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 1999 ether);
    uint nativeBalBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.offerId, 0, "There should be no resting order");
    assertEq(quote.balanceOf(fresh_taker), 0, "incorrect quote balance");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "incorrect base balance");
    assertEq(fresh_taker.balance, nativeBalBefore, "value was not returned to taker");
  }

  function test_filled_resting_buy_order_with_FoK_succeeds_and_returns_provision() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: true,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1999 ether,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(0, 1999 ether);
    uint nativeBalBefore = fresh_taker.balance;
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.offerId, 0, "There should be no resting order");
    assertEq(quote.balanceOf(fresh_taker), 0, "incorrect quote balance");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "incorrect base balance");
    assertEq(fresh_taker.balance, nativeBalBefore, "value was not returned to taker");
  }

  ///////////////////////
  /// Test maker side ///
  ///////////////////////

  function logOrderData(
    IMangrove iMgv,
    address taker,
    IOrderLogic.TakerOrder memory tko,
    IOrderLogic.TakerOrderResult memory res_
  ) internal {
    emit OrderSummary(
      iMgv,
      tko.outbound_tkn,
      tko.inbound_tkn,
      taker,
      tko.fillOrKill,
      tko.takerWants,
      tko.takerGives,
      tko.fillWants,
      tko.restingOrder,
      tko.expiryDate,
      res_.takerGot,
      res_.takerGave,
      res_.bounty,
      res_.fee,
      res_.offerId
    );
  }

  function test_partial_fill_buy_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 1999 ether * 2,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedResult = IOrderLogic.TakerOrderResult({
      takerGot: reader.minusFee($(quote), $(base), 1 ether),
      takerGave: 1999 ether,
      bounty: 0,
      fee: 1 ether - reader.minusFee($(quote), $(base), 1 ether),
      offerId: 5
    });

    address fresh_taker = freshTaker(0, 1999 ether * 2);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), fresh_taker, buyOrder, expectedResult);

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(quote, base, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(quote, base, res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(quote.balanceOf(fresh_taker), 1999 ether, "Incorrect remaining quote balance");
    assertEq(
      base.balanceOf(fresh_taker), reader.minusFee($(base), $(quote), 1 ether), "Incorrect obtained base balance"
    );
    // checking price of offer
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(quote), $(base), res.offerId);
    assertEq(offer.gives(), 1999 ether, "Incorrect offer gives");
    assertEq(offer.wants(), 1 ether, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_empty_fill_buy_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1998 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedResult =
      IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 5});

    address fresh_taker = freshTaker(0, 1998 ether);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), fresh_taker, buyOrder, expectedResult);

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(quote, base, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(quote, base, res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(quote.balanceOf(fresh_taker), 1998 ether, "Incorrect remaining quote balance");
    assertEq(base.balanceOf(fresh_taker), 0, "Incorrect obtained base balance");
    // checking price of offer
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(quote), $(base), res.offerId);
    assertEq(offer.gives(), 1998 ether, "Incorrect offer gives");
    assertEq(offer.wants(), 1 ether, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_partial_fill_sell_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1991 * 2 ether,
      takerGives: 2 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedResult = IOrderLogic.TakerOrderResult({
      takerGot: reader.minusFee($(quote), $(base), 1991 ether),
      takerGave: 1 ether,
      bounty: 0,
      fee: 1991 ether - reader.minusFee($(quote), $(base), 1991 ether),
      offerId: 5
    });

    address fresh_taker = freshTaker(2 ether, 0);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), fresh_taker, sellOrder, expectedResult);

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(base, quote, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(base, quote, res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(base.balanceOf(fresh_taker), 1 ether, "Incorrect remaining base balance");
    assertEq(
      quote.balanceOf(fresh_taker), reader.minusFee($(base), $(quote), 1991 ether), "Incorrect obtained quote balance"
    );
    // checking price of offer
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), res.offerId);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(base), $(quote), res.offerId);
    assertEq(offer.gives(), 1 ether, "Incorrect offer gives");
    assertEq(offer.wants(), 1991 ether, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_empty_fill_sell_with_resting_order_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1992 ether,
      takerGives: 1 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedResult =
      IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 5});

    address fresh_taker = freshTaker(1 ether, 0);
    uint nativeBalBefore = fresh_taker.balance;

    // checking log emission
    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), fresh_taker, sellOrder, expectedResult);

    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);

    assertTrue(res.offerId > 0, "Offer not posted");
    assertEq(fresh_taker.balance, nativeBalBefore - 0.1 ether, "Value not deposited");
    assertEq(mgo.provisionOf(base, quote, res.offerId), 0.1 ether, "Offer not provisioned");
    // checking mappings
    assertEq(mgo.ownerOf(base, quote, res.offerId), fresh_taker, "Invalid offer owner");
    assertEq(base.balanceOf(fresh_taker), 1 ether, "Incorrect remaining base balance");
    assertEq(quote.balanceOf(fresh_taker), 0, "Incorrect obtained quote balance");
    // checking price of offer
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), res.offerId);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(base), $(quote), res.offerId);
    assertEq(offer.gives(), 1 ether, "Incorrect offer gives");
    assertEq(offer.wants(), 1992 ether, "Incorrect offer wants");
    assertEq(offer.prev(), 0, "Offer should be best of the book");
    assertEq(detail.maker(), address(mgo), "Incorrect maker");
  }

  function test_resting_order_with_expiry_date_is_correctly_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1991 * 2 ether,
      takerGives: 2 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 1 //NA
    });
    address fresh_taker = freshTaker(2 ether, 0);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);
    assertEq(mgo.expiring(base, quote, res.offerId), block.timestamp + 1, "Incorrect expiry");
  }

  function test_resting_buy_order_for_blacklisted_reserve_for_inbound_reverts() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1991 ether,
      takerGives: 1 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    address fresh_taker = freshTaker(1 ether, 0);
    vm.mockCall(
      $(quote),
      abi.encodeWithSelector(
        quote.transferFrom.selector, $(mgo), fresh_taker, reader.minusFee($(quote), $(base), 1991 ether)
      ),
      abi.encode(false)
    );
    vm.expectRevert("mgvOrder/pushFailed");
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  function test_resting_buy_order_failing_to_post_returns_tokens_and_provision() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1991 * 2 ether,
      takerGives: 2 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    //address(args.outbound_tkn), address(args.inbound_tkn), args.wants, args.gives, args.gasreq, gasprice, args.pivotId
    address fresh_taker = freshTaker(2 ether, 0);
    uint oldNativeBal = fresh_taker.balance;
    // pretend new offer failed for some reason
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOffer.selector), abi.encode(uint(0)));
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
    assertEq(fresh_taker.balance, oldNativeBal, "Taker's provision was not returned");
  }

  function test_restingOrder_that_fail_to_post_revert_if_no_partialFill() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: true,
      fillWants: false,
      takerWants: 1991 * 2 ether,
      takerGives: 2 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    //address(args.outbound_tkn), address(args.inbound_tkn), args.wants, args.gives, args.gasreq, gasprice, args.pivotId
    address fresh_taker = freshTaker(2 ether, 0);
    // pretend new offer failed for some reason
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOffer.selector), abi.encode(uint(0)));
    vm.expectRevert("mgvOrder/partialFill");
    vm.prank(fresh_taker);
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  function test_taker_unable_to_receive_eth_makes_tx_throw_if_resting_order_could_not_be_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1991 * 2 ether,
      takerGives: 2 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    TestSender sender = new TestSender();
    vm.deal($(sender), 1 ether);

    deal($(base), $(sender), 2 ether);
    sender.refuseNative();

    vm.startPrank($(sender));
    TransferLib.approveToken(base, $(mgo.router()), type(uint).max);
    vm.stopPrank();
    // mocking MangroveOrder failure to post resting offer
    vm.mockCall($(mgv), abi.encodeWithSelector(mgv.newOffer.selector), abi.encode(uint(0)));
    /// since `sender` throws on `receive()`, this should fail.
    vm.expectRevert("mgvOrder/refundFail");
    vm.prank($(sender));
    // complete fill will not lead to a resting order
    mgo.take{value: 0.1 ether}(sellOrder);
  }

  //////////////////////////////////////
  /// Test resting order consumption ///
  //////////////////////////////////////

  function test_resting_buy_offer_can_be_partially_filled() public {
    // sniping resting sell offer: 4 ┆ 1999 DAI  /  1 WETH 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    uint oldBaseBal = base.balanceOf($(this));
    uint oldQuoteBal = quote.balanceOf($(this)); // quote balance of test runner

    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), cold_buyResult.offerId);

    (, uint takerGot, uint takerGave,, uint fee) =
      sell_taker.takeWithInfo({takerWants: 1000 ether, offerId: cold_buyResult.offerId});

    // offer delivers
    assertEq(takerGot, 1000 ether - fee, "Incorrect received amount for seller taker");
    // inbound token forwarded to test runner
    assertEq(base.balanceOf($(this)), oldBaseBal + takerGave, "Incorrect base balance");
    // outbound taken from test runner
    assertEq(quote.balanceOf($(this)), oldQuoteBal - (takerGot + fee), "Incorrect quote balance");
    // checking residual
    MgvStructs.OfferPacked offer_ = mgv.offers($(quote), $(base), cold_buyResult.offerId);
    assertEq(offer_.gives(), offer.gives() - (takerGot + fee), "Incorrect residual");
  }

  function test_resting_buy_offer_can_be_fully_consumed_at_minimum_approval() public {
    TransferLib.approveToken(quote, $(mgo.router()), 2000 ether);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1000 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 1
    });
    IOrderLogic.TakerOrderResult memory buyResult = mgo.take{value: 0.1 ether}(buyOrder);

    assertTrue(buyResult.offerId > 0, "Resting order should succeed");

    (bool success,,,,) = sell_taker.takeWithInfo({takerWants: 40000 ether, offerId: buyResult.offerId});

    assertTrue(success, "Offer should succeed");
  }

  function test_failing_resting_offer_releases_uncollected_provision() public {
    uint provision = mgo.provisionOf(quote, base, cold_buyResult.offerId);
    // empty quotes so that cold buy offer fails
    deal($(quote), address(this), 0);
    _gas();
    (,,, uint bounty,) = sell_taker.takeWithInfo({offerId: cold_buyResult.offerId, takerWants: 1991});
    uint g = gas_(true);

    assertTrue(bounty > 0, "snipe should have failed");
    assertTrue(
      provision > mgo.provisionOf(quote, base, cold_buyResult.offerId),
      "Remaining provision should be less than original"
    );
    assertTrue(mgo.provisionOf(quote, base, cold_buyResult.offerId) > 0, "Remaining provision should not be 0");
    assertTrue(bounty > g * reader.global().gasprice(), "taker not compensated");
    console.log("Taker gained %s matics", toFixed(bounty - g * reader.global().gasprice(), 18));
  }

  function test_offer_succeeds_when_time_is_not_expired() public {
    mgo.setExpiry(quote, base, cold_buyResult.offerId, block.timestamp + 1);
    (bool success,,,,) = sell_taker.takeWithInfo({offerId: cold_buyResult.offerId, takerWants: 1991});
    assertTrue(success, "offer failed");
  }

  function test_offer_reneges_when_time_is_expired() public {
    mgo.setExpiry(quote, base, cold_buyResult.offerId, block.timestamp);
    vm.warp(block.timestamp + 1);
    (bool success,,,,) = sell_taker.takeWithInfo({offerId: cold_buyResult.offerId, takerWants: 1991});
    assertTrue(!success, "offer should have failed");
  }
  //////////////////////////////
  /// Tests offer management ///
  //////////////////////////////

  function test_user_can_retract_resting_offer() public {
    uint userWeiBalanceOld = $(this).balance;
    uint credited = mgo.retractOffer(quote, base, cold_buyResult.offerId, true);
    assertEq($(this).balance, userWeiBalanceOld + credited, "Incorrect provision received");
  }

  event SetExpiry(address indexed outbound_tkn, address indexed inbound_tkn, uint offerId, uint date);

  function test_offer_owner_can_set_expiry() public {
    expectFrom($(mgo));
    emit SetExpiry($(quote), $(base), cold_buyResult.offerId, 42);
    mgo.setExpiry(quote, base, cold_buyResult.offerId, 42);
    assertEq(mgo.expiring(quote, base, cold_buyResult.offerId), 42, "expiry date was not set");
  }

  function test_only_offer_owner_can_set_expiry() public {
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.setExpiry(quote, base, cold_buyResult.offerId, 42);
  }

  function test_offer_owner_can_update_offer() public {
    //IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId
    mgo.updateOffer(quote, base, 1 ether, 2000 ether, cold_buyResult.offerId, cold_buyResult.offerId);
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), cold_buyResult.offerId);
    assertEq(offer.wants(), 1 ether, "Incorrect updated wants");
    assertEq(offer.gives(), 2000 ether, "Incorrect updated gives");
    assertEq(mgo.ownerOf(quote, base, cold_buyResult.offerId), $(this), "Owner should not have changed");
  }

  function test_only_offer_owner_can_update_offer() public {
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.updateOffer(quote, base, 1 ether, 2000 ether, cold_buyResult.offerId, cold_buyResult.offerId);
  }

  //////////////////////////////
  /// Gas requirements tests ///
  //////////////////////////////

  function test_mockup_routing_gas_cost() public {
    SimpleRouter router = SimpleRouter(address(mgo.router()));
    // making quote balance hot to mock taker's transfer
    quote.transfer($(mgo), 1);

    vm.prank($(mgo));
    uint g = gasleft();
    uint pushed = router.push(quote, address(this), 1);
    uint push_cost = g - gasleft();
    assertEq(pushed, 1, "Push failed");

    vm.prank($(mgo));
    g = gasleft();
    uint pulled = router.pull(base, address(this), 1, true);
    uint pull_cost = g - gasleft();
    assertEq(pulled, 1, "Pull failed");

    console.log("Gas cost: %d (pull: %d g.u, push: %d g.u)", pull_cost + push_cost, pull_cost, push_cost);
  }

  function test_mockup_offerLogic_gas_cost() public {
    (MgvLib.SingleOrder memory sellOrder, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: 0.5 ether,
      takerWants: 1991 ether / 2,
      partialFill: 2,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    // pranking a fresh taker to avoid heating test runner balance
    vm.prank($(mgv));
    base.transferFrom(address(sell_taker), $(mgv), 0.5 ether);
    vm.prank($(mgv));
    base.transfer($(mgo), 0.5 ether);

    sellOrder.offerId = cold_buyResult.offerId;
    vm.prank($(mgv));
    _gas();
    mgo.makerExecute(sellOrder);
    uint exec_gas = gas_(true);
    // since offer reposts itself, making offer info, mgo credit on mangrove and mgv config hot in storage
    mgv.config($(quote), $(base));
    mgv.offers($(quote), $(base), sellOrder.offerId);
    mgv.offerDetails($(quote), $(base), sellOrder.offerId);
    mgv.fund{value: 1}($(mgo));

    vm.prank($(mgv));
    _gas();
    mgo.makerPosthook(sellOrder, result);
    uint posthook_gas = gas_(true);
    console.log(
      "MgvOrder's logic is %d (makerExecute: %d, makerPosthook:%d)", exec_gas + posthook_gas, exec_gas, posthook_gas
    );
  }

  function test_empirical_offer_gas_cost() public {
    uint[4][] memory targets = new uint[4][](1);
    // resting order buys 1 ether for 1991 dai
    // fresh taker sells 0.5 ether for 900 dai for any gasreq
    targets[0] = [cold_buyResult.offerId, 900 ether, 0.5 ether, type(uint).max];
    vm.prank(address(sell_taker));
    _gas();
    // cannot use TestTaker functions that have additional gas cost
    // simply using sell_taker's approvals and already filled balances
    (uint successes,,,,) = mgv.snipes($(quote), $(base), targets, true);
    gas_();
    assertTrue(successes == 1, "Snipe failed");
    assertTrue(mgv.offers($(quote), $(base), cold_buyResult.offerId).gives() > 0, "Update failed");
  }
}
