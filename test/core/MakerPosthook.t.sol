// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

contract MakerPosthookTest is MangroveTest, IMaker {
  TestTaker tkr;
  uint gasreq = 200_000;
  uint ofr;
  uint _gasprice = 50; // will cover for a gasprice of 50 gwei/gas uint
  uint weiBalMaker;
  bool willFail = false;
  bool makerRevert = false;
  bool called;
  string sExecuteRevertData = "NOK";
  bytes32 bExecuteRevertData = "NOK";
  bytes32 executeReturnData = "NOK";

  event Execute(address mgv, address base, address quote, uint offerId, uint takerWants, uint takerGives);

  function makerExecute(MgvLib.SingleOrder calldata trade) external override returns (bytes32) {
    require(msg.sender == $(mgv));
    if (makerRevert) {
      revert(sExecuteRevertData);
    }
    emit Execute(msg.sender, trade.outbound_tkn, trade.inbound_tkn, trade.offerId, trade.wants, trade.gives);
    return executeReturnData;
  }

  function renew_offer_at_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    mgv.updateOfferByVolume(order.outbound_tkn, order.inbound_tkn, 1 ether, 1 ether, gasreq, _gasprice, order.offerId);
  }

  function update_gas_offer_at_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    mgv.updateOfferByVolume(order.outbound_tkn, order.inbound_tkn, 1 ether, 1 ether, gasreq, _gasprice, order.offerId);
  }

  function failer_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    fail("Posthook should not be called");
  }

  function retractOffer_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    uint bal = mgv.balanceOf($(this));
    mgv.retractOffer($(base), $(quote), ofr, true);
    if (makerRevert) {
      assertEq(bal, mgv.balanceOf($(this)), "Cancel offer of a failed offer should not give provision to maker");
    }
  }

  function(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) _posthook;

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external override {
    require(msg.sender == $(mgv));
    bool success = (result.mgvData == "mgv/tradeSuccess");
    assertEq(success, !(makerRevert || willFail), "incorrect success flag");
    if (makerRevert) {
      assertEq(result.mgvData, "mgv/makerRevert", "mgvData should be makerRevert");
      // testing reverted makerData happens in specific tests
    } else {
      assertEq(result.mgvData, bytes32("mgv/tradeSuccess"), "mgvData should be tradeSuccess");
      assertEq(result.makerData, executeReturnData, "Incorrect returned makerData");
    }
    assertTrue(
      !mgv.offers(order.outbound_tkn, order.inbound_tkn, order.offerId).isLive(), "Offer was not removed after take"
    );
    _posthook(order, result);
  }

  function setUp() public override {
    super.setUp();

    tkr = setupTaker($(base), $(quote), "Taker");
    deal($(base), $(this), 5 ether);
    deal($(quote), address(tkr), 1 ether);

    tkr.approveMgv(base, 1 ether); // takerFee
    tkr.approveMgv(quote, 1 ether);

    weiBalMaker = mgv.balanceOf($(this));
  }

  function test_renew_offer_after_partial_fill() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom($(mgv));
    // FIXME why does this pass?
    emit OfferWrite($(base), $(quote), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.take(ofr, 0.5 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers($(base), $(quote), ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_complete_fill() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    // FIXME why does this expect pass?
    expectFrom($(mgv));
    emit OfferWrite($(base), $(quote), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers($(base), $(quote), ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_failed_execution() public {
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferWrite($(base), $(quote), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(!success, "Snipe should fail");
    assertTrue(called, "PostHook not called");

    assertEq(mgv.offers($(base), $(quote), ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_clean() public {
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferWrite($(base), $(quote), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.clean(ofr, 2 ether);
    assertTrue(success, "Clean failed");
    assertTrue(called, "PostHook not called");

    assertEq(mgv.offers($(base), $(quote), ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function treat_fail_at_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata res) internal {
    bool success = (res.mgvData == "mgv/tradeSuccess");
    assertTrue(!success, "Offer should be marked as failed");
    assertTrue(res.makerData == bExecuteRevertData, "Incorrect maker data");
  }

  function test_failed_offer_truncates() public {
    sExecuteRevertData = "abcdefghijklmnopqrstuvwxyz1234567";
    bExecuteRevertData = "abcdefghijklmnopqrstuvwxyz123456";
    _posthook = treat_fail_at_posthook;
    uint balMaker = base.balanceOf($(this));
    uint balTaker = quote.balanceOf(address(tkr));
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;
    expectFrom($(mgv));
    emit OfferFail(ofr, 1 ether, 1 ether, "mgv/makerRevert");
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(!success, "Snipe should fail");
    assertEq(base.balanceOf($(this)), balMaker, "Maker should not have been debited of her base tokens");
    assertEq(quote.balanceOf(address(tkr)), balTaker, "Taker should not have been debited of her quote tokens");
  }

  function test_failed_offer_is_not_executed() public {
    _posthook = treat_fail_at_posthook;
    uint balMaker = base.balanceOf($(this));
    uint balTaker = quote.balanceOf(address(tkr));
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferFail(ofr, 1 ether, 1 ether, "mgv/makerRevert");
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(!success, "Snipe should fail");
    assertEq(base.balanceOf($(this)), balMaker, "Maker should not have been debited of her base tokens");
    assertEq(quote.balanceOf(address(tkr)), balTaker, "Taker should not have been debited of her quote tokens");
  }

  function test_update_offer_with_more_gasprice() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    uint standard_provision = reader.getProvision($(base), $(quote), gasreq);
    _posthook = update_gas_offer_at_posthook;
    // provision for mgv.global.gasprice
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, 0);

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - standard_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom($(mgv));
    emit OfferWrite($(base), $(quote), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers($(base), $(quote), ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_posthook_of_skipped_offer_wrong_gas_should_not_be_called() public {
    _posthook = failer_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);

    bool success = tkr.snipeByVolume(ofr, 1 ether, gasreq - 1);
    assertTrue(!called, "PostHook was called");
    assertTrue(!success, "Snipe should fail");
  }

  function test_alter_revert_data() public {
    executeReturnData = "NOK2";
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);

    bool success = tkr.snipeByVolume(ofr, 1 ether, gasreq - 1);
    // using asserts in makerPosthook here
    assertTrue(!called, "PostHook was called");
    assertTrue(!success, "Snipe should fail");
  }

  function test_posthook_of_skipped_offer_wrong_price_should_not_be_called() public {
    _posthook = failer_posthook;
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    Tick offerTick = mgv.offers($(base), $(quote), ofr).tick();
    Tick snipeTick = Tick.wrap(Tick.unwrap(offerTick) - 1); // Snipe at a lower price tick
    bool success = tkr.snipeByTick(ofr, snipeTick, 1 ether, gasreq);
    assertTrue(!success, "Snipe should fail");
    assertTrue(!called, "PostHook was called");
  }

  function test_retract_offer_in_posthook() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    expectFrom($(mgv));
    emit OfferSuccess(ofr, 1 ether, 1 ether);
    expectFrom($(mgv));
    emit Credit($(this), mkr_provision);
    expectFrom($(mgv));
    emit OfferRetract($(base), $(quote), ofr, true);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker, // provision returned to taker
      "Incorrect maker balance after take"
    );
  }

  function test_balance_after_fail_and_retract() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    uint tkr_weis = address(tkr).balance;
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true;
    expectFrom($(mgv));
    emit OfferFail(ofr, 1 ether, 1 ether, "mgv/makerRevert");
    expectFrom($(mgv));
    emit OfferRetract($(base), $(quote), ofr, true);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(this), 0 /*penalty*/ );
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(!success, "Snipe should fail");
    uint penalty = weiBalMaker - mgv.balanceOf($(this));
    assertEq(penalty, address(tkr).balance - tkr_weis, "Incorrect overall balance after penalty for taker");
  }

  function test_update_offer_after_deprovision_in_posthook_succeeds() public {
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    expectFrom($(mgv));
    emit OfferSuccess(ofr, 1 ether, 1 ether);
    expectFrom($(mgv));
    emit OfferRetract($(base), $(quote), ofr, true);
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");

    assertTrue(success, "Snipe should succeed");
    mgv.updateOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice, ofr);
  }

  function check_best_in_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    assertEq(pair.best(), ofr, "Incorrect best offer id in posthook");
  }

  function test_best_in_posthook_is_correct() public {
    mgv.newOfferByVolume($(base), $(quote), 2 ether, 1 ether, gasreq, _gasprice);
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    uint best = mgv.newOfferByVolume($(base), $(quote), 0.5 ether, 1 ether, gasreq, _gasprice);
    _posthook = check_best_in_posthook;
    bool success = tkr.take(best, 1 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function check_offer_in_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    uint __wants = order.offer.wants();
    uint __gives = order.offer.gives();
    address __maker = order.offerDetail.maker();
    uint __gasreq = order.offerDetail.gasreq();
    uint __gasprice = order.offerDetail.gasprice();
    assertApproxEqRel(__wants, 1 ether, relError(10), "Incorrect wants for offer in posthook");
    assertEq(__gives, 2 ether, "Incorrect gives for offer in posthook");
    assertEq(__gasprice, 500, "Incorrect gasprice for offer in posthook");
    assertEq(__maker, $(this), "Incorrect maker address");
    assertEq(__gasreq, gasreq, "Incorrect gasreq");
  }

  function test_check_offer_in_posthook() public {
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 2 ether, gasreq, 500);
    _posthook = check_offer_in_posthook;
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function check_lastId_in_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    (, MgvStructs.LocalPacked cfg) = mgv.config(order.outbound_tkn, order.inbound_tkn);
    assertEq(cfg.last(), ofr, "Incorrect last offer id in posthook");
  }

  function test_lastId_in_posthook_is_correct() public {
    mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    ofr = mgv.newOfferByVolume($(base), $(quote), 0.5 ether, 1 ether, gasreq, _gasprice);
    _posthook = check_lastId_in_posthook;
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");
  }

  function test_retract_offer_after_fail_in_posthook() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), gasreq, _gasprice);
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true; // maker should fail
    expectFrom($(mgv));
    emit OfferFail(ofr, 1 ether, 1 ether, "mgv/makerRevert");
    expectFrom($(mgv));
    emit OfferRetract($(base), $(quote), ofr, true);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(this), 0 /*refund*/ );
    bool success = tkr.take(ofr, 2 ether);
    assertTrue(called, "PostHook not called");

    assertTrue(!success, "Snipe should fail");

    assertLt(mgv.balanceOf($(this)), weiBalMaker, "Maker balance after take should be less than original balance");
  }

  function test_makerRevert_is_logged() public {
    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true; // maker should fail
    bool success;
    expectFrom($(mgv));
    emit OfferFail(ofr, 1 ether, 1 ether, "mgv/makerRevert");
    success = tkr.take(ofr, 2 ether);
  }

  function reverting_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal pure {
    assert(false);
  }

  function test_reverting_posthook_does_not_revert_offer() public {
    reader.getProvision($(base), $(quote), gasreq, _gasprice);
    uint balMaker = base.balanceOf($(this));
    uint balTaker = quote.balanceOf(address(tkr));
    _posthook = reverting_posthook;

    ofr = mgv.newOfferByVolume($(base), $(quote), 1 ether, 1 ether, gasreq, _gasprice);
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(success, "snipe should succeed");
    assertEq(balMaker - 1 ether, base.balanceOf($(this)), "Incorrect maker balance");
    assertEq(balTaker - 1 ether, quote.balanceOf(address(tkr)), "Incorrect taker balance");
  }

  uint expectedWants;
  uint expectedGives;

  function checkSorWantsPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata) internal {
    assertApproxEqRel(sor.gives, expectedGives, relError({basis_points: 10}), "sor.gives not as expected");
    assertApproxEqRel(sor.wants, expectedWants, relError({basis_points: 10}), "sor.wants not as expected");
  }

  // Check that a previously-executed posthook does not corrupt the current posthook (when fillWants=true)
  function test_failing_offer_does_not_get_corrupted_sor_wants_values_of_previous_offers_posthook_with_fillWants_true()
    public
  {
    // This maker makes a succeeding offer, with a bad price
    TestMaker mkr = setupMaker($(base), $(quote), "maker");
    mkr.approveMgv(base, 10 ether);
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 5 ether);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000);

    // The test contract makes a failing offer, with a good price
    _posthook = checkSorWantsPosthook;
    makerRevert = true;
    mgv.newOfferByVolume($(base), $(quote), 1 ether, 1.1 ether, 100_000, 0);

    expectedWants = 0.5 ether;
    expectedGives = 10 * uint(0.5 ether) / 11;

    tkr.marketOrder(0.5 ether, 0.5 ether);
  }

  // Check that a previously-executed posthook does not corrupt the current posthook (when fillWants=false)
  function test_failing_offer_does_not_get_corrupted_sor_gives_values_of_previous_offers_posthook_with_fillWants_false()
    public
  {
    // This maker makes a succeeding offer, with a bad price
    TestMaker mkr = setupMaker($(base), $(quote), "maker");
    mkr.approveMgv(base, 10 ether);
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 5 ether);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000);

    // The test contract makes a failing offer, with a good price
    _posthook = checkSorWantsPosthook;
    makerRevert = true;
    mgv.newOfferByVolume($(base), $(quote), 1 ether, 1.1 ether, 100_000, 0);

    expectedGives = 0.5 ether;
    expectedWants = uint(0.5 ether) * 11 / 10;

    tkr.marketOrder(0.5 ether, 0.5 ether, false);
  }
}
