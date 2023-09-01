// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, LogPriceLib} from "mgv_src/MgvLib.sol";

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
    emit Execute(msg.sender, trade.olKey.outbound, trade.olKey.inbound, trade.offerId, trade.wants, trade.gives);
    return executeReturnData;
  }

  function renew_offer_at_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    mgv.updateOfferByVolume(order.olKey, 1 ether, 1 ether, gasreq, _gasprice, order.offerId);
  }

  function update_gas_offer_at_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    mgv.updateOfferByVolume(order.olKey, 1 ether, 1 ether, gasreq, _gasprice, order.offerId);
  }

  function failer_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    fail("Posthook should not be called");
  }

  function retractOffer_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    uint bal = mgv.balanceOf($(this));
    mgv.retractOffer(olKey, ofr, true);
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
    assertTrue(!mgv.offers(order.olKey, order.offerId).isLive(), "Offer was not removed after take");
    _posthook(order, result);
  }

  function setUp() public override {
    super.setUp();

    tkr = setupTaker(olKey, "Taker");
    deal($(base), $(this), 5 ether);
    deal($(quote), address(tkr), 1 ether);

    tkr.approveMgv(base, 1 ether); // takerFee
    tkr.approveMgv(quote, 1 ether);

    weiBalMaker = mgv.balanceOf($(this));
  }

  function test_renew_offer_after_partial_fill() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom($(mgv));
    // FIXME why does this pass?
    emit OfferWrite(olKey.hash(), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.marketOrderWithSuccess(0.5 ether);
    assertTrue(success, "Snipe should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers(olKey, ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_complete_fill() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    // FIXME why does this expect pass?
    expectFrom($(mgv));
    emit OfferWrite(olKey.hash(), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "Snipe should succeed");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers(olKey, ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_failed_execution() public {
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferWrite(olKey.hash(), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(!success, "Snipe should fail");
    assertTrue(called, "PostHook not called");

    assertEq(mgv.offers(olKey, ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_renew_offer_after_clean() public {
    _posthook = renew_offer_at_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferWrite(olKey.hash(), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.clean(ofr, 2 ether);
    assertTrue(success, "Clean failed");
    assertTrue(called, "PostHook not called");

    assertEq(mgv.offers(olKey, ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function treat_fail_at_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata res) internal {
    called = true;
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
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, 1 ether, 1 ether, 2375880000000000, "mgv/makerRevert");
    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(!success, "market order should fail");
    assertTrue(called, "PostHook not called");
    assertEq(base.balanceOf($(this)), balMaker, "Maker should not have been debited of her base tokens");
    assertEq(quote.balanceOf(address(tkr)), balTaker, "Taker should not have been debited of her quote tokens");
  }

  function test_failed_offer_is_not_executed() public {
    _posthook = treat_fail_at_posthook;
    uint balMaker = base.balanceOf($(this));
    uint balTaker = quote.balanceOf(address(tkr));
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true;

    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, 1 ether, 1 ether, 2517320000000000, "mgv/makerRevert");
    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(!success, "market order should fail");
    assertTrue(called, "PostHook not called");
    assertEq(base.balanceOf($(this)), balMaker, "Maker should not have been debited of her base tokens");
    assertEq(quote.balanceOf(address(tkr)), balTaker, "Taker should not have been debited of her quote tokens");
  }

  function test_update_offer_with_more_gasprice() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    uint standard_provision = reader.getProvision(olKey, gasreq, 0);
    _posthook = update_gas_offer_at_posthook;
    // provision for mgv.global.gasprice
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, 0);

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - standard_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );

    expectFrom($(mgv));
    emit OfferWrite(olKey.hash(), $(this), 0, 1 ether, _gasprice, gasreq, ofr);
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(success, "market order should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker reposts
      "Incorrect maker balance after take"
    );
    assertEq(mgv.offers(olKey, ofr).gives(), 1 ether, "Offer was not correctly updated");
  }

  function test_posthook_of_skipped_offer_wrong_gas_should_not_be_called() public {
    _posthook = failer_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);

    int offerLogPrice = mgv.offers(olKey, ofr).logPrice();
    assertFalse(tkr.cleanByLogPrice(ofr, offerLogPrice, 1 ether, gasreq - 1), "clean should fail");
    assertTrue(!called, "PostHook was called");
  }

  function test_alter_revert_data() public {
    executeReturnData = "NOK2";
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);

    int offerLogPrice = mgv.offers(olKey, ofr).logPrice();
    assertFalse(tkr.cleanByLogPrice(ofr, offerLogPrice, 1 ether, gasreq - 1), "clean should fail");
    // using asserts in makerPosthook here
    assertTrue(!called, "PostHook was called");
  }

  function test_posthook_of_skipped_offer_wrong_price_should_not_be_called() public {
    _posthook = failer_posthook;
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    int newLogPrice = logPrice - 1; // Snipe at a lower price
    assertFalse(tkr.cleanByLogPrice(ofr, newLogPrice, 1 ether, gasreq), "clean should fail");
    assertTrue(!called, "PostHook was called");
  }

  function test_retract_offer_in_posthook() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    expectFrom($(mgv));
    emit Credit($(this), mkr_provision);
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(this), ofr, true);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), ofr, 1 ether, 1 ether);
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(success, "market order should succeed");
    assertTrue(called, "PostHook not called");

    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker, // provision returned to taker
      "Incorrect maker balance after take"
    );
  }

  function test_balance_after_fail_and_retract() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    uint tkr_weis = address(tkr).balance;
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true;
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(this), ofr, true);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(this), 0 /*penalty*/ );
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, 1 ether, 1 ether, 3022440000000000, "mgv/makerRevert");
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(!success, "market order should fail");
    assertTrue(called, "PostHook not called");
    uint penalty = weiBalMaker - mgv.balanceOf($(this));
    assertEq(penalty, address(tkr).balance - tkr_weis, "Incorrect overall balance after penalty for taker");
  }

  function test_update_offer_after_deprovision_in_posthook_succeeds() public {
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(this), ofr, true);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), ofr, 1 ether, 1 ether);
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(success, "market order should succeed");
    assertTrue(called, "PostHook not called");

    mgv.updateOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice, ofr);
  }

  function check_best_in_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal {
    called = true;
    assertEq(mgv.best(olKey), ofr, "Incorrect best offer id in posthook");
  }

  function test_best_in_posthook_is_correct() public {
    mgv.newOfferByVolume(olKey, 2 ether, 1 ether, gasreq, _gasprice);
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    mgv.newOfferByVolume(olKey, 0.5 ether, 1 ether, gasreq, _gasprice);
    _posthook = check_best_in_posthook;
    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "market order should succeed");
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
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 2 ether, gasreq, 500);
    _posthook = check_offer_in_posthook;
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "market order should succeed");
  }

  function check_lastId_in_posthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata) internal {
    called = true;
    (, MgvStructs.LocalPacked cfg) = mgv.config(order.olKey);
    assertEq(cfg.last(), ofr, "Incorrect last offer id in posthook");
  }

  function test_lastId_in_posthook_is_correct() public {
    mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    ofr = mgv.newOfferByVolume(olKey, 0.5 ether, 1 ether, gasreq, _gasprice);
    _posthook = check_lastId_in_posthook;
    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(called, "PostHook not called");
    assertTrue(success, "market order should succeed");
  }

  function test_retract_offer_after_fail_in_posthook() public {
    uint mkr_provision = reader.getProvision(olKey, gasreq, _gasprice);
    _posthook = retractOffer_posthook;
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    assertEq(
      mgv.balanceOf($(this)),
      weiBalMaker - mkr_provision, // maker has provision for his gasprice
      "Incorrect maker balance before take"
    );
    makerRevert = true; // maker should fail
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(this), ofr, true);
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(this), 0 /*refund*/ );
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, 1 ether, 1 ether, 3022440000000000, "mgv/makerRevert");
    bool success = tkr.marketOrderWithSuccess(2 ether);
    assertTrue(called, "PostHook not called");

    assertTrue(!success, "market order should fail");

    assertLt(mgv.balanceOf($(this)), weiBalMaker, "Maker balance after take should be less than original balance");
  }

  function test_makerRevert_is_logged() public {
    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    makerRevert = true; // maker should fail
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, 1 ether, 1 ether, 2491160000000000, "mgv/makerRevert");
    tkr.marketOrderWithSuccess(2 ether);
  }

  function reverting_posthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) internal pure {
    revert("reverting_posthook");
  }

  function test_reverting_posthook_does_not_revert_offer() public {
    reader.getProvision(olKey, gasreq, _gasprice);
    uint balMaker = base.balanceOf($(this));
    uint balTaker = quote.balanceOf(address(tkr));
    _posthook = reverting_posthook;

    ofr = mgv.newOfferByVolume(olKey, 1 ether, 1 ether, gasreq, _gasprice);
    expectFrom($(mgv));
    emit PosthookFail("reverting_posthook");

    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(success, "order should succeed");
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
    TestMaker mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, 10 ether);
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 5 ether);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000);

    // The test contract makes a failing offer, with a good price
    _posthook = checkSorWantsPosthook;
    makerRevert = true;
    mgv.newOfferByVolume(olKey, 1 ether, 1.1 ether, 100_000, 0);

    expectedWants = 0.5 ether;
    expectedGives = 10 * uint(0.5 ether) / 11;

    tkr.marketOrder(0.5 ether, 0.5 ether);
  }

  // Check that a previously-executed posthook does not corrupt the current posthook (when fillWants=false)
  function test_failing_offer_does_not_get_corrupted_sor_gives_values_of_previous_offers_posthook_with_fillWants_false()
    public
  {
    // This maker makes a succeeding offer, with a bad price
    TestMaker mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, 10 ether);
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 5 ether);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000);

    // The test contract makes a failing offer, with a good price
    _posthook = checkSorWantsPosthook;
    makerRevert = true;
    mgv.newOfferByVolume(olKey, 1 ether, 1.1 ether, 100_000, 0);

    expectedGives = 0.5 ether;
    expectedWants = uint(0.5 ether) * 11 / 10;

    tkr.marketOrder(0.5 ether, 0.5 ether, false);
  }
}
