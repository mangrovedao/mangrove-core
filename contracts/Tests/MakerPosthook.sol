// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";

contract MakerPosthook_Test is IMaker, HasMgvEvents {
  AbstractMangrove mgv;
  TestTaker tkr;
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  uint gasreq = 200_000;
  uint ofr;
  bytes4 posthook_bytes;
  uint _gasprice = 50; // will cover for a gasprice of 50 gwei/gas uint
  uint weiBalMaker;
  bool abort = false;
  bool willFail = false;
  bool makerRevert = false;
  bool called;

  event Execute(
    address mgv,
    address base,
    address quote,
    uint offerId,
    uint takerWants,
    uint takerGives
  );

  receive() external payable {}

  function tradeRevert(bytes32 data) internal pure {
    bytes memory revData = new bytes(32);
    assembly {
      mstore(add(revData, 32), data)
      revert(add(revData, 32), 32)
    }
  }

  function makerExecute(MgvLib.SingleOrder calldata trade)
    external
    override
    returns (bytes32)
  {
    require(msg.sender == address(mgv));
    if (makerRevert) {
      tradeRevert("NOK");
    }
    if (abort) {
      return "NOK";
    }
    emit Execute(
      msg.sender,
      trade.outbound_tkn,
      trade.inbound_tkn,
      trade.offerId,
      trade.wants,
      trade.gives
    );
    //MakerTrade.returnWithData("OK");
    return "";
  }

  function renew_offer_at_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    called = true;
    mgv.updateOffer(
      order.outbound_tkn,
      order.inbound_tkn,
      1 ether,
      1 ether,
      gasreq,
      _gasprice,
      order.offerId,
      order.offerId
    );
  }

  function update_gas_offer_at_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    called = true;
    mgv.updateOffer(
      order.outbound_tkn,
      order.inbound_tkn,
      1 ether,
      1 ether,
      gasreq,
      _gasprice,
      order.offerId,
      order.offerId
    );
  }

  function failer_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    called = true;
    TestEvents.fail("Posthook should not be called");
  }

  function retractOffer_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    called = true;
    uint bal = mgv.balanceOf(address(this));
    mgv.retractOffer(base, quote, ofr, true);
    if (abort) {
      TestEvents.eq(
        bal,
        mgv.balanceOf(address(this)),
        "Cancel offer of a failed offer should not give provision to maker"
      );
    }
  }

  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override {
    require(msg.sender == address(mgv));
    bool success = (result.mgvData == "mgv/tradeSuccess");
    TestEvents.eq(
      success,
      !(abort || makerRevert || willFail),
      "incorrect success flag"
    );
    if (makerRevert) {
      TestEvents.eq(
        result.mgvData,
        "mgv/makerRevert",
        "mgvData should be makerRevert"
      );
    } else if (abort) {
      TestEvents.eq(
        result.mgvData,
        "mgv/makerAbort",
        "mgvData should be makerAbort"
      );
    } else {
      TestEvents.eq(
        result.mgvData,
        bytes32("mgv/tradeSuccess"),
        "mgvData should be tradeSuccess"
      );
    }
    TestEvents.check(
      !TestUtils.hasOffer(
        mgv,
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId
      ),
      "Offer was not removed after take"
    );
    bool noRevert;
    (noRevert, ) = address(this).call(
      abi.encodeWithSelector(posthook_bytes, order, result)
    );
  }

  function a_beforeAll() public {
    Display.register(address(this), "Test runner");

    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    Display.register(base, "base");
    Display.register(quote, "quote");

    mgv = MgvSetup.setup(baseT, quoteT);
    Display.register(address(mgv), "Mgv");

    tkr = TakerSetup.setup(mgv, base, quote);
    Display.register(address(tkr), "Taker");

    baseT.approve(address(mgv), 10 ether);

    address(tkr).transfer(10 ether);
    quoteT.mint(address(tkr), 1 ether);
    baseT.mint(address(this), 5 ether);

    tkr.approveMgv(baseT, 1 ether); // takerFee
    tkr.approveMgv(quoteT, 1 ether);

    mgv.fund{value: 10 ether}(address(this)); // for new offer and further updates
    weiBalMaker = mgv.balanceOf(address(this));
  }

  function renew_offer_after_partial_fill_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 0.5 ether);
    TestEvents.check(success, "Snipe should succeed");
    TestEvents.check(called, "PostHook not called");

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(mgv, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferWrite(
      base,
      quote,
      address(this),
      1 ether,
      1 ether,
      _gasprice,
      gasreq,
      ofr,
      0
    );
  }

  function renew_offer_after_complete_fill_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(called, "PostHook not called");
    TestEvents.check(success, "Snipe should succeed");

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(mgv, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferWrite(
      base,
      quote,
      address(this),
      1 ether,
      1 ether,
      _gasprice,
      gasreq,
      ofr,
      0
    );
  }

  function renew_offer_after_failed_execution_test() public {
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    abort = true;

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(called, "PostHook not called");

    TestEvents.eq(
      TestUtils.getOfferInfo(mgv, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferWrite(
      base,
      quote,
      address(this),
      1 ether,
      1 ether,
      _gasprice,
      gasreq,
      ofr,
      0
    );
  }

  function treat_fail_at_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata res
  ) external {
    bool success = (res.mgvData == "mgv/tradeSuccess");
    TestEvents.check(!success, "Offer should be marked as failed");
    TestEvents.check(res.makerData == "NOK", "Incorrect maker data");
  }

  function failed_offer_is_not_executed_test() public {
    posthook_bytes = this.treat_fail_at_posthook.selector;
    uint balMaker = baseT.balanceOf(address(this));
    uint balTaker = quoteT.balanceOf(address(tkr));
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    abort = true;

    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.eq(
      baseT.balanceOf(address(this)),
      balMaker,
      "Maker should not have been debited of her base tokens"
    );
    TestEvents.eq(
      quoteT.balanceOf(address(tkr)),
      balTaker,
      "Taker should not have been debited of her quote tokens"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerAbort"
    );
  }

  function update_offer_with_more_gasprice_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    uint standard_provision = TestUtils.getProvision(mgv, base, quote, gasreq);
    posthook_bytes = this.update_gas_offer_at_posthook.selector;
    // provision for mgv.global.gasprice
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, 0, 0);

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - standard_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(success, "Snipe should succeed");
    TestEvents.check(called, "PostHook not called");

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    TestEvents.eq(
      TestUtils.getOfferInfo(mgv, base, quote, TestUtils.Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferWrite(
      base,
      quote,
      address(this),
      1 ether,
      1 ether,
      _gasprice,
      gasreq,
      ofr,
      0
    );
  }

  function posthook_of_skipped_offer_wrong_gas_should_not_be_called_test()
    public
  {
    posthook_bytes = this.failer_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);

    bool success = tkr.snipe(
      mgv,
      base,
      quote,
      ofr,
      1 ether,
      1 ether,
      gasreq - 1
    );
    TestEvents.check(!called, "PostHook was called");
    TestEvents.check(!success, "Snipe should fail");
  }

  function posthook_of_skipped_offer_wrong_price_should_not_be_called_test()
    public
  {
    posthook_bytes = this.failer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    bool success = tkr.snipe(mgv, base, quote, ofr, 1.1 ether, 1 ether, gasreq);
    TestEvents.check(!success, "Snipe should fail");
    TestEvents.check(!called, "PostHook was called");
  }

  function retract_offer_in_posthook_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(success, "Snipe should succeed");
    TestEvents.check(called, "PostHook not called");

    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker, // provision returned to taker
      "Incorrect maker balance after take"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferSuccess(base, quote, ofr, address(tkr), 1 ether, 1 ether);
    emit Credit(address(this), mkr_provision);
    emit OfferRetract(base, quote, ofr);
  }

  function balance_after_fail_and_retract_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    uint tkr_weis = address(tkr).balance;
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    abort = true;
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(!success, "Snipe should fail");
    uint penalty = weiBalMaker - mgv.balanceOf(address(this));
    TestEvents.eq(
      penalty,
      address(tkr).balance - tkr_weis,
      "Incorrect overall balance after penalty for taker"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerAbort"
    );
    emit OfferRetract(base, quote, ofr);
    emit Credit(address(this), mkr_provision - penalty);
  }

  function update_offer_after_deprovision_in_posthook_succeeds_test() public {
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(called, "PostHook not called");

    TestEvents.check(success, "Snipe should succeed");
    mgv.updateOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0, ofr);
    TestEvents.expectFrom(address(mgv));
    emit OfferSuccess(base, quote, ofr, address(tkr), 1 ether, 1 ether);
    emit OfferRetract(base, quote, ofr);
  }

  function check_best_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    (, bytes32 cfg) = mgv.config(order.outbound_tkn, order.inbound_tkn);
    TestEvents.eq(
      MP.local_unpack_best(cfg),
      ofr,
      "Incorrect best offer id in posthook"
    );
  }

  function best_in_posthook_is_correct_test() public {
    mgv.newOffer(base, quote, 2 ether, 1 ether, gasreq, _gasprice, 0);
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    uint best = mgv.newOffer(
      base,
      quote,
      0.5 ether,
      1 ether,
      gasreq,
      _gasprice,
      0
    );
    posthook_bytes = this.check_best_in_posthook.selector;
    bool success = tkr.take(best, 1 ether);
    TestEvents.check(called, "PostHook not called");
    TestEvents.check(success, "Snipe should succeed");
  }

  function check_offer_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    (, , uint __wants, uint __gives, uint __gasprice) = MgvPack.offer_unpack(
      order.offer
    );
    (address __maker, uint __gasreq, , ) = MgvPack.offerDetail_unpack(
      order.offerDetail
    );
    TestEvents.eq(__wants, 1 ether, "Incorrect wants for offer in posthook");
    TestEvents.eq(__gives, 2 ether, "Incorrect gives for offer in posthook");
    TestEvents.eq(__gasprice, 500, "Incorrect gasprice for offer in posthook");
    TestEvents.eq(__maker, address(this), "Incorrect maker address");
    TestEvents.eq(__gasreq, gasreq, "Incorrect gasreq");
  }

  function check_offer_in_posthook_test() public {
    ofr = mgv.newOffer(base, quote, 1 ether, 2 ether, gasreq, 500, 0);
    posthook_bytes = this.check_offer_in_posthook.selector;
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(called, "PostHook not called");
    TestEvents.check(success, "Snipe should succeed");
  }

  function check_lastId_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    (, bytes32 cfg) = mgv.config(order.outbound_tkn, order.inbound_tkn);
    TestEvents.eq(
      MP.local_unpack_last(cfg),
      ofr,
      "Incorrect last offer id in posthook"
    );
  }

  function lastId_in_posthook_is_correct_test() public {
    mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    ofr = mgv.newOffer(base, quote, 0.5 ether, 1 ether, gasreq, _gasprice, 0);
    posthook_bytes = this.check_lastId_in_posthook.selector;
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(called, "PostHook not called");
    TestEvents.check(success, "Snipe should succeed");
  }

  function retract_offer_after_fail_in_posthook_test() public {
    uint mkr_provision = TestUtils.getProvision(
      mgv,
      base,
      quote,
      gasreq,
      _gasprice
    );
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    TestEvents.eq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    abort = true; // maker should fail
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.check(called, "PostHook not called");

    TestEvents.check(!success, "Snipe should fail");

    TestEvents.less(
      mgv.balanceOf(address(this)),
      weiBalMaker,
      "Maker balance after take should be less than original balance"
    );
    uint refund = mgv.balanceOf(address(this)) + mkr_provision - weiBalMaker;
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerAbort"
    );
    emit OfferRetract(base, quote, ofr);
    emit Credit(address(this), refund);
  }

  function makerRevert_is_logged_test() public {
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    makerRevert = true; // maker should fail
    bool success = tkr.take(ofr, 2 ether);
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
  }

  function reverting_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata
  ) external pure {
    assert(false);
  }

  function reverting_posthook_does_not_revert_offer_test() public {
    TestUtils.getProvision(mgv, base, quote, gasreq, _gasprice);
    uint balMaker = baseT.balanceOf(address(this));
    uint balTaker = quoteT.balanceOf(address(tkr));
    posthook_bytes = this.reverting_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    bool success = tkr.take(ofr, 1 ether);
    TestEvents.check(success, "snipe should succeed");
    TestEvents.eq(
      balMaker - 1 ether,
      baseT.balanceOf(address(this)),
      "Incorrect maker balance"
    );
    TestEvents.eq(
      balTaker - 1 ether,
      quoteT.balanceOf(address(tkr)),
      "Incorrect taker balance"
    );
  }
}
