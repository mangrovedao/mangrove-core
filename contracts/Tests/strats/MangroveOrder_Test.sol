// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "../../AbstractMangrove.sol";
import "contracts/Strategies/interfaces/IEIP20.sol";
import "contracts/Strategies/interfaces/IMangrove.sol";
import {MgvLib as ML, P, IMaker} from "../../MgvLib.sol";

import "hardhat/console.sol";

import "../Toolbox/TestUtils.sol";

import "../Agents/TestToken.sol";
import "../Agents/TestMaker.sol";

import {MangroveOrderEnriched as MgvOrder} from "../../Strategies/OrderLogics/MangroveOrderEnriched.sol";
import "../../Strategies/interfaces/IOrderLogic.sol";
import "../../Strategies/interfaces/IOfferLogic.sol";

contract MangroveOrder_Test is HasMgvEvents {
  // to check ERC20 logging
  event Transfer(address indexed from, address indexed to, uint value);

  // to check incident logging
  event LogIncident(
    IMangrove mangrove,
    IEIP20 indexed outbound_tkn,
    IEIP20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 reason
  );

  event OrderSummary(
    IMangrove mangrove,
    IEIP20 indexed base,
    IEIP20 indexed quote,
    address indexed taker,
    bool selling,
    uint takerGot,
    uint takerGave,
    uint penalty,
    uint restingOrderId
  );

  AbstractMangrove mgv;
  IEIP20 base;
  IEIP20 quote;
  address $base;
  address $quote;
  MgvOrder mgvOrder;
  TestMaker bidMkr;
  TestMaker askMkr;
  TestTaker sellTkr;

  receive() external payable {}

  function netBuy(uint price) internal view returns (uint) {
    return price - TestUtils.getFee(mgv, $base, $quote, price);
  }

  function netSell(uint price) internal view returns (uint) {
    return price - TestUtils.getFee(mgv, $quote, $base, price);
  }

  function a_beforeAll() public {
    TestToken tka = TokenSetup.setup("A", "$A");
    $base = address(tka);
    base = IEIP20($base);
    TestToken tkb = TokenSetup.setup("B", "$B");
    $quote = address(tkb);
    quote = IEIP20($quote);

    // returns an activated Mangrove on market (base,quote)
    mgv = MgvSetup.setup(tka, tkb);
    mgv.setFee($base, $quote, 30);
    mgv.setFee($quote, $base, 30);
    // to prevent test runner (taker) from receiving fees!
    mgv.setVault(address(mgv));

    mgvOrder = new MgvOrder(IMangrove(payable(mgv)), address(this)); // this contract is admin of MgvOrder and its router

    // mgvOrder needs to approve mangrove for inbound & outbound token transfer (inbound when acting as a taker, outbound when matched as a maker)
    mgvOrder.approveMangrove(base, type(uint).max);
    mgvOrder.approveMangrove(quote, type(uint).max);

    // mgvOrder needs to approve its router for inbound & outbound token transfer (push and pull from reserve)
    mgvOrder.approveRouter(base);
    mgvOrder.approveRouter(quote);

    // `this` contract will act as `MgvOrder` user
    tkb.mint(address(this), 10 ether);
    tka.mint(address(this), 10 ether);

    // user approves `mgvOrder.router()` in order to be able to pull quote or base when doing a market order and when executing a resting order
    address liquidity_router = address(mgvOrder.router());
    quote.approve(liquidity_router, 10 ether);
    base.approve(liquidity_router, 10 ether);

    // `sellTkr` will take resting offer
    sellTkr = TakerSetup.setup(mgv, $quote, $base);
    tka.mint(address(sellTkr), 10 ether);
    // if seller wants to sell direclty on mangrove
    sellTkr.approve(tka, address(mgv), 10 ether);
    // if seller wants to sell via mgvOrder
    sellTkr.approve(tka, address(mgvOrder), 10 ether);

    // populating order book with offers
    bidMkr = MakerSetup.setup(mgv, $quote, $base);
    payable(bidMkr).transfer(10 ether);
    askMkr = MakerSetup.setup(mgv, $base, $quote);
    payable(askMkr).transfer(10 ether);

    bidMkr.approveMgv(tkb, 10 ether);
    tkb.mint(address(bidMkr), 10 ether);

    tka.mint(address(askMkr), 10 ether);
    askMkr.approveMgv(tka, 10 ether);

    bidMkr.newOfferWithFunding(1 ether, 0.1 ether, 50_000, 0, 0, 0.1 ether);
    bidMkr.newOfferWithFunding(1 ether, 0.11 ether, 50_000, 0, 0, 0.1 ether);
    bidMkr.newOfferWithFunding(1 ether, 0.12 ether, 50_000, 0, 0, 0.1 ether);

    askMkr.newOfferWithFunding(0.13 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    askMkr.newOfferWithFunding(0.14 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    askMkr.newOfferWithFunding(0.15 ether, 1 ether, 50_000, 0, 0, 0.1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Taker");
    Display.register(address(mgvOrder), "MgvOrder");
    Display.register($base, "$A");
    Display.register($quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(askMkr), "Asking maker");
    Display.register(address(bidMkr), "Bidding maker");
    Display.register(address(sellTkr), "Seller taker");

    TestUtils.logOfferBook(mgv, $base, $quote, 3);
    TestUtils.logOfferBook(mgv, $quote, $base, 3);
  }

  function admin_test() public {
    TestEvents.eq(mgv.governance(), mgvOrder.admin(), "Invalid admin address");
  }

  function partial_filled_buy_order_returns_residual_test() public {
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.eq(
      res.takerGot,
      netBuy(1 ether),
      "Incorrect partial fill of taker order"
    );
    TestEvents.eq(
      res.takerGave,
      0.13 ether,
      "Incorrect partial fill of taker order"
    );

    TestEvents.expectFrom($quote); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer(address(this), address(mgvOrder), 0.26 ether);
    emit Transfer(address(mgvOrder), address(this), 0.13 ether);
  }

  function partial_filled_buy_order_reverts_when_noPartialFill_enabled_test()
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
    try mgvOrder.take{value: 0.1 ether}(buyOrder) {
      TestEvents.fail("Partial fill should revert");
    } catch Error(string memory reason) {
      TestEvents.eq(
        reason,
        "mgvOrder/mo/noPartialFill",
        "Unexpected revert reason"
      );
    }
  }

  function partial_filled_buy_order_returns_provision_test() public {
    uint balBefore = address(this).balance;
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.eq(res.takerGot, netBuy(1 ether), "Incorrect taker got");
    TestEvents.eq(
      balBefore,
      address(this).balance,
      "Take function did not return funds"
    );
  }

  function partial_filled_buy_order_returns_bounty_test() public {
    uint balBefore = address(this).balance;
    askMkr.shouldRevert(true);

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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.check(res.bounty > 0, "Bounty should not be zero");
    TestEvents.eq(
      balBefore + res.bounty,
      address(this).balance,
      "Take function did not return bounty"
    );
  }

  function resting_buy_order_reverts_when_unprovisioned_test() public {
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
    try mgvOrder.take{value: 0.0001 ether}(buyOrder) {
      TestEvents.fail("Maker order should have failed.");
    } catch Error(string memory reason) {
      TestEvents.eq(
        reason,
        "MultiUser/derive_gasprice/NotEnoughProvision",
        "Unexpected revert reason"
      );
    }
  }

  function filled_resting_buy_order_ignores_resting_option_test() public {
    uint balQuoteBefore = quote.balanceOf(address(this));
    uint balBaseBefore = base.balanceOf(address(this));

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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.eq(
      quote.balanceOf(address(this)),
      balQuoteBefore - res.takerGave,
      "incorrect quote balance"
    );
    TestEvents.eq(
      base.balanceOf(address(this)),
      balBaseBefore + res.takerGot,
      "incorrect base balance"
    );
  }

  function filled_resting_buy_order_returns_provision_test() public {
    uint balWeiBefore = address(this).balance;

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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    res; // ssh
    TestEvents.eq(address(this).balance, balWeiBefore, "incorrect wei balance");
  }

  function resting_buy_order_is_successfully_posted_test() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: base,
      quote: quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether, // with 2% slippage
      makerWants: 2 ether,
      makerGives: 0.2548 ether, // without 2% slippage
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 // NA
    });
    uint balquoteBefore = mgvOrder.router().reserveBalance(
      quote,
      address(this)
    );
    uint balbaseBefore = mgvOrder.router().reserveBalance(quote, address(this));
    TestEvents.check(
      mgv.balanceOf(address(mgvOrder)) == 0,
      "Invalid balance on Mangrove"
    );

    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.check(
      res.offerId > 0,
      "Resting offer failed to be published on mangrove"
    );

    // checking resting order parameters
    P.Offer.t offer = mgv.offers($quote, $base, res.offerId);
    TestEvents.eq(
      offer.wants(),
      buyOrder.makerWants - (res.takerGot + res.fee),
      "Incorrect wants for bid resting order"
    );
    TestEvents.eq(
      offer.gives(),
      buyOrder.makerGives - res.takerGave,
      "Incorrect gives for bid resting order"
    );

    TestEvents.eq(
      mgvOrder.ownerOf(quote, base, res.offerId),
      address(this),
      "Invalid offer owner"
    );
    TestEvents.eq(
      mgvOrder.router().reserveBalance(quote, address(this)),
      balquoteBefore - res.takerGave,
      "Invalid quote balance"
    );
    TestEvents.eq(
      mgvOrder.router().reserveBalance(base, address(this)),
      balbaseBefore + res.takerGot,
      "Invalid quote balance"
    );
    TestEvents.expectFrom(address(mgvOrder));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      address(this),
      false, //buying
      netBuy(1 ether),
      0.13 ether,
      0,
      res.offerId
    );
  }

  function resting_buy_order_can_be_partially_filled_test() public {
    //mgv.setFee($quote, $base, 0);
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    uint oldLocalBaseBal = base.balanceOf(address(this));
    uint oldRemoteQuoteBal = mgvOrder.router().reserveBalance(
      quote,
      address(this)
    ); // quote balance of test runner

    TestUtils.logOfferBook(mgv, $base, $quote, 4);
    TestUtils.logOfferBook(mgv, $quote, $base, 4);
    (bool success, uint sellTkrGot, uint sellTkrGave, , uint fee) = sellTkr
      .takeWithInfo({offerId: res.offerId, takerWants: 0.1 ether});

    TestEvents.check(success, "Resting order failed");
    // offer delivers
    TestEvents.eq(
      sellTkrGot,
      netSell(0.1 ether),
      "Incorrect received amount for seller taker"
    );
    // inbound token forwarded to test runner
    TestEvents.eq(
      base.balanceOf(address(this)),
      oldLocalBaseBal + sellTkrGave,
      "Incorrect forwarded amount to initial taker"
    );

    TestEvents.eq(
      mgvOrder.router().reserveBalance(quote, address(this)),
      oldRemoteQuoteBal - (sellTkrGot + fee),
      "Incorrect token balance on mgvOrder"
    );

    // checking resting order residual
    P.Offer.t offer = mgv.offers($quote, $base, res.offerId);

    TestEvents.eq(
      offer.gives(),
      buyOrder.gives - res.takerGave - 0.1 ether,
      "Incorrect gives for bid resting order"
    );
  }

  function resting_offer_retracts_when_unable_to_repost_test() public {
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

    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    uint OldWeiBalance = mgvOrder.router().reserveNativeBalance(address(this));
    // increasing density on mangrove so that resting offer can no longer repost
    mgv.setDensity($quote, $base, 1 ether);
    (bool success, , , , ) = sellTkr.takeWithInfo({
      offerId: res.offerId,
      takerWants: 0
    });
    TestEvents.check(success, "snipe failed");
    TestEvents.eq(
      mgvOrder.router().reserveNativeBalance(address(this)),
      OldWeiBalance,
      "retract should not deprovision"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferRetract($quote, $base, res.offerId);
  }

  function user_can_retract_resting_offer_test() public {
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    uint userWeiBalanceOld = mgvOrder.router().reserveNativeBalance(
      address(this)
    );
    uint credited = mgvOrder.retractOffer(quote, base, res.offerId, true);

    TestEvents.eq(
      mgvOrder.router().reserveNativeBalance(address(this)),
      userWeiBalanceOld + credited,
      "Incorrect provision received"
    );
  }

  function failing_resting_offer_releases_uncollected_provision_test() public {
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: provision}(
      buyOrder
    );
    // native token reserve for user
    uint native_reserve_before = mgvOrder.router().reserveNativeBalance(
      address(this)
    );

    // removing base/quote approval to make resting offer fail when matched
    quote.approve(address(mgvOrder.router()), 0);
    base.approve(address(mgvOrder.router()), 0);

    (, , , uint bounty, ) = sellTkr.takeWithInfo({
      offerId: res.offerId,
      takerWants: 1
    });
    TestEvents.check(bounty > 0, "snipe should have failed");
    // collecting released provision
    mgvOrder.retractOffer(quote, base, res.offerId, true);
    uint native_reserve_after = mgvOrder.router().reserveNativeBalance(
      address(this)
    );
    uint UserReleasedProvision = native_reserve_after - native_reserve_before;
    TestEvents.check(UserReleasedProvision > 0, "No released provision");
    // making sure approx is not too bad (UserreleasedProvision in O(provision - res.bounty))
    TestEvents.eq(
      (provision - res.bounty) / UserReleasedProvision,
      1,
      "invalid amount of released provision"
    );
  }

  function iterative_market_order_completes_test() public {
    askMkr.shouldRepost(true);
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.eq(
      res.takerGot,
      netBuy(2 ether),
      "Iterative market order was not complete"
    );
    TestEvents.expectFrom(address(mgv));
    emit OrderComplete(
      $base,
      $quote,
      address(mgvOrder),
      netBuy(1 ether),
      0.13 ether,
      0,
      TestUtils.getFee(mgv, $base, $quote, 1 ether)
    );
    emit OrderComplete(
      $base,
      $quote,
      address(mgvOrder),
      netBuy(1 ether),
      0.13 ether,
      0,
      TestUtils.getFee(mgv, $base, $quote, 1 ether)
    );
    TestEvents.expectFrom(address(mgvOrder));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      address(this),
      false,
      netBuy(2 ether),
      0.26 ether,
      0,
      0
    );
  }

  function ownership_relation_test() public {
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
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    IOrderLogic.TakerOrderResult memory res_ = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.expectFrom(address(mgvOrder));
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      address(this),
      false,
      0,
      0,
      0,
      res.offerId
    );
    emit OrderSummary(
      IMangrove(payable(mgv)),
      base,
      quote,
      address(this),
      false,
      0,
      0,
      0,
      res_.offerId
    );
    (uint[] memory live, uint[] memory dead) = mgvOrder.offersOfOwner(
      address(this),
      quote,
      base
    );
    TestEvents.check(
      live.length == 2 && dead.length == 0,
      "Incorrect offer list"
    );
    mgvOrder.retractOffer(quote, base, live[0], false);
    (live, dead) = mgvOrder.offersOfOwner(address(this), quote, base);
    TestEvents.check(
      live.length == 1 && dead.length == 1,
      "Incorrect offer list after retract"
    );
  }
}
