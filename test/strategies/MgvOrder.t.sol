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
  uint constant GASREQ = 30_000;

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
  IOrderLogic.TakerOrder internal cold_buyOrder;
  IOrderLogic.TakerOrder internal cold_sellOrder;
  IOrderLogic.TakerOrderResult internal cold_sellResult;

  receive() external payable {}

  function setUp() public override {
    fork = new PinnedPolygonFork();
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

    // depositing a cold MangroveOrder offer.
    cold_buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 1991 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    cold_sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false,
      takerWants: 1999 ether,
      takerGives: 1 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    cold_buyResult = mgo.take{value: 0.1 ether}(cold_buyOrder);
    cold_sellResult = mgo.take{value: 0.1 ether}(cold_sellOrder);

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
    quote.approve(address(mgo.router()), balQuote);
    base.approve(address(mgo.router()), balBase);
    vm.stopPrank();
  }

  function test_partial_filled_buy_order_is_transfered_to_taker() public {
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
    address fresh_taker = freshTaker(0, 4000 ether);
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee($(base), $(quote), 1 ether), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, 1999 ether, "Incorrect partial fill of taker order");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "Funds were not transfered to taker");
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

  function test_partial_filled_with_no_resting_order_returns_value_and_remaining_inbound() public {
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

  function test_partial_filled_with_no_resting_order_returns_bounty() public {
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

  function test_filled_resting_buy_order_ignores_resting_option() public {
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
    vm.prank(fresh_taker);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.offerId, 0, "There should be no resting order");
    assertEq(quote.balanceOf(fresh_taker), 0, "incorrect quote balance");
    assertEq(base.balanceOf(fresh_taker), res.takerGot, "incorrect base balance");
  }

  // function test_filled_resting_buy_order_returns_provision() public {
  //   uint balWeiBefore = $(this).balance;

  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 1 ether,
  //     takerGives: 0.17 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });
  //   mgo.take(buyOrder);
  //   assertEq($(this).balance, balWeiBefore, "incorrect wei balance");
  // }

  // function logOrderData(
  //   IMangrove iMgv,
  //   address taker,
  //   IOrderLogic.TakerOrder memory tko,
  //   IOrderLogic.TakerOrderResult memory res_
  // ) internal {
  //   emit OrderSummary(
  //     iMgv,
  //     tko.outbound_tkn,
  //     tko.inbound_tkn,
  //     taker,
  //     tko.fillOrKill,
  //     tko.takerWants,
  //     tko.takerGives,
  //     tko.fillWants,
  //     tko.restingOrder,
  //     tko.expiryDate,
  //     res_.takerGot,
  //     res_.takerGave,
  //     res_.bounty,
  //     res_.fee,
  //     res_.offerId
  //   );
  // }

  // function test_resting_buy_order_is_successfully_posted() public {
  //   uint bal_quote_before = mgo.router().balanceOfReserve(quote, $(this));
  //   uint bal_base_before = mgo.router().balanceOfReserve(quote, $(this));
  //   assertEq(mgv.balanceOf($(mgo)), 0, "Invalid balance on Mangrove");

  //   IOrderLogic.TakerOrderResult memory expectedRes = IOrderLogic.TakerOrderResult({
  //     takerGot: 997000000000000000,
  //     takerGave: 130000000000000000,
  //     bounty: 0,
  //     fee: 3000000000000000,
  //     offerId: 4
  //   });

  //   expectFrom($(mgo));
  //   logOrderData(IMangrove(payable(mgv)), $(this), buyOrder, expectedRes);

  //   // checking resting order parameters
  //   MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), cold_resultofferId);
  //   assertEq(
  //     offer.wants(),
  //     buyOrder.takerWants - (cold_result.takerGot + cold_resultfee),
  //     "Incorrect wants for bid resting order"
  //   );
  //   assertEq(
  //     offer.gives(),
  //     (offer.wants() * buyOrder.takerGives) / buyOrder.takerWants,
  //     "Incorrect gives for bid resting order"
  //   );

  //   // checking `router` balances
  //   assertEq(
  //     mgo.router().balanceOfReserve(quote, $(this)), bal_quote_before - cold_resulttakerGave, "Invalid quote balance"
  //   );
  //   assertEq(
  //     mgo.router().balanceOfReserve(base, $(this)), bal_base_before + cold_resulttakerGot, "Invalid base balance"
  //   );
  // }

  // function test_resting_buy_order_is_successfully_posted_after_empty_fill() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.102 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });

  //   IOrderLogic.TakerOrderResult memory expectedRes =
  //     IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 4});

  //   expectFrom($(mgo));
  //   logOrderData(IMangrove(payable(mgv)), $(this), buyOrder, expectedRes);
  //   // TODO when checkEmit is available, get offer id after post
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "Resting offer failed to be published on mangrove");

  //   // checking resting order parameters
  //   MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), cold_result.offerId);
  //   assertEq(offer.wants(), buyOrder.takerWants, "Incorrect wants for bid resting order");
  //   assertEq(offer.gives(), buyOrder.takerGives, "Incorrect gives for bid resting order");
  // }

  // function test_resting_sell_order_is_successfully_posted() public {
  //   IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: quote,
  //     inbound_tkn: base,
  //     fillOrKill: false,
  //     fillWants: false, // sell order
  //     takerWants: 0.2352 ether, // wants 0.24 quotes for 2 bases
  //     takerGives: 2 ether, // sells 2 base
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });
  //   uint bal_quote_before = mgo.router().balanceOfReserve(quote, $(this));
  //   uint bal_base_before = mgo.router().balanceOfReserve(quote, $(this));
  //   assertEq(mgv.balanceOf($(mgo)), 0, "Invalid balance on Mangrove");

  //   IOrderLogic.TakerOrderResult memory expectedRes = IOrderLogic.TakerOrderResult({
  //     takerGot: 119640000000000000,
  //     takerGave: 1000000000000000000,
  //     bounty: 0,
  //     fee: 360000000000000,
  //     offerId: 4
  //   });

  //   expectFrom($(mgo));
  //   logOrderData(IMangrove(payable(mgv)), $(this), sellOrder, expectedRes);
  //   // TODO when checkEmit is available, get offer id after post
  //   IOrderLogic.TakerOrderResult memory res_ = mgo.take{value: 0.1 ether}(sellOrder);
  //   assertTrue(res_.offerId > 0, "Resting offer failed to be published on mangrove");

  //   // checking resting order parameters
  //   MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), res_.offerId);
  //   assertEq(offer.gives(), sellOrder.takerGives - res_.takerGave, "Incorrect gives for ask resting order");
  //   assertEq(
  //     offer.wants(),
  //     (offer.gives() * sellOrder.takerWants) / sellOrder.takerGives,
  //     "Incorrect wants for ask resting order"
  //   );

  //   // checking `mgo` mappings
  //   assertEq(mgo.ownerOf(base, quote, res_.offerId), $(this), "Invalid offer owner");
  //   assertEq(mgo.router().balanceOfReserve(quote, $(this)), bal_quote_before + res_.takerGot, "Invalid quote balance");
  //   assertEq(mgo.router().balanceOfReserve(base, $(this)), bal_base_before - res_.takerGave, "Invalid base balance");
  // }

  // function test_resting_sell_order_is_successfully_posted_after_empty_fill() public {
  //   IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: quote,
  //     inbound_tkn: base,
  //     fillOrKill: false,
  //     fillWants: false, // sell order
  //     takerWants: 1 ether,
  //     takerGives: 2 ether, // sells 2 base
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });

  //   IOrderLogic.TakerOrderResult memory expectedRes =
  //     IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 4});

  //   expectFrom($(mgo));
  //   logOrderData(IMangrove(payable(mgv)), $(this), sellOrder, expectedRes);
  //   // TODO when checkEmit is available, get offer id after post
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);
  //   assertTrue(cold_result.offerId > 0, "Resting offer failed to be published on mangrove");

  //   // checking resting order parameters
  //   MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), cold_result.offerId);
  //   assertEq(offer.gives(), sellOrder.takerGives, "Incorrect gives for ask resting order");
  //   assertEq(offer.wants(), sellOrder.takerWants, "Incorrect wants for ask resting order");
  // }

  // function resting_buy_order_for_blacklisted_reserve_reverts() private {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });

  //   vm.expectRevert("mgvOrder/pushFailed");
  //   mgo.take{value: 0.1 ether}(buyOrder);
  // }

  // function test_resting_buy_order_for_blacklisted_reserve_for_inbound_reverts() public {
  //   // We cannot blacklist in quote as take will fail too early, use mocking instead
  //   // quote.blacklists($(this));
  //   vm.mockCall(
  //     address(quote), abi.encodeWithSelector(base.transferFrom.selector, $(mgo), $(this), 0.13 ether), abi.encode(false)
  //   );
  //   resting_buy_order_for_blacklisted_reserve_reverts();
  // }

  // function test_resting_buy_order_can_be_partially_filled() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   uint oldLocalBaseBal = base.balanceOf($(this));
  //   uint oldRemoteQuoteBal = mgo.router().balanceOfReserve(quote, $(this)); // quote balance of test runner

  //   (bool success, uint sell_takerGot, uint sell_takerGave,, uint fee) =
  //     sell_taker.takeWithInfo({offerId: cold_result.offerId, takerWants: 0.1 ether});

  //   assertTrue(success, "Resting order failed");
  //   // offer delivers
  //   assertEq(sell_takerGot, reader.minusFee($(quote), $(base), 0.1 ether), "Incorrect received amount for seller taker");
  //   // inbound token forwarded to test runner
  //   assertEq(base.balanceOf($(this)), oldLocalBaseBal + sell_takerGave, "Incorrect forwarded amount to initial taker");

  //   assertEq(
  //     mgo.router().balanceOfReserve(quote, $(this)),
  //     oldRemoteQuoteBal - (sell_takerGot + fee),
  //     "Incorrect token balance on mgo"
  //   );

  //   // checking resting order residual
  //   MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), cold_result.offerId);

  //   assertEq(
  //     offer.gives(), buyOrder.takerGives - cold_result.takerGave - 0.1 ether, "Incorrect gives for bid resting order"
  //   );
  // }

  // function test_user_can_retract_resting_offer() public {
  //   uint userWeiBalanceOld = $(this).balance;
  //   uint credited = mgo.retractOffer(quote, base, cold_result.offerId, true);
  //   assertEq($(this).balance, userWeiBalanceOld + credited, "Incorrect provision received");
  // }

  // function test_failing_resting_offer_releases_uncollected_provision() public {
  //   uint provision = 5 ether;
  //   mgv.fund{value: provision}(address(mgo));

  //   // native token reserve for user
  //   uint native_reserve_before = $(this).balance;

  //   // removing base/quote approval to make resting offer fail when matched
  //   TransferLib.approveToken(quote, $(mgo.router()), 0);
  //   TransferLib.approveToken(base, $(mgo.router()), 0);

  //   (,,, uint bounty,) = sell_taker.takeWithInfo({offerId: cold_result.offerId, takerWants: 1});
  //   assertTrue(bounty > 0, "snipe should have failed");
  //   // collecting released provision
  //   mgo.retractOffer(quote, base, cold_result.offerId, true);
  //   uint native_reserve_after = $(this).balance;
  //   uint userReleasedProvision = native_reserve_after - native_reserve_before;
  //   assertTrue(userReleasedProvision > 0, "No released provision");
  //   // making sure approx is not too bad (UserReleasedProvision in O(provision - cold_resultbounty))
  //   assertEq((provision - cold_result.bounty) / userReleasedProvision, 1, "invalid amount of released provision");
  // }

  // function test_restingOrder_that_fail_to_post_release_provisions() public {
  //   vm.deal(address(this), 2 ether);
  //   uint native_balance_before = $(this).balance;
  //   mgv.setDensity($(quote), $(base), 0.1 ether);
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 1.000001 ether, // residual will be below density
  //     takerGives: 0.13000013 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 2 ether}(buyOrder);
  //   assertEq(cold_result.takerGot + cold_result.fee, 1 ether, "Market order failed");
  //   assertEq(cold_result.offerId, 0, "Resting order should not be posted");
  //   assertEq($(this).balance, native_balance_before, "Provision not released");
  // }

  // function test_restingOrder_that_fail_to_post_revert_if_no_partialFill() public {
  //   mgv.setDensity($(quote), $(base), 0.1 ether);
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: true,
  //     fillWants: true,
  //     takerWants: 1.000001 ether, // residual will be below density
  //     takerGives: 0.13000013 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0 //NA
  //   });
  //   vm.expectRevert("mgvOrder/partialFill");
  //   mgo.take{value: 2 ether}(buyOrder);
  // }

  // function test_restingOrder_is_correctly_owned() public {
  //   // post an order that will result in a resting order on the book

  //   uint[] memory offerIds = new uint[](1);
  //   offerIds[0] = cold_result.offerId;

  //   address[] memory offerOwners = mgo.offerOwners(quote, base, offerIds);
  //   assertEq(offerOwners.length, 1);
  //   assertEq(offerOwners[0], $(this), "Invalid offer owner");
  // }

  // function test_offer_succeeds_when_time_is_not_expired() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: block.timestamp + 60 //NA
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "resting order not posted");

  //   MgvLib.SingleOrder memory order;
  //   order.outbound_tkn = address(quote);
  //   order.inbound_tkn = address(base);
  //   order.offerId = cold_result.offerId;

  //   vm.prank($(mgv));
  //   bytes32 ret = mgo.makerExecute(order);
  //   assertEq(ret, "", "logic should accept trade");
  // }

  // function test_offer_reneges_when_time_is_expired() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: block.timestamp + 60
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "resting order not posted");

  //   MgvLib.SingleOrder memory order;
  //   order.outbound_tkn = address(quote);
  //   order.inbound_tkn = address(base);
  //   order.offerId = cold_result.offerId;

  //   vm.warp(block.timestamp + 62);
  //   vm.expectRevert("mgvOrder/expired");
  //   vm.prank($(mgv));
  //   mgo.makerExecute(order);
  // }

  // function test_offer_owner_can_set_expiry() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: block.timestamp + 60
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "resting order not posted");
  //   mgo.setExpiry(quote, base, cold_result.offerId, block.timestamp + 70);
  //   assertEq(mgo.expiring(quote, base, cold_result.offerId), block.timestamp + 70, "Incorrect timestamp");
  // }

  // function test_offer_only_owner_can_set_expiry() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: block.timestamp + 60
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "resting order not posted");
  //   vm.expectRevert("AccessControlled/Invalid");
  //   vm.prank(freshAddress());
  //   mgo.setExpiry(quote, base, cold_result.offerId, block.timestamp + 70);
  // }

  // function test_order_fails_when_time_is_expired() public {
  //   IOrderLogic.TakerOrder memory buyOrder;
  //   buyOrder.expiryDate = 1;
  //   vm.warp(2);
  //   vm.expectRevert("mgvOrder/expired");
  //   mgo.take{value: 0.1 ether}(buyOrder);
  // }

  // function test_underprovisioned_order_logs_properly() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0
  //   });
  //   deal($(quote), $(this), 0.25 ether);
  //   vm.expectRevert("mgvOrder/transferInFail");
  //   mgo.take{value: 0.1 ether}(buyOrder);
  // }

  // function test_caller_unable_to_receive_eth_makes_failing_resting_order_throw() public {
  //   TestSender buy_taker = new TestSender();
  //   vm.deal($(buy_taker), 1 ether);

  //   deal($(quote), $(buy_taker), 10 ether);
  //   buy_taker.refuseNative();

  //   vm.startPrank($(buy_taker));
  //   TransferLib.approveToken(quote, $(mgo.router()), type(uint).max);
  //   vm.stopPrank();

  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 1 ether,
  //     takerGives: 0.13 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: 0
  //   });
  //   /// since `buy_taker` throws on `receive()`, this should fail.
  //   vm.expectRevert("mgvOrder/refundFail");
  //   vm.prank($(buy_taker));
  //   // complete fill will not lead to a resting order
  //   mgo.take{value: 0.1 ether}(buyOrder);
  // }

  // function test_mockup_routing_gas_cost() public {
  //   SimpleRouter router = SimpleRouter(address(mgo.router()));
  //   // making quote balance hot to mock taker's transfer
  //   quote.transfer($(mgo), 1);

  //   vm.prank($(mgo));
  //   uint g = gasleft();
  //   uint pushed = router.push(quote, address(this), 1);
  //   uint push_cost = g - gasleft();
  //   assertEq(pushed, 1, "Push failed");

  //   vm.prank($(mgo));
  //   g = gasleft();
  //   uint pulled = router.pull(base, address(this), 1, true);
  //   uint pull_cost = g - gasleft();
  //   assertEq(pulled, 1, "Pull failed");

  //   console.log("Gas cost: %d (pull: %d g.u, push: %d g.u)", pull_cost + push_cost, pull_cost, push_cost);
  // }

  // function test_mockup_offerLogic_gas_cost() public {
  //   IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
  //     outbound_tkn: base,
  //     inbound_tkn: quote,
  //     fillOrKill: false,
  //     fillWants: true,
  //     takerWants: 2 ether,
  //     takerGives: 0.26 ether,
  //     restingOrder: true,
  //     pivotId: 0,
  //     expiryDate: block.timestamp + 60
  //   });
  //   IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
  //   assertTrue(cold_result.offerId > 0, "resting order not posted");

  //   (MgvLib.SingleOrder memory sellOrder, MgvLib.OrderResult memory result) =
  //     mockSellOrder( /*gives base*/ 0.01 ether, 0.0013 ether, 10, base, quote, "");
  //   // mock up mgv taker transfer to maker contract
  //   base.transfer($(mgo), 0.01 ether);
  //   sellOrder.offerId = cold_result.offerId;
  //   vm.prank($(mgv));
  //   _gas();
  //   mgo.makerExecute(sellOrder);
  //   uint exec_gas = gas_(true);
  //   vm.prank($(mgv));
  //   _gas();
  //   mgo.makerPosthook(sellOrder, result);
  //   uint posthook_gas = gas_(true);
  //   console.log(
  //     "MgvOrder's logic is %d (makerExecute: %d, makerPosthook:%d)", exec_gas + posthook_gas, exec_gas, posthook_gas
  //   );
  // }
}
