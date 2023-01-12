// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, TestMaker, TestTaker, TestSender, console} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MangroveOrderEnriched as MgvOrder} from "mgv_src/strategies/MangroveOrderEnriched.sol";
import {IOrderLogic} from "mgv_src/strategies/interfaces/IOrderLogic.sol";
import {MgvStructs, MgvLib, IERC20} from "mgv_src/MgvLib.sol";

contract MangroveOrder_Test is MangroveTest {
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

  MgvOrder mgo;
  TestMaker ask_maker;
  TestMaker bid_maker;

  TestTaker sell_taker;

  receive() external payable {}

  function setUp() public override {
    super.setUp();
    mgv.setFee($(base), $(quote), 30);
    mgv.setFee($(quote), $(base), 30);
    // to prevent test runner (taker) from receiving fees!
    mgv.setVault($(mgv));

    // this contract is admin of MgvOrder and its router
    mgo = new MgvOrder(IMangrove(payable(mgv)), $(this));
    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = base;
    tokens[1] = quote;
    mgo.activate(tokens);

    // `this` contract will act as `MgvOrder` user
    deal($(base), $(this), 10 ether);
    deal($(quote), $(this), 10 ether);

    // user approves `mgo` to pull quote or base when doing a market order
    quote.approve($(mgo.router()), 10 ether);
    base.approve($(mgo.router()), 10 ether);

    // `sell_taker` will take resting bid
    sell_taker = setupTaker($(quote), $(base), "sell-taker");
    deal($(base), $(sell_taker), 10 ether);

    // if seller wants to sell directly on mangrove
    vm.prank($(sell_taker));
    base.approve($(mgv), 10 ether);
    // if seller wants to sell via mgo
    vm.prank($(sell_taker));
    quote.approve($(mgv), 10 ether);

    // populating order book with offers
    ask_maker = setupMaker($(base), $(quote), "ask-maker");
    vm.deal($(ask_maker), 10 ether);

    bid_maker = setupMaker($(quote), $(base), "bid-maker");
    vm.deal($(bid_maker), 10 ether);

    deal($(base), $(ask_maker), 10 ether);
    deal($(quote), $(bid_maker), 10 ether);

    ask_maker.approveMgv(base, 10 ether);
    ask_maker.newOfferWithFunding( /*wants quote*/ 0.13 ether, /*gives base*/ 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(0.14 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(0.15 ether, 1 ether, 50_000, 0, 0, 0.1 ether);

    bid_maker.approveMgv(quote, 10 ether);
    bid_maker.newOfferWithFunding(1 ether, 0.12 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding(1 ether, 0.11 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding( /*wants base*/ 1 ether, /*gives quote*/ 0.1 ether, 50_000, 0, 0, 0.1 ether);
  }

  function test_admin() public {
    assertEq(mgv.governance(), mgo.admin(), "Invalid admin address");
  }

  function test_only_owner_can_update_offer() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether, // with 2% slippage
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.updateOffer(quote, base, 10, 10, 0, res.offerId);
  }

  function test_owner_can_update_offer() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether, // with 2% slippage
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");
    mgo.updateOffer(quote, base, 1 ether, 1 ether, 0, res.offerId);
    assertEq(mgv.offers($(quote), $(base), res.offerId).gives(), 1 ether, "Offer incorrectly updated");
  }

  function test_partial_filled_buy_order_returns_residual() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    expectFrom($(quote)); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer($(this), $(mgo), 0.26 ether);
    expectFrom($(quote)); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer($(mgo), $(this), 0.13 ether);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee($(base), $(quote), 1 ether), "Incorrect partial fill of taker order");
    assertEq(res.takerGave, 0.13 ether, "Incorrect partial fill of taker order");
  }

  function test_partial_filled_buy_order_reverts_when_noPartialFill_enabled() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: true,
      // The highest price taker wants to pay is takerGives/takerWants. We want takerWants to not be completely filled, so it is larger than 3 ether
      // this then requires takerGives to be larger than 0.42 ether for all orders to be picked.
      // Therefore takerGives is also not completely filled so fillWants: false will also not be completely filled here.
      fillWants: true,
      takerWants: 3000000000000000001,
      takerGives: 420000000000000001,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    vm.expectRevert("mgvOrder/partialFill");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_partial_filled_with_no_resting_order_returns_provision() public {
    uint balBefore = $(this).balance;
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(res.takerGot, reader.minusFee($(base), $(quote), 1 ether), "Incorrect taker got");
    assertEq(balBefore, $(this).balance, "Take function did not return funds");
  }

  function test_partial_filled_with_no_resting_order_returns_bounty() public {
    uint balBefore = $(this).balance;
    ask_maker.shouldRevert(true);

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerGives: 0.26 ether,
      takerWants: 2 ether,
      restingOrder: false,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.bounty > 0, "Bounty should not be zero");
    assertEq(balBefore + res.bounty, $(this).balance, "Take function did not return bounty");
  }

  function test_filled_resting_buy_order_ignores_resting_option() public {
    uint balQuoteBefore = quote.balanceOf($(this));
    uint balBaseBefore = base.balanceOf($(this));

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertEq(quote.balanceOf($(this)), balQuoteBefore - res.takerGave, "incorrect quote balance");
    assertEq(base.balanceOf($(this)), balBaseBefore + res.takerGot, "incorrect base balance");
  }

  function test_filled_resting_buy_order_returns_provision() public {
    uint balWeiBefore = $(this).balance;

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 0.13 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take(buyOrder);
    res; // ssh
    assertEq($(this).balance, balWeiBefore, "incorrect wei balance");
  }

  function logOrderData(
    IMangrove iMgv,
    address taker,
    IOrderLogic.TakerOrder memory tko,
    IOrderLogic.TakerOrderResult memory res
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
      res.takerGot,
      res.takerGave,
      res.bounty,
      res.fee,
      res.offerId
      );
  }

  function test_resting_buy_order_is_successfully_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    uint bal_quote_before = mgo.router().reserveBalance(quote, $(this));
    uint bal_base_before = mgo.router().reserveBalance(quote, $(this));
    assertEq(mgv.balanceOf($(mgo)), 0, "Invalid balance on Mangrove");

    IOrderLogic.TakerOrderResult memory expectedRes = IOrderLogic.TakerOrderResult({
      takerGot: 997000000000000000,
      takerGave: 130000000000000000,
      bounty: 0,
      fee: 3000000000000000,
      offerId: 4
    });

    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), $(this), buyOrder, expectedRes);
    // TODO when checkEmit is available, get offer id after post
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");

    // checking resting order parameters
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);
    assertEq(offer.wants(), buyOrder.takerWants - (res.takerGot + res.fee), "Incorrect wants for bid resting order");
    assertEq(
      offer.gives(),
      (offer.wants() * buyOrder.takerGives) / buyOrder.takerWants,
      "Incorrect gives for bid resting order"
    );

    // checking `mgo` mappings
    assertEq(mgo.ownerOf(quote, base, res.offerId), $(this), "Invalid offer owner");
    assertEq(mgo.router().reserveBalance(quote, $(this)), bal_quote_before - res.takerGave, "Invalid quote balance");
    assertEq(mgo.router().reserveBalance(base, $(this)), bal_base_before + res.takerGot, "Invalid base balance");
  }

  function test_resting_buy_order_is_successfully_posted_after_empty_fill() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.102 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedRes =
      IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 4});

    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), $(this), buyOrder, expectedRes);
    // TODO when checkEmit is available, get offer id after post
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");

    // checking resting order parameters
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);
    assertEq(offer.wants(), buyOrder.takerWants, "Incorrect wants for bid resting order");
    assertEq(offer.gives(), buyOrder.takerGives, "Incorrect gives for bid resting order");
  }

  function test_resting_sell_order_is_successfully_posted() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false, // sell order
      takerWants: 0.2352 ether, // wants 0.24 quotes for 2 bases
      takerGives: 2 ether, // sells 2 base
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    uint bal_quote_before = mgo.router().reserveBalance(quote, $(this));
    uint bal_base_before = mgo.router().reserveBalance(quote, $(this));
    assertEq(mgv.balanceOf($(mgo)), 0, "Invalid balance on Mangrove");

    IOrderLogic.TakerOrderResult memory expectedRes = IOrderLogic.TakerOrderResult({
      takerGot: 119640000000000000,
      takerGave: 1000000000000000000,
      bounty: 0,
      fee: 360000000000000,
      offerId: 4
    });

    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), $(this), sellOrder, expectedRes);
    // TODO when checkEmit is available, get offer id after post
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");

    // checking resting order parameters
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), res.offerId);
    assertEq(offer.gives(), sellOrder.takerGives - res.takerGave, "Incorrect gives for ask resting order");
    assertEq(
      offer.wants(),
      (offer.gives() * sellOrder.takerWants) / sellOrder.takerGives,
      "Incorrect wants for ask resting order"
    );

    // checking `mgo` mappings
    assertEq(mgo.ownerOf(base, quote, res.offerId), $(this), "Invalid offer owner");
    assertEq(mgo.router().reserveBalance(quote, $(this)), bal_quote_before + res.takerGot, "Invalid quote balance");
    assertEq(mgo.router().reserveBalance(base, $(this)), bal_base_before - res.takerGave, "Invalid base balance");
  }

  function test_resting_sell_order_is_successfully_posted_after_empty_fill() public {
    IOrderLogic.TakerOrder memory sellOrder = IOrderLogic.TakerOrder({
      outbound_tkn: quote,
      inbound_tkn: base,
      fillOrKill: false,
      fillWants: false, // sell order
      takerWants: 1 ether,
      takerGives: 2 ether, // sells 2 base
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory expectedRes =
      IOrderLogic.TakerOrderResult({takerGot: 0, takerGave: 0, bounty: 0, fee: 0, offerId: 4});

    expectFrom($(mgo));
    logOrderData(IMangrove(payable(mgv)), $(this), sellOrder, expectedRes);
    // TODO when checkEmit is available, get offer id after post
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(sellOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");

    // checking resting order parameters
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), res.offerId);
    assertEq(offer.gives(), sellOrder.takerGives, "Incorrect gives for ask resting order");
    assertEq(offer.wants(), sellOrder.takerWants, "Incorrect wants for ask resting order");
  }

  function resting_buy_order_for_blacklisted_reserve_reverts() private {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    vm.expectRevert("mgvOrder/pushFailed");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_resting_buy_order_for_blacklisted_reserve_for_outbound_reverts() public {
    base.blacklists($(this));
    resting_buy_order_for_blacklisted_reserve_reverts();
  }

  function test_resting_buy_order_for_blacklisted_reserve_for_inbound_reverts() public {
    // We cannot blacklist in quote as take will fail too early, use mocking instead
    // quote.blacklists($(this));
    vm.mockCall(
      address(quote), abi.encodeWithSelector(base.transferFrom.selector, $(mgo), $(this), 0.13 ether), abi.encode(false)
    );
    resting_buy_order_for_blacklisted_reserve_reverts();
  }

  function test_resting_buy_order_can_be_partially_filled() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    uint oldLocalBaseBal = base.balanceOf($(this));
    uint oldRemoteQuoteBal = mgo.router().reserveBalance(quote, $(this)); // quote balance of test runner

    (bool success, uint sell_takerGot, uint sell_takerGave,, uint fee) =
      sell_taker.takeWithInfo({offerId: res.offerId, takerWants: 0.1 ether});

    assertTrue(success, "Resting order failed");
    // offer delivers
    assertEq(sell_takerGot, reader.minusFee($(quote), $(base), 0.1 ether), "Incorrect received amount for seller taker");
    // inbound token forwarded to test runner
    assertEq(base.balanceOf($(this)), oldLocalBaseBal + sell_takerGave, "Incorrect forwarded amount to initial taker");

    assertEq(
      mgo.router().reserveBalance(quote, $(this)),
      oldRemoteQuoteBal - (sell_takerGot + fee),
      "Incorrect token balance on mgo"
    );

    // checking resting order residual
    MgvStructs.OfferPacked offer = mgv.offers($(quote), $(base), res.offerId);

    assertEq(offer.gives(), buyOrder.takerGives - res.takerGave - 0.1 ether, "Incorrect gives for bid resting order");
  }

  function test_user_can_retract_resting_offer() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    uint userWeiBalanceOld = $(this).balance;
    uint credited = mgo.retractOffer(quote, base, res.offerId, true);
    assertEq($(this).balance, userWeiBalanceOld + credited, "Incorrect provision received");
  }

  function test_failing_resting_offer_releases_uncollected_provision() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    uint provision = 5 ether;
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: provision}(buyOrder);
    // native token reserve for user
    uint native_reserve_before = $(this).balance;

    // removing base/quote approval to make resting offer fail when matched
    quote.approve($(mgo.router()), 0);
    base.approve($(mgo.router()), 0);

    (,,, uint bounty,) = sell_taker.takeWithInfo({offerId: res.offerId, takerWants: 1});
    assertTrue(bounty > 0, "snipe should have failed");
    // collecting released provision
    mgo.retractOffer(quote, base, res.offerId, true);
    uint native_reserve_after = $(this).balance;
    uint userReleasedProvision = native_reserve_after - native_reserve_before;
    assertTrue(userReleasedProvision > 0, "No released provision");
    // making sure approx is not too bad (UserReleasedProvision in O(provision - res.bounty))
    assertEq((provision - res.bounty) / userReleasedProvision, 1, "invalid amount of released provision");
  }

  function test_restingOrder_that_fail_to_post_release_provisions() public {
    vm.deal(address(this), 2 ether);
    uint native_balance_before = $(this).balance;
    mgv.setDensity($(quote), $(base), 0.1 ether);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1.000001 ether, // residual will be below density
      takerGives: 0.13000013 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 2 ether}(buyOrder);
    assertEq(res.takerGot + res.fee, 1 ether, "Market order failed");
    assertEq(res.offerId, 0, "Resting order should not be posted");
    assertEq($(this).balance, native_balance_before, "Provision not released");
  }

  function test_restingOrder_that_fail_to_post_revert_if_no_partialFill() public {
    mgv.setDensity($(quote), $(base), 0.1 ether);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: true,
      fillWants: true,
      takerWants: 1.000001 ether, // residual will be below density
      takerGives: 0.13000013 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });
    vm.expectRevert("mgvOrder/partialFill");
    mgo.take{value: 2 ether}(buyOrder);
  }

  function test_restingOrder_is_correctly_owned() public {
    // post an order that will result in a resting order on the book
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0 //NA
    });

    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "Resting offer failed to be published on mangrove");

    uint[] memory offerIds = new uint[](1);
    offerIds[0] = res.offerId;

    address[] memory offerOwners = mgo.offerOwners(quote, base, offerIds);
    assertEq(offerOwners.length, 1);
    assertEq(offerOwners[0], $(this), "Invalid offer owner");
  }

  function test_offer_succeeds_when_time_is_not_expired() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 60 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "resting order not posted");

    MgvLib.SingleOrder memory order;
    order.outbound_tkn = address(quote);
    order.inbound_tkn = address(base);
    order.offerId = res.offerId;

    vm.prank($(mgv));
    bytes32 ret = mgo.makerExecute(order);
    assertEq(ret, "mgvOffer/proceed", "logic should accept trade");
  }

  function test_offer_reneges_when_time_is_expired() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 60
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "resting order not posted");

    MgvLib.SingleOrder memory order;
    order.outbound_tkn = address(quote);
    order.inbound_tkn = address(base);
    order.offerId = res.offerId;

    vm.warp(block.timestamp + 62);
    vm.expectRevert("mgvOrder/expired");
    vm.prank($(mgv));
    mgo.makerExecute(order);
  }

  function test_offer_owner_can_set_expiry() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 60
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "resting order not posted");
    mgo.setExpiry(quote, base, res.offerId, block.timestamp + 70);
    assertEq(mgo.expiring(quote, base, res.offerId), block.timestamp + 70, "Incorrect timestamp");
  }

  function test_offer_only_owner_can_set_expiry() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: block.timestamp + 60
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(buyOrder);
    assertTrue(res.offerId > 0, "resting order not posted");
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(freshAddress());
    mgo.setExpiry(quote, base, res.offerId, block.timestamp + 70);
  }

  function test_order_fails_when_time_is_expired() public {
    IOrderLogic.TakerOrder memory buyOrder;
    buyOrder.expiryDate = 1;
    vm.warp(2);
    vm.expectRevert("mgvOrder/expired");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_underprovisioned_order_logs_properly() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 2 ether,
      takerGives: 0.26 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0
    });
    deal($(quote), $(this), 0.25 ether);
    vm.expectRevert("mgvOrder/transferInFail");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_caller_unable_to_receive_eth_makes_failing_resting_order_throw() public {
    TestSender buy_taker = new TestSender();
    vm.deal($(buy_taker), 1 ether);

    deal($(quote), $(buy_taker), 10 ether);
    buy_taker.refuseNative();

    vm.startPrank($(buy_taker));
    quote.approve($(mgo.router()), type(uint).max);
    vm.stopPrank();

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      outbound_tkn: base,
      inbound_tkn: quote,
      fillOrKill: false,
      fillWants: true,
      takerWants: 1 ether,
      takerGives: 0.13 ether,
      restingOrder: true,
      pivotId: 0,
      expiryDate: 0
    });
    /// since `buy_taker` throws on `receive()`, this should fail.
    vm.expectRevert("mgvOrder/refundFail");
    vm.prank($(buy_taker));
    // complete fill will not lead to a resting order
    mgo.take{value: 0.1 ether}(buyOrder);
  }
}
