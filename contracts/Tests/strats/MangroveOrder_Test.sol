// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "../../AbstractMangrove.sol";
import {MgvLib as ML, P, IMaker} from "../../MgvLib.sol";

import "hardhat/console.sol";

import "../Toolbox/TestUtils.sol";

import "../Agents/TestToken.sol";
import "../Agents/TestMaker.sol";

import {MangroveOrder as MgvOrder} from "../../Strategies/OrderLogics/MangroveOrder.sol";
import "../../Strategies/interfaces/IOrderLogic.sol";

contract MangroveOrder_Test is HasMgvEvents {
  using P.Global for P.Global.t;
  using P.OfferDetail for P.OfferDetail.t;
  using P.Offer for P.Offer.t;
  using P.Local for P.Local.t;

  // to check ERC20 logging
  event Transfer(address indexed from, address indexed to, uint value);

  // to check incident logging
  event LogIncident(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    bytes32 reason
  );

  event OrderSummary(
    address indexed base,
    address indexed quote,
    address indexed taker,
    uint takerGot,
    uint takerGave,
    uint bounty,
    uint restingOrderId
  );

  AbstractMangrove mgv;
  TestToken base;
  TestToken quote;
  address _base;
  address _quote;
  MgvOrder mgvOrder;
  TestMaker bidMkr;
  TestMaker askMkr;
  TestTaker sellTkr;

  receive() external payable {}

  function netBuy(uint price) internal view returns (uint) {
    return price - TestUtils.getFee(mgv, _base, _quote, price);
  }

  function netSell(uint price) internal view returns (uint) {
    return price - TestUtils.getFee(mgv, _quote, _base, price);
  }

  function a_beforeAll() public {
    base = TokenSetup.setup("A", "$A");
    _base = address(base);
    quote = TokenSetup.setup("B", "$B");
    _quote = address(quote);

    // returns an activated Mangrove on market (base,quote)
    mgv = MgvSetup.setup(base, quote);
    mgv.setFee(_base, _quote, 30);
    mgv.setFee(_quote, _base, 30);
    // to prevent test runner (taker) from receiving fees!
    mgv.setVault(address(mgv));

    mgvOrder = new MgvOrder(payable(mgv));

    // mgvOrder needs to approve mangrove for outbound token transfer
    mgvOrder.approveMangrove(_base);
    mgvOrder.approveMangrove(_quote);

    //adding provision on Mangrove for `mgvOrder` in order to fake having already multiple users
    mgv.fund{value: 1 ether}(address(mgvOrder));

    // `this` contract will act as `MgvOrder` user
    quote.mint(address(this), 10 ether);
    base.mint(address(this), 10 ether);

    // user approves `mgvOrder` to pull quote or base when doing a market order
    quote.approve(address(mgvOrder), 10 ether);
    base.approve(address(mgvOrder), 10 ether);

    // `sellTkr` will take resting offer
    sellTkr = TakerSetup.setup(mgv, _quote, _base);
    base.mint(address(sellTkr), 10 ether);
    // if seller wants to sell direclty on mangrove
    sellTkr.approve(base, address(mgv), 10 ether);
    // if seller wants to sell via mgvOrder
    sellTkr.approve(base, address(mgvOrder), 10 ether);

    // populating order book with offers
    bidMkr = MakerSetup.setup(mgv, _quote, _base);
    payable(bidMkr).transfer(10 ether);
    askMkr = MakerSetup.setup(mgv, _base, _quote);
    payable(askMkr).transfer(10 ether);

    bidMkr.approveMgv(quote, 10 ether);
    quote.mint(address(bidMkr), 10 ether);

    base.mint(address(askMkr), 10 ether);
    askMkr.approveMgv(base, 10 ether);

    bidMkr.newOfferWithFunding(1 ether, 0.1 ether, 50_000, 0, 0, 0.1 ether);
    bidMkr.newOfferWithFunding(1 ether, 0.11 ether, 50_000, 0, 0, 0.1 ether);
    bidMkr.newOfferWithFunding(1 ether, 0.12 ether, 50_000, 0, 0, 0.1 ether);

    askMkr.newOfferWithFunding(0.13 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    askMkr.newOfferWithFunding(0.14 ether, 1 ether, 50_000, 0, 0, 0.1 ether);
    askMkr.newOfferWithFunding(0.15 ether, 1 ether, 50_000, 0, 0, 0.1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Taker");
    Display.register(address(mgvOrder), "MgvOrder");
    Display.register(_base, "$A");
    Display.register(_quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(askMkr), "Asking maker");
    Display.register(address(bidMkr), "Bidding maker");
    Display.register(address(sellTkr), "Seller taker");

    TestUtils.logOfferBook(mgv, _base, _quote, 3);
    TestUtils.logOfferBook(mgv, _quote, _base, 3);
  }

  function partial_filled_buy_order_returns_residual_test() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take(buyOrder);
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

    TestEvents.expectFrom(_quote); // checking quote is sent to mgv and remainder is sent back to taker
    emit Transfer(address(this), address(mgvOrder), 0.26 ether);
    emit Transfer(address(mgvOrder), address(this), 0.13 ether);
  }

  function partial_filled_buy_order_reverts_when_noPartialFill_enabled_test()
    public
  {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: true,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: false,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    try mgvOrder.take(buyOrder) {
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
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
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
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
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
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    try mgvOrder.take(buyOrder) {
      TestEvents.fail("Maker order should have failed.");
    } catch Error(string memory reason) {
      TestEvents.eq(
        reason,
        "Multi/debitOnMgv/insufficient",
        "Unexpected revert reason"
      );
    }
  }

  function filled_resting_buy_order_ignores_resting_option_test() public {
    uint balQuoteBefore = quote.balanceOf(address(this));
    uint balBaseBefore = base.balanceOf(address(this));

    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 1 ether,
      gives: 0.13 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take(buyOrder);
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
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 1 ether,
      gives: 0.13 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take(buyOrder);
    res; // ssh
    TestEvents.eq(address(this).balance, balWeiBefore, "incorrect wei balance");
  }

  function resting_buy_order_is_successfully_posted_test() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    TestEvents.check(
      res.offerId > 0,
      "Resting offer failed to be published on mangrove"
    );

    // checking resting order parameters
    P.Offer.t offer = mgv.offers(_quote, _base, res.offerId);
    TestEvents.eq(
      offer.wants(),
      buyOrder.wants - res.takerGot,
      "Incorrect wants for bid resting order"
    );
    TestEvents.eq(
      offer.gives(),
      buyOrder.gives - res.takerGave,
      "Incorrect gives for bid resting order"
    );

    // checking `mgvOrder` mappings
    uint prov = mgvOrder.getMissingProvision(
      _quote,
      _base,
      mgvOrder.OFR_GASREQ(),
      0,
      0
    );
    TestEvents.eq(
      mgvOrder.balanceOnMangrove(),
      0.1 ether - prov,
      "Incorrect user balance on mangrove"
    );
    TestEvents.eq(
      mgvOrder.ownerOf(_quote, _base, res.offerId),
      address(this),
      "Invalid offer owner"
    );
    TestEvents.eq(
      mgvOrder.tokenBalance(_quote),
      0.13 ether,
      "Invalid offer owner"
    );
    TestEvents.expectFrom(address(mgvOrder));
    emit OrderSummary(
      _base,
      _quote,
      address(this),
      netBuy(1 ether),
      0.13 ether,
      0,
      res.offerId
    );
  }

  function resting_buy_order_can_be_partially_filled_test() public {
    mgv.setFee(_quote, _base, 0);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    uint oldLocalBaseBal = base.balanceOf(address(this));
    uint oldRemoteQuoteBal = mgvOrder.tokenBalance(_quote); // quote balance of test runner

    // TestUtils.logOfferBook(mgv,_base,_quote,4);
    // TestUtils.logOfferBook(mgv,_quote,_base,4);

    (bool success, uint sellTkrGot, uint sellTkrGave) = sellTkr.takeWithInfo({
      offerId: res.offerId,
      takerWants: 0.1 ether
    });

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
    // outbound token debited from test runner account on `mgvOrder`
    // computation below is incorrect when fee != 0 since sellTkrGot is net for taker and brut should be taken from Quote balance
    // setting fees to 0 to have correct computation

    TestEvents.eq(
      mgvOrder.tokenBalance(_quote),
      oldRemoteQuoteBal - sellTkrGot,
      "Incorrect token balance on mgvOrder"
    );

    // checking resting order residual
    P.Offer.t offer = mgv.offers(_quote, _base, res.offerId);

    TestEvents.eq(
      offer.gives(),
      buyOrder.gives - res.takerGave - 0.1 ether,
      "Incorrect gives for bid resting order"
    );
  }

  function resting_offer_deprovisions_when_unable_to_repost_test() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    // test runner quote balance on the gateway
    uint balQuoteRemote = mgvOrder.tokenBalance(_quote);
    uint balQuoteLocal = quote.balanceOf(address(this));

    // increasing density on mangrove so that resting offer can no longer repost
    mgv.setDensity(_quote, _base, 1 ether);
    (bool success, , ) = sellTkr.takeWithInfo({
      offerId: res.offerId,
      takerWants: 0
    });
    TestEvents.check(success, "snipe failed");
    TestEvents.eq(
      quote.balanceOf(address(this)),
      balQuoteLocal + balQuoteRemote,
      "Quote was not transfered to user"
    );
    TestEvents.check(
      mgvOrder.tokenBalance(_quote) == 0,
      "Inconsistent token balance"
    );
    TestEvents.check(
      mgvOrder.balanceOnMangrove() == 0,
      "Inconsistent wei balance"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferRetract(_quote, _base, res.offerId);
  }

  function user_can_retract_resting_offer_test() public {
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
      restingOrder: true,
      retryNumber: 0,
      gasForMarketOrder: 6_500_000,
      blocksToLiveForRestingOrder: 0 //NA
    });
    IOrderLogic.TakerOrderResult memory res = mgvOrder.take{value: 0.1 ether}(
      buyOrder
    );
    uint userWeiOnMangroveOld = mgvOrder.balanceOnMangrove();
    uint userWeiBalanceLocalOld = address(this).balance;
    uint credited = mgvOrder.retractOffer(_quote, _base, res.offerId, true);
    TestEvents.eq(
      mgvOrder.balanceOnMangrove(),
      userWeiOnMangroveOld + credited,
      "Incorrect wei balance after retract"
    );
    TestEvents.check(
      mgvOrder.withdrawFromMangrove(
        payable(this),
        mgvOrder.balanceOnMangrove()
      ),
      "Withdraw failed"
    );
    TestEvents.eq(
      address(this).balance,
      userWeiBalanceLocalOld + userWeiOnMangroveOld + credited,
      "Incorrect provision received"
    );
  }

  function iterative_market_order_completes_test() public {
    askMkr.shouldRepost(true);
    IOrderLogic.TakerOrder memory buyOrder = IOrderLogic.TakerOrder({
      base: _base,
      quote: _quote,
      partialFillNotAllowed: false,
      selling: false, //i.e buying
      wants: 2 ether,
      gives: 0.26 ether,
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
      _base,
      _quote,
      address(mgvOrder),
      netBuy(1 ether),
      0.13 ether,
      0,
      TestUtils.getFee(mgv, _base, _quote, 1 ether)
    );
    emit OrderComplete(
      _base,
      _quote,
      address(mgvOrder),
      netBuy(1 ether),
      0.13 ether,
      0,
      TestUtils.getFee(mgv, _base, _quote, 1 ether)
    );
    TestEvents.expectFrom(address(mgvOrder));
    emit OrderSummary(
      _base,
      _quote,
      address(this),
      netBuy(2 ether),
      0.26 ether,
      0,
      0
    );
  }
}
