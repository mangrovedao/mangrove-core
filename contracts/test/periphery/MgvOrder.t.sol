// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import "mgv_test/lib/MangroveTest.sol";

pragma solidity ^0.8.10;
pragma abicoder v2;

// import "../../AbstractMangrove.sol";
import {MgvLib as ML, P, IMaker} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

// import "hardhat/console.sol";

// import "../Toolbox/sol";

// import "../Agents/TestToken.sol";
// import "../Agents/TestMaker.sol";

import {MangroveOrderEnriched as MgvOrder} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import "mgv_src/strategies/interfaces/IOrderLogic.sol";

contract MangroveOrder_Test is MangroveTest {
  // to check ERC20 logging
  event Transfer(address indexed from, address indexed to, uint value);

  // to check incident logging
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 reason
  );

  event OrderSummary(
    IMangrove mangrove,
    IERC20 indexed base,
    IERC20 indexed quote,
    address indexed taker,
    bool selling,
    uint takerGot,
    uint takerGave,
    uint penalty,
    uint restingOrderId
  );

  MgvOrder mgo;
  TestMaker bid_maker;
  TestMaker ask_maker;
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
    // base.mint($(this), 10 ether);
    // quote.mint($(this), 10 ether);

    // user approves `mgo` to pull quote or base when doing a market order
    quote.approve($(mgo.router()), 10 ether);
    base.approve($(mgo.router()), 10 ether);

    // `sell_taker` will take resting offer
    sell_taker = setupTaker($(quote), $(base), "sell-taker");
    deal($(base), $(sell_taker), 10 ether);
    // tka.mint($(sell_taker), 10 ether);

    // if seller wants to sell direclty on mangrove
    vm.prank($(sell_taker));
    base.approve($(mgv), 10 ether);
    // sell_taker.approve(tka, $(mgv), 10 ether);
    // if seller wants to sell via mgo
    // sell_taker.approve(tka, $(mgo), 10 ether);
    vm.prank($(sell_taker));
    quote.approve($(mgv), 10 ether);

    // populating order book with offers
    bid_maker = setupMaker($(quote), $(base), "bid-maker");
    vm.deal($(bid_maker), 10 ether);
    ask_maker = setupMaker($(base), $(quote), "ask-maker");
    vm.deal($(ask_maker), 10 ether);

    vm.prank($(bid_maker));
    quote.approve($(mgv), 10 ether);
    // bid_maker.approveMgv(tkb, 10 ether);
    deal($(quote), $(bid_maker), 10 ether);
    // tkb.mint($(bid_maker), 10 ether);

    deal($(base), $(ask_maker), 10 ether);
    // tka.mint($(ask_maker), 10 ether);
    vm.prank($(ask_maker));
    base.approve($(mgv), 10 ether);
    // ask_maker.approveMgv(tka, 10 ether);

    bid_maker.newOfferWithFunding(1 ether, 0.1 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding(1 ether, 0.11 ether, 50_000, 0, 0, 0.1 ether);
    bid_maker.newOfferWithFunding(1 ether, 0.12 ether, 50_000, 0, 0, 0.1 ether);

    ask_maker.newOfferWithFunding(0.13 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(0.14 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    ask_maker.newOfferWithFunding(0.15 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
  }

  function test_admin() public {
    assertEq(mgv.governance(), mgo.admin(), "Invalid admin address");
  }

  function test_partial_filled_buy_order_returns_residual() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      makerWants: 2 ether,
      gives: 0.26 ether,
      makerGives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    expectFrom($(quote)); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer($(this), $(mgo), 0.26 ether);
    expectFrom($(quote)); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer($(mgo), $(this), 0.13 ether);
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertEq(
      res.takerGot,
      minusFee($(base), $(quote), 1 ether),
      "Incorrect partial fill of taker order"
    );
    assertEq(
      res.takerGave,
      0.13 ether,
      "Incorrect partial fill of taker order"
    );
  }

  function test_partial_filled_buy_order_reverts_when_noPartialFill_enabled()
    public
  {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: true,
      selling: false, //i.e buying
      wants: 2 ether,
      makerWants: 2 ether,
      gives: 0.26 ether,
      makerGives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    vm.expectRevert("mgvOrder/mo/noPartialFill");
    mgo.take{value: 0.1 ether}(buyOrder);
  }

  function test_partial_filled_buy_order_returns_provision() public {
    uint balBefore = $(this).balance;
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      makerWants: 2 ether,
      gives: 0.26 ether,
      makerGives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertEq(
      res.takerGot,
      minusFee($(base), $(quote), 1 ether),
      "Incorrect taker got"
    );
    assertEq(balBefore, $(this).balance, "Take function did not return funds");
  }

  function test_partial_filled_buy_order_returns_bounty() public {
    uint balBefore = $(this).balance;
    ask_maker.shouldRevert(true);

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertTrue(res.bounty > 0, "Bounty should not be zero");
    assertEq(
      balBefore + res.bounty,
      $(this).balance,
      "Take function did not return bounty"
    );
  }

  function test_resting_buy_order_reverts_when_unprovisioned() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    vm.expectRevert("MultiUser/derive_gasprice/NotEnoughProvision");
    mgo.take{value: 0.0001 ether}(buyOrder);
  }

  function test_filled_resting_buy_order_ignores_resting_option() public {
    uint balQuoteBefore = quote.balanceOf($(this));
    uint balBaseBefore = base.balanceOf($(this));

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 1 ether,
      gives: 0.13 ether,
      makerWants: 1 ether,
      makerGives: 0.13 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertEq(
      quote.balanceOf($(this)),
      balQuoteBefore - res.takerGave,
      "incorrect quote balance"
    );
    assertEq(
      base.balanceOf($(this)),
      balBaseBefore + res.takerGot,
      "incorrect base balance"
    );
  }

  function test_filled_resting_buy_order_returns_provision() public {
    uint balWeiBefore = $(this).balance;

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 1 ether,
      gives: 0.13 ether,
      makerWants: 1 ether,
      makerGives: 0.13 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take(buyOrder);
    res; // ssh
    assertEq($(this).balance, balWeiBefore, "incorrect wei balance");
  }

  function test_resting_buy_order_is_successfully_posted() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether, // with 2% slippage
      makerWants: 2 ether,
      makerGives: 0.2548 ether, //without 2% slippage
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    uint bal_quote_before = mgo.router().reserveBalance(quote, $(this));
    uint bal_base_before = mgo.router().reserveBalance(quote, $(this));
    assertEq(mgv.balanceOf($(mgo)), 0, "Invalid balance on Mangrove");

    expectFrom($(mgo));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      $(this),
      false, //buying
      minusFee($(base), $(quote), 1 ether),
      0.13 ether,
      0,
      4 // TODO when checkEmit is available, get offer id after post
    );
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertTrue(
      res.offerId > 0,
      "Resting offer failed to be published on mangrove"
    );

    // checking resting order parameters
    P.Offer.t offer = mgv.offers($(quote), $(base), res.offerId);
    assertEq(
      offer.wants(),
      buyOrder.makerWants - (res.takerGot + res.fee),
      "Incorrect wants for bid resting order"
    );
    assertEq(
      offer.gives(),
      buyOrder.makerGives - res.takerGave,
      "Incorrect gives for bid resting order"
    );

    // checking `mgo` mappings
    assertEq(
      mgo.ownerOf(quote, base, res.offerId),
      $(this),
      "Invalid offer owner"
    );
    assertEq(
      mgo.router().reserveBalance(quote, $(this)),
      bal_quote_before - res.takerGave,
      "Invalid quote balance"
    );
    assertEq(
      mgo.router().reserveBalance(base, $(this)),
      bal_base_before + res.takerGot,
      "Invalid quote balance"
    );
  }

  function test_resting_buy_order_can_be_partially_filled() public {
    //mgv.setFee($(quote), $(base), 0);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    uint oldLocalBaseBal = base.balanceOf($(this));
    uint oldRemoteQuoteBal = mgo.router().reserveBalance(quote, $(this)); // quote balance of test runner

    (
      bool success,
      uint sell_takerGot,
      uint sell_takerGave,
      ,
      uint fee
    ) = sell_taker.takeWithInfo({offerId: res.offerId, takerWants: 0.1 ether});

    assertTrue(success, "Resting order failed");
    // offer delivers
    assertEq(
      sell_takerGot,
      minusFee($(quote), $(base), 0.1 ether),
      "Incorrect received amount for seller taker"
    );
    // inbound token forwarded to test runner
    assertEq(
      base.balanceOf($(this)),
      oldLocalBaseBal + sell_takerGave,
      "Incorrect forwarded amount to initial taker"
    );

    assertEq(
      mgo.router().reserveBalance(quote, $(this)),
      oldRemoteQuoteBal - (sell_takerGot + fee),
      "Incorrect token balance on mgo"
    );

    // checking resting order residual
    P.Offer.t offer = mgv.offers($(quote), $(base), res.offerId);

    assertEq(
      offer.gives(),
      buyOrder.gives - res.takerGave - 0.1 ether,
      "Incorrect gives for bid resting order"
    );
  }

  function test_resting_offer_retracts_when_unable_to_repost() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    // test runner quote balance on the gateway
    uint oldWeiBalance = $(this).balance;

    // increasing density on mangrove so that resting offer can no longer repost
    mgv.setDensity($(quote), $(base), 1 ether);
    expectFrom($(mgv));
    emit OfferRetract($(quote), $(base), res.offerId);
    (bool success, , , , ) = sell_taker.takeWithInfo({
      offerId: res.offerId,
      takerWants: 0
    });
    assertTrue(success, "snipe failed");
    assertEq($(this).balance, oldWeiBalance, "retract should not deprovision");
  }

  function test_user_can_retract_resting_offer() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    uint userWeiBalanceOld = $(this).balance;
    uint credited = mgo.retractOffer(quote, base, res.offerId, true);
    assertEq(
      $(this).balance,
      userWeiBalanceOld + credited,
      "Incorrect provision received"
    );
  }

  function test_failing_resting_offer_releases_uncollected_provision() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });

    uint provision = 5 ether;
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: provision}(
      buyOrder
    );
    // native token reserve for user
    uint native_reserve_before = $(this).balance;

    // removing base/quote approval to make resting offer fail when matched
    quote.approve($(mgo.router()), 0);
    base.approve($(mgo.router()), 0);

    (, , , uint bounty, ) = sell_taker.takeWithInfo({
      offerId: res.offerId,
      takerWants: 1
    });
    assertTrue(bounty > 0, "snipe should have failed");
    // collecting released provision
    mgo.retractOffer(quote, base, res.offerId, true);
    uint native_reserve_after = $(this).balance;
    uint userReleasedProvision = native_reserve_after - native_reserve_before;
    assertTrue(userReleasedProvision > 0, "No released provision");
    // making sure approx is not too bad (UserreleasedProvision in O(provision - res.bounty))
    assertEq(
      (provision - res.bounty) / userReleasedProvision,
      1,
      "invalid amount of released provision"
    );
  }

  function test_iterative_market_order_completes() public {
    ask_maker.shouldRepost(true);
    expectFrom($(mgv));
    emit OrderComplete(
      $(base),
      $(quote),
      $(mgo),
      minusFee($(base), $(quote), 1 ether),
      0.13 ether,
      0,
      getFee($(base), $(quote), 1 ether)
    );
    expectFrom($(mgv));
    emit OrderComplete(
      $(base),
      $(quote),
      $(mgo),
      minusFee($(base), $(quote), 1 ether),
      0.13 ether,
      0,
      getFee($(base), $(quote), 1 ether)
    );
    expectFrom($(mgo));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      $(this),
      false,
      minusFee($(base), $(quote), 2 ether),
      0.26 ether,
      0,
      0
    );
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      makerWants: 2 ether,
      makerGives: 0.26 ether,
      restingOrder: true,
      retryNumber: 1,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgo.take{value: 0.1 ether}(
      buyOrder
    );
    assertEq(
      res.takerGot,
      minusFee($(base), $(quote), 2 ether),
      "Iterative market order was not complete"
    );
  }

  function test_ownership_relation() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false,
      wants: 2 ether,
      gives: 0.1 ether,
      makerWants: 2 ether,
      makerGives: 0.1 ether,
      restingOrder: true,
      retryNumber: 1,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    expectFrom($(mgo));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      $(this),
      false,
      0,
      0,
      0,
      4 // TODO when checkEmit is available, get offer id after post
    );
    mgo.take{value: 0.1 ether}(buyOrder);
    expectFrom($(mgo));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      $(this),
      false,
      0,
      0,
      0,
      5 // TODO when checkEmit is available, get offer id after post
    );
    mgo.take{value: 0.1 ether}(buyOrder);
    (uint[] memory live, uint[] memory dead) = mgo.offersOfOwner(
      $(this),
      quote,
      base
    );
    assertTrue(live.length == 2 && dead.length == 0, "Incorrect offer list");
    mgo.retractOffer(quote, base, live[0], false);
    (live, dead) = mgo.offersOfOwner($(this), quote, base);
    assertTrue(
      live.length == 1 && dead.length == 1,
      "Incorrect offer list after retract"
    );
  }
}
