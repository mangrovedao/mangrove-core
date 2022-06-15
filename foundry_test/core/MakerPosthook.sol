// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/tools/MangroveTest.sol";

contract MakerPosthook_Test is MangroveTest, IMaker {
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
  bool willFail = false;
  bool makerRevert = false;
  bool called;
  string sExecuteRevertData = "NOK";
  bytes32 bExecuteRevertData = "NOK";
  bytes32 executeReturnData = "NOK";

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
      revert(sExecuteRevertData);
    }
    emit Execute(
      msg.sender,
      trade.outbound_tkn,
      trade.inbound_tkn,
      trade.offerId,
      trade.wants,
      trade.gives
    );
    return executeReturnData;
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
    fail("Posthook should not be called");
  }

  function retractOffer_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata
  ) external {
    require(msg.sender == address(this));
    called = true;
    uint bal = mgv.balanceOf(address(this));
    mgv.retractOffer(base, quote, ofr, true);
    if (makerRevert) {
      assertEq(
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
    assertEq(success, !(makerRevert || willFail), "incorrect success flag");
    if (makerRevert) {
      assertEq(
        result.mgvData,
        "mgv/makerRevert",
        "mgvData should be makerRevert"
      );
    } else {
      assertEq(
        result.mgvData,
        bytes32("mgv/tradeSuccess"),
        "mgvData should be tradeSuccess"
      );
    }
    assertTrue(
      !hasOffer(mgv, order.outbound_tkn, order.inbound_tkn, order.offerId),
      "Offer was not removed after take"
    );
    bool noRevert;
    (noRevert, ) = address(this).call(
      abi.encodeWithSelector(posthook_bytes, order, result)
    );
  }

  function setUp() public {
    vm.label(address(this), "Test runner");

    baseT = setupToken("A", "$A");
    quoteT = setupToken("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    vm.label(base, "base");
    vm.label(quote, "quote");

    mgv = setupMangrove(baseT, quoteT);
    vm.label(address(mgv), "Mgv");

    tkr = setupTaker(mgv, base, quote);
    vm.label(address(tkr), "Taker");

    baseT.approve(address(mgv), 10 ether);

    payable(tkr).transfer(10 ether);
    quoteT.mint(address(tkr), 1 ether);
    baseT.mint(address(this), 5 ether);

    tkr.approveMgv(baseT, 1 ether); // takerFee
    tkr.approveMgv(quoteT, 1 ether);

    mgv.fund{value: 10 ether}(address(this)); // for new offer and further updates
    weiBalMaker = mgv.balanceOf(address(this));
  }

  function test_renew_offer_after_partial_fill() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom(address(mgv));
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
    bool success = tkr.take(ofr, 0.5 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(
      getOfferInfo(mgv, base, quote, Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
  }

  function test_renew_offer_after_complete_fill() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom(address(mgv));
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
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(
      getOfferInfo(mgv, base, quote, Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
  }

  function test_renew_offer_after_failed_execution() public {
    posthook_bytes = this.renew_offer_at_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    makerRevert = true;

    expectFrom(address(mgv));
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
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(!success, "Snipe should fail");
    assertTrue(called, "PostHook not called");

    assertEq(
      getOfferInfo(mgv, base, quote, Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
  }

  function treat_fail_at_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata res
  ) external {
    bool success = (res.mgvData == "mgv/tradeSuccess");
    assertTrue(!success, "Offer should be marked as failed");
    assertTrue(res.makerData == bExecuteRevertData, "Incorrect maker data");
  }

  function test_failed_offer_truncates() public {
    sExecuteRevertData = "abcdefghijklmnopqrstuvwxyz1234567";
    bExecuteRevertData = "abcdefghijklmnopqrstuvwxyz123456";
    uint balMaker = baseT.balanceOf(address(this));
    uint balTaker = quoteT.balanceOf(address(tkr));
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    makerRevert = true;
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(!success, "Snipe should fail");
    assertEq(
      baseT.balanceOf(address(this)),
      balMaker,
      "Maker should not have been debited of her base tokens"
    );
    assertEq(
      quoteT.balanceOf(address(tkr)),
      balTaker,
      "Taker should not have been debited of her quote tokens"
    );
  }

  function test_failed_offer_is_not_executed() public {
    posthook_bytes = this.treat_fail_at_posthook.selector;
    uint balMaker = baseT.balanceOf(address(this));
    uint balTaker = quoteT.balanceOf(address(tkr));
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    makerRevert = true;

    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(!success, "Snipe should fail");
    assertEq(
      baseT.balanceOf(address(this)),
      balMaker,
      "Maker should not have been debited of her base tokens"
    );
    assertEq(
      quoteT.balanceOf(address(tkr)),
      balTaker,
      "Taker should not have been debited of her quote tokens"
    );
  }

  function test_update_offer_with_more_gasprice() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    uint standard_provision = getProvision(mgv, base, quote, gasreq);
    posthook_bytes = this.update_gas_offer_at_posthook.selector;
    // provision for mgv.global.gasprice
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, 0, 0);

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - standard_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom(address(mgv));
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
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(
      getOfferInfo(mgv, base, quote, Info.makerGives, ofr),
      1 ether,
      "Offer was not correctly updated"
    );
  }

  function test_posthook_of_skipped_offer_wrong_gas_should_not_be_called()
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
    assertTrue(!called, "PostHook was called");
    assertTrue(!success, "Snipe should fail");
  }

  function test_posthook_of_skipped_offer_wrong_price_should_not_be_called()
    public
  {
    posthook_bytes = this.failer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    bool success = tkr.snipe(mgv, base, quote, ofr, 1.1 ether, 1 ether, gasreq);
    assertTrue(!success, "Snipe should fail");
    assertTrue(!called, "PostHook was called");
  }

  function test_retract_offer_in_posthook() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    expectFrom(address(mgv));
    emit OfferSuccess(base, quote, ofr, address(tkr), 1 ether, 1 ether);
    expectFrom(address(mgv));
    emit Credit(address(this), mkr_provision);
    expectFrom(address(mgv));
    emit OfferRetract(base, quote, ofr);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker, // provision returned to taker
      "Incorrect maker balance after take"
    );
  }

  function test_balance_after_fail_and_retract() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    uint tkr_weis = address(tkr).balance;
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true;
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    expectFrom(address(mgv));
    emit OfferRetract(base, quote, ofr);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, address(mgv));
    emit Credit(
      address(this),
      0 /*penalty*/
    );
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(!success, "Snipe should fail");
    uint penalty = weiBalMaker - mgv.balanceOf(address(this));
    assertEq(
      penalty,
      address(tkr).balance - tkr_weis,
      "Incorrect overall balance after penalty for taker"
    );
  }

  function test_update_offer_after_deprovision_in_posthook_succeeds() public {
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    expectFrom(address(mgv));
    emit OfferSuccess(base, quote, ofr, address(tkr), 1 ether, 1 ether);
    expectFrom(address(mgv));
    emit OfferRetract(base, quote, ofr);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");

    assertTrue(success, "Snipe should succeed");
    mgv.updateOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0, ofr);
  }

  function check_best_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    (, P.Local.t cfg) = mgv.config(order.outbound_tkn, order.inbound_tkn);
    assertEq(cfg.best(), ofr, "Incorrect best offer id in posthook");
  }

  function test_best_in_posthook_is_correct() public {
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
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function check_offer_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    uint __wants = order.offer.wants();
    uint __gives = order.offer.gives();
    address __maker = order.offerDetail.maker();
    uint __gasreq = order.offerDetail.gasreq();
    uint __gasprice = order.offerDetail.gasprice();
    assertEq(__wants, 1 ether, "Incorrect wants for offer in posthook");
    assertEq(__gives, 2 ether, "Incorrect gives for offer in posthook");
    assertEq(__gasprice, 500, "Incorrect gasprice for offer in posthook");
    assertEq(__maker, address(this), "Incorrect maker address");
    assertEq(__gasreq, gasreq, "Incorrect gasreq");
  }

  function test_check_offer_in_posthook() public {
    ofr = mgv.newOffer(base, quote, 1 ether, 2 ether, gasreq, 500, 0);
    posthook_bytes = this.check_offer_in_posthook.selector;
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function check_lastId_in_posthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata
  ) external {
    called = true;
    (, P.Local.t cfg) = mgv.config(order.outbound_tkn, order.inbound_tkn);
    assertEq(cfg.last(), ofr, "Incorrect last offer id in posthook");
  }

  function test_lastId_in_posthook_is_correct() public {
    mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    ofr = mgv.newOffer(base, quote, 0.5 ether, 1 ether, gasreq, _gasprice, 0);
    posthook_bytes = this.check_lastId_in_posthook.selector;
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function test_retract_offer_after_fail_in_posthook() public {
    uint mkr_provision = getProvision(mgv, base, quote, gasreq, _gasprice);
    posthook_bytes = this.retractOffer_posthook.selector;
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    assertEq(
      mgv.balanceOf(address(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true; // maker should fail
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    expectFrom(address(mgv));
    emit OfferRetract(base, quote, ofr);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, address(mgv));
    emit Credit(
      address(this),
      0 /*refund*/
    );
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");

    assertTrue(!success, "Snipe should fail");

    assertLt(
      mgv.balanceOf(address(this)),
      weiBalMaker,
      "Maker balance after take should be less than original balance"
    );
    uint refund = mgv.balanceOf(address(this)) + mkr_provision - weiBalMaker;
    console.log(refund);
  }

  function test_makerRevert_is_logged() public {
    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    makerRevert = true; // maker should fail
    bool success;
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(tkr),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    success = tkr.take(ofr, 2 ether);
  }

  function reverting_posthook(
    MgvLib.SingleOrder calldata,
    MgvLib.OrderResult calldata
  ) external pure {
    assert(false);
  }

  function test_reverting_posthook_does_not_revert_offer() public {
    getProvision(mgv, base, quote, gasreq, _gasprice);
    uint balMaker = baseT.balanceOf(address(this));
    uint balTaker = quoteT.balanceOf(address(tkr));
    posthook_bytes = this.reverting_posthook.selector;

    ofr = mgv.newOffer(base, quote, 1 ether, 1 ether, gasreq, _gasprice, 0);
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(success, "snipe should succeed");
    assertEq(
      balMaker - 1 ether,
      baseT.balanceOf(address(this)),
      "Incorrect maker balance"
    );
    assertEq(
      balTaker - 1 ether,
      quoteT.balanceOf(address(tkr)),
      "Incorrect taker balance"
    );
  }
}
