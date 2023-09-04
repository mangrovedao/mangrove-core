// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MAX_TICK, MIN_TICK, LogPriceLib} from "mgv_lib/TickLib.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.*/
contract TakerOperationsTest is MangroveTest {
  TestMaker mkr;
  TestMaker refusemkr;
  TestMaker failmkr;
  TestMaker failNonZeroMkr;

  bool refuseReceive = false;

  receive() external payable {
    if (refuseReceive) {
      revert("no");
    }
  }

  function setUp() public override {
    super.setUp();

    // reset approvals
    base.approve($(mgv), 0);
    quote.approve($(mgv), 0);

    mkr = setupMaker(olKey, "maker");
    refusemkr = setupMaker(olKey, "refusing mkr");
    refusemkr.shouldFail(true);
    failmkr = setupMaker(olKey, "reverting mkr");
    failmkr.shouldRevert(true);
    failNonZeroMkr = setupMaker(olKey, "reverting on non-zero mkr");
    failNonZeroMkr.shouldRevertOnNonZeroGives(true);

    mkr.provisionMgv(10 ether);
    mkr.approveMgv(base, 10 ether);

    refusemkr.provisionMgv(1 ether);
    refusemkr.approveMgv(base, 10 ether);
    failmkr.provisionMgv(1 ether);
    failmkr.approveMgv(base, 10 ether);
    failNonZeroMkr.provisionMgv(1 ether);
    failNonZeroMkr.approveMgv(base, 10 ether);

    deal($(base), address(mkr), 5 ether);
    deal($(base), address(failmkr), 5 ether);
    deal($(base), address(refusemkr), 5 ether);
    deal($(base), address(failNonZeroMkr), 5 ether);

    deal($(quote), address(this), 10 ether);
  }

  /* # `execute` tests */
  /* Test of `execute` which cannot be tested directly, so we test it via `marketOrder`. */

  function test_execute_reverts_if_taker_is_blacklisted_for_quote() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    quote.blacklists($(this));

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  function test_execute_reverts_if_taker_is_blacklisted_for_base() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    base.blacklists($(this));

    vm.expectRevert("mgv/MgvFailToPayTaker");
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  // The purpose of this test is to make sure inbound volumes are rounded up when partially
  // taking an offer i.e. you can't have the taker pay 0 if the maker sends > 0 to the taker.
  // The test sets this up with a wants=9, gives=10 offer, and the taker asks for a volume of 1.
  function test_taker_cannot_drain_maker() public {
    mgv.setDensityFixed(olKey, 0);
    quote.approve($(mgv), 1 ether);
    mkr.newOfferByVolume(9, 10, 100_000, 0);
    uint oldBal = quote.balanceOf($(this));
    mgv.marketOrderByLogPrice(olKey, LogPriceLib.MAX_LOG_PRICE, 1, true);
    uint newBal = quote.balanceOf($(this));
    assertGt(oldBal, newBal, "oldBal should be strictly higher");
  }

  function test_execute_fillWants() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice + 1, 0.5 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(got, 0.5 ether, "Taker did not get correct amount");
    assertEq(gave, 0.5 ether, "Taker did not give correct amount");
  }

  function test_execute_free_offer_fillWants_respects_spec() public {
    uint ofr = mkr.newOfferByVolume(1, 1 ether, 100_000, 0);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    /* Setting fillWants = true means we should not receive more than `wants`.
       Here we are asking for 0.1 eth to an offer that gives 1eth for ~nothing.
       We should still only receive 0.1 eth */
    int logPrice = LogPriceLib.logPriceFromPrice_e18(1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 0.1 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertApproxEqRel(got, 0.1 ether, relError(10), "Wrong got value");
    assertApproxEqRel(gave, 1, relError(10), "Wrong gave value");
    assertTrue(!mgv.offers(olKey, ofr).isLive(), "Offer should not be in the book");
  }

  function test_execute_free_offer_fillGives_respects_spec() public {
    uint ofr = mkr.newOfferByVolume(0.01 ether, 1 ether, 100_000, 0);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    /* Setting fillWants = false means we should spend as little as possible to receive
       as much as possible.
       Here despite asking for .1eth the offer gives 1eth for ~0 so we should receive 1eth. */
    int logPrice = LogPriceLib.logPriceFromPrice_e18(1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 0.1 ether, false);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertApproxEqRel(got, 1 ether, relError(10), "Wrong got value");
    assertApproxEqRel(gave, 0.01 ether, relError(10), "Wrong gave value");
    assertTrue(!mgv.offers(olKey, ofr).isLive(), "Offer should not be in the book");
  }

  function test_execute_fillGives() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    int logPrice = LogPriceLib.logPriceFromPrice_e18(1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, false);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(got, 1 ether, "Taker did not get correct amount");
    assertEq(gave, 1 ether, "Taker did not get correct amount");
  }

  /* # Market order tests */

  event Transfer(address indexed from, address indexed to, uint value);

  function test_mo_fillWants() public {
    uint ofr1 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int offerLogPrice1 = mgv.offers(olKey, ofr1).logPrice();
    int offerLogPrice2 = mgv.offers(olKey, ofr2).logPrice();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);

    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 1 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 1 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 1 ether);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), ofr1, $(this), 1 ether, LogPriceLib.inboundFromOutbound(offerLogPrice1, 1 ether));

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0.1 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0.1 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 0.1 ether);
    expectFrom($(mgv));
    emit OfferSuccess(
      olKey.hash(), ofr2, $(this), 0.1 ether, LogPriceLib.inboundFromOutbound(offerLogPrice2, 0.1 ether)
    );

    expectFrom($(base));
    emit Transfer($(mgv), $(this), 1.1 ether);
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 1.1 ether, 1.1 ether, 0, 0);

    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 1.1 ether, 1.9 ether, true);

    assertEq(got, 1.1 ether, "Taker did not get correct amount");
    assertEq(gave, 1.1 ether, "Taker did not get correct amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr1), "ofr1 must be executed or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr2), "ofr2 must be executed or test is void");
    assertFalse(mgv.offers(olKey, ofr1).isLive(), "Offer 1 should not be in the book");
    assertFalse(mgv.offers(olKey, ofr2).isLive(), "Offer 2 should not be in the book");
  }

  function test_mo_fillWants_zero() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    quote.approve($(mgv), 1 ether);

    expectFrom($(mgv));
    emit OrderStart();
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, 0);

    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 0, true);

    assertEq(got, 0 ether, "Taker had too much");
    assertEq(gave, 0 ether, "Taker gave too much");
    assertFalse(mkr.makerExecuteWasCalled(ofr), "ofr must not be executed or test is void");
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
  }

  function test_mo_newBest() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    quote.approve($(mgv), 2 ether);
    assertEq(mgv.best(olKey), ofr, "wrong best offer");
    mgv.marketOrderByVolume(olKey, 2 ether, 4 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(mgv.best(olKey), 0, "there should not be a best offer anymore");
  }

  function test_mo_fillGives() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 1.1 ether, 1.9 ether, false);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr2), "ofr2 must be executed or test is void");
    assertEq(got, 1.9 ether, "Taker did not get correct amount");
    assertEq(gave, 1.9 ether, "Taker did not give correct amount");
  }

  function test_mo_fillGives_zero() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    expectFrom($(mgv));
    emit OrderStart();
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, 0);

    (uint got, uint gave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 0 ether, false);
    assertEq(got, 0 ether, "Taker had too much");
    assertEq(gave, 0 ether, "Taker gave too much");
    assertFalse(mkr.makerExecuteWasCalled(ofr), "ofr must not be executed or test is void");
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
  }

  function test_mo_fillGivesAll_no_approved_fails() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByVolume(olKey, 0 ether, 3 ether, false);
  }

  function test_mo_fillGivesAll_succeeds() public {
    uint ofr1 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 3 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 0 ether, 3 ether, false);
    assertEq(got, 3 ether, "Taker did not get correct amount");
    assertEq(gave, 3 ether, "Taker did not get correct amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr1), "ofr1 must be executed or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr2), "ofr2 must be executed or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr3), "ofr2 must be executed or test is void");
  }

  function test_taker_reimbursed_if_maker_doesnt_pay() public {
    // uint mkr_provision = reader.getProvision(olKey, 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = refusemkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 1 ether, 1 ether, "mgv/makerTransferFail");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(refusemkr), 0 /*mkr_provision - penalty*/ );
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, logPrice, 100_000, 1 ether)), $(this));
    assertEq(successes, 1, "clean should succeed");
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(refusemkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_reverts_on_penalty_triggers_revert() public {
    uint ofr = refusemkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    refuseReceive = true;
    quote.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/sendPenaltyReverted");
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_base() public {
    // uint mkr_provision = reader.getProvision(olKey, 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook

    base.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 1 ether, 1 ether, "mgv/makerTransferFail");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(mkr), 0 /*mkr_provision - penalty*/ );
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_quote() public {
    // uint mkr_provision = reader.getProvision(olKey, 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/makerReceiveFail"); // status visible in the posthook

    quote.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 1 ether, 1 ether, "mgv/makerReceiveFail");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(mkr), 0 /*mkr_provision - penalty*/ );
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_collects_failing_offer() public {
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    uint beforeWei = $(this).balance;

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertTrue(takerGot == takerGave && takerGave == 0, "Transaction data should be 0");
    assertTrue($(this).balance > beforeWei, "Taker was not compensated");
    assertTrue(failmkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_reimbursed_if_maker_reverts() public {
    // uint mkr_provision = reader.getProvision(olKey, 50_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 1 ether, 1 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(failmkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_hasnt_approved_base_succeeds_order_with_fee() public {
    mgv.setFee(olKey, 3);

    uint balTaker = base.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    quote.approve($(mgv), 1 ether);
    uint shouldGet = reader.minusFee(olKey, 1 ether);
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertEq(base.balanceOf($(this)) - balTaker, shouldGet, "Incorrect delivered amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr execute must be called or test is void");
  }

  function test_taker_hasnt_approved_base_succeeds_order_wo_fee() public {
    uint balTaker = base.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    quote.approve($(mgv), 1 ether);
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertEq(base.balanceOf($(this)) - balTaker, 1 ether, "Incorrect delivered amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr execute must be called or test is void");
  }

  function test_taker_hasnt_approved_quote_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    base.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
  }

  function test_simple_marketOrder() public {
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1.2 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess");

    base.approve($(mgv), 10 ether);
    quote.approve($(mgv), 10 ether);
    uint balTaker = base.balanceOf($(this));
    uint balMaker = quote.balanceOf(address(mkr));

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume(olKey, 2 ether, 4 ether, true);
    assertTrue(mkr.makerPosthookWasCalled(ofr1), "ofr1 posthook must be called or test is void");
    assertTrue(mkr.makerPosthookWasCalled(ofr2), "ofr2 posthook must be called or test is void");
    assertApproxEqRel(takerGot, 2 ether, relError(10), "Incorrect declared delivered amount (taker)");
    assertApproxEqRel(takerGave, 2.3 ether, relError(10), "Incorrect declared delivered amount (maker)");
    assertApproxEqRel(base.balanceOf($(this)) - balTaker, 2 ether, relError(10), "Incorrect delivered amount (taker)");
    assertApproxEqRel(
      quote.balanceOf(address(mkr)) - balMaker, 2.3 ether, relError(10), "Incorrect delivered amount (maker)"
    );
  }

  function test_simple_fillWants() public {
    uint ofr = mkr.newOfferByVolume(2 ether, 2 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume(olKey, 1 ether, 2 ether, true);
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(takerGot, 1 ether, "Incorrect declared delivered amount (taker)");
    assertEq(takerGave, 1 ether, "Incorrect declared delivered amount (maker)");
  }

  function test_simple_fillGives() public {
    uint ofr = mkr.newOfferByVolume(2 ether, 2 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume(olKey, 1 ether, 2 ether, false);
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  // before ticks: testing whether a wants of 0 works
  // after ticks: wants of 0 not possible since we store log(wants/gives) as tick. Testing with an extremely small amount.
  function test_fillGives_at_0_wants_works() public {
    uint ofr = mkr.newOfferByVolume(10, 2 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 10, false);
    // console.log("offer wants",mgv.offers(olKey,ofr).wants());
    // console.log("offer tick",mgv.offers(olKey,ofr).tick().toString());
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(takerGave, 10, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillGives() public {
    uint ofr = mkr.newOfferByVolume(2 ether, 2 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume(olKey, 0 ether, 2 ether, false);
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillWants() public {
    uint ofr = mkr.newOfferByVolume(2 ether, 2 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume(olKey, 0 ether, 2 ether, true);
    assertFalse(mkr.makerPosthookWasCalled(ofr), "ofr posthook must not be called or test is void");
    assertEq(takerGave, 0 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 0 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_taker_has_no_quote_fails_order() public {
    uint ofr = mkr.newOfferByVolume(100 ether, 2 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/tradeSuccess");

    quote.approve($(mgv), 100 ether);
    base.approve($(mgv), 1 ether); // not necessary since no fee

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByLogPrice(olKey, logPrice, 2 ether, true);
  }

  function test_maker_has_not_enough_base_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/makerTransferFail");
    // getting rid of base tokens
    //mkr.transferToken(base,$(this),5 ether);
    quote.approve($(mgv), 0.5 ether);
    MgvStructs.OfferPacked offer = mgv.offers(olKey, ofr);

    uint takerWants = 50 ether;
    expectFrom($(mgv));
    emit OfferFail(
      olKey.hash(),
      ofr,
      $(this),
      takerWants,
      LogPriceLib.inboundFromOutbound(offer.logPrice(), takerWants),
      "mgv/makerTransferFail"
    );
    (,, uint bounty,) = mgv.marketOrderByLogPrice(olKey, logPrice, 50 ether, true);
    assertTrue(bounty > 0, "offer should fail");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  // FIXME remove this manual test when the reason for why it was failing is clear
  /* It stops failing if I redefine inboundFromOutboundUpTick as
      uint nextPrice_e18 = Tick.wrap(logPrice+1).priceFromTick_e18();
      uint prod = nextPrice_e18 * outboundAmt;
      return prod/1e18 + (prod%1e18==0 ? 0 : 1);
  */
  // function test_manual() public {
  //   test_snipe_correct_amount_auto(22701, 20214603739982190561, 2, 0);
  // }

  // FIXME restricting to uint72 so maximum price is not reached
  // FIXME: This fails with args=[1, 2, 1, 0], unclear why. Commenting out for now.
  // function test_snipe_correct_amount_auto(uint72 makerWants, uint72 makerGives, uint72 factor1, uint16 pc) public {
  //   vm.assume(factor1 > 0);
  //   vm.assume(makerWants > 0);
  //   vm.assume(makerGives > 0);

  //   // uint takerWants = uint(makerGives) / (uint(factor1)*uint(factor2));
  //   uint takerWants = uint(makerGives) / uint(factor1);
  //   // uint takerWants = uint(makerGives) *100 / (uint(factor1)*uint(factor2)*100);
  //   // uint takerGives = uint(makerWants) *100 / (uint(factor1)*100);

  //   // vm.assume(takerWants > 0);

  //   mgv.setDensityFixed(olKey, 0);
  //   uint ofr = mkr.newOfferByVolume(makerWants, makerGives, 100_000, 0);
  //   MgvStructs.OfferPacked offer = mgv.offers(olKey,ofr);
  //   pc = uint16(bound(pc, 0, 10_000));
  //   Tick takerTick = offer.tick(olKey.tickScale);
  //   // if I round down takerGives: what? well I reudce the price allowed, and so might mistakenly think (in execute()) that the taker is not ok with the offer (because I reduced the price more here, than I reduced it when I stored the offer?).
  //   // but then if I round it up, somehow I get also a roudned down takerGave in execute(), that is even lower a.... ahhh?

  //   // Actual makerWants due to loss of precision when inserting offer.
  //   makerWants = uint72(offer.wants());
  //   uint takerGives = takerWants == 0 ? 0 : takerTick.inboundFromOutboundUpTick(takerWants);
  //   vm.assume(uint72(takerGives) == takerGives);

  //   if (takerGives > 0) {
  //     uint takerPriceE18 = takerGives * 1e18 / takerWants;
  //     // If price is not high enough then we it must because of rounding due to too small gives/wants.
  //     if (takerTick.priceFromTick_e18() > takerPriceE18) {
  //       // ensure just one more gives passes price
  //       assertLe(takerTick.priceFromTick_e18(), (takerGives + 1) * 1e18 / takerWants);
  //       // TODO: Hopefully this is removed by changing targets to tick,volume - otherwise, try stabilizing test without this assume(false).
  //       // bail out as price is too low
  //       vm.assume(false);
  //     }
  //     assertLe(
  //       takerPriceE18,
  //       Tick.wrap(logPrice + 1).priceFromTick_e18(),
  //       "TakerGives should not overestimate too much"
  //     );
  //   }

  //   // Tick takerTick = Tick.wrap(logPrice)*10_000/(pc*10_000));
  //   // takerWants = random
  //   // takerGives =
  //   // if you want to snipe offer (tick,og):
  //   // - goal is to give (tw,tg) such that tick.ow(og)*tw <= og*tg
  //   // - i don't want to do tick compare for now because how do I do tick compare for market order?
  //   // - i woud like takerGives=0 OK (and takerWants=0 ok too?)
  //   // - if I take tw as given and apply the tick, I get tg=tick.ow(tw), which... will work?

  //   deal($(quote), address(this), type(uint).max);
  //   deal($(base), address(mkr), type(uint).max);
  //   mkr.approveMgv(base, type(uint).max);
  //   quote.approve($(mgv), type(uint).max);

  //   (uint successes, uint takerGot,,,) =
  //     testMgv.snipesInTest(olKey, wrap_dynamic([ofr, takerWants, takerGives, 100_000]), true);
  //   assertEq(successes, 1, "order should succeed");
  //   assertEq(takerGot, takerWants, "wrong takerGot");
  //   // Taker does not give all it has since it overestimates price - assertEq(takerGave, takerGives, "wrong takerGave");
  // }

  function test_maker_revert_is_logged() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mkr.expect("mgv/makerRevert");
    mkr.shouldRevert(true);
    quote.approve($(mgv), 1 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 1 ether, 1 ether, "mgv/makerRevert");
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertFalse(mkr.makerPosthookWasCalled(ofr), "ofr posthook must not be called or test is void");
  }

  function test_detect_low_gas() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    // Change gasbase so that gas limit checks does not prevent execution attempt
    mgv.setGasbase(olKey, 1);
    quote.approve($(mgv), 100 ether);

    vm.expectRevert("mgv/notEnoughGasForMakerTrade");
    mgv.marketOrderByLogPrice{gas: 130000}(olKey, logPrice, 1 ether, true);
  }

  /* Note as for jan 5 2020: by locally pushing the block gas limit to 38M, you can go up to 162 levels of recursion before hitting "revert for an unknown reason" -- I'm assuming that's the stack limit. */
  function test_recursion_depth_is_acceptable() public {
    for (uint i = 0; i < 50; i++) {
      mkr.newOfferByVolume(0.001 ether, 0.001 ether, 50_000, i);
    }
    quote.approve($(mgv), 10 ether);
    // 6/1/20 : ~50k/offer with optims
    //uint g = gasleft();
    //console.log("gas used per offer: %s",(g-gasleft())/50);
  }

  function test_partial_fill() public {
    quote.approve($(mgv), 1 ether);
    uint ofr1 = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 1);
    mkr.expect("mgv/tradeSuccess");
    (uint takerGot,,,) = mgv.marketOrderByVolume(olKey, 0.15 ether, 0.15 ether, true);
    assertEq(takerGot, 0.15 ether, "Incorrect declared partial fill amount");
    assertEq(base.balanceOf($(this)), 0.15 ether, "incorrect partial fill");
    assertTrue(mkr.makerPosthookWasCalled(ofr1), "ofr1 posthook must be called or test is void");
    assertTrue(mkr.makerPosthookWasCalled(ofr2), "ofr2 posthook must be called or test is void");
  }

  // ! unreliable test, depends on gas use
  function test_market_order_stops_for_high_price() public {
    quote.approve($(mgv), 1 ether);
    uint offerCount = 10;
    uint offersExpectedTaken = 2;
    uint[] memory ofrs = new uint[](offerCount);
    for (uint i = 1; i <= offerCount; i++) {
      ofrs[i - 1] = mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 100_000, i - 1);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.1 ether;
    uint takerGives = 2 * takerWants;
    mgv.marketOrderByVolume{gas: 700_000}(olKey, takerWants, takerGives, true);
    for (uint i = 0; i < offersExpectedTaken; i++) {
      assertTrue(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must be called or test is void");
    }
    for (uint i = offersExpectedTaken; i < offerCount; i++) {
      assertFalse(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must not be called or test is void");
    }
  }

  // ! unreliable test, depends on gas use
  function test_market_order_stops_for_filled_mid_offer() public {
    quote.approve($(mgv), 1 ether);
    uint offerCount = 10;
    uint offersExpectedTaken = 2;
    uint[] memory ofrs = new uint[](offerCount);
    for (uint i = 1; i <= offerCount; i++) {
      ofrs[i - 1] = mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 100_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.05 ether;
    uint takerGives = 2 * takerWants;
    mgv.marketOrderByVolume{gas: 700_000}(olKey, takerWants, takerGives, true);
    for (uint i = 0; i < offersExpectedTaken; i++) {
      assertTrue(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must be called or test is void");
    }
    for (uint i = offersExpectedTaken; i < offerCount; i++) {
      assertFalse(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must not be called or test is void");
    }
  }

  function test_market_order_stops_for_filled_after_offer() public {
    quote.approve($(mgv), 1 ether);
    uint offerCount = 10;
    uint offersExpectedTaken = 1;
    uint[] memory ofrs = new uint[](offerCount);
    for (uint i = 1; i <= offerCount; i++) {
      ofrs[i - 1] = mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 100_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether;
    uint takerGives = 2 * takerWants;
    mgv.marketOrderByVolume{gas: 450_000}(olKey, takerWants, takerGives, true);
    for (uint i = 0; i < offersExpectedTaken; i++) {
      assertTrue(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must be called or test is void");
    }
    for (uint i = offersExpectedTaken; i < offerCount; i++) {
      assertFalse(mkr.makerPosthookWasCalled(ofrs[i]), "ofr posthook must not be called or test is void");
    }
  }

  function test_takerWants_wider_than_160_bits_fails_marketOrder() public {
    vm.expectRevert("mgv/mOrder/takerWants/160bits");
    mgv.marketOrderByVolume(olKey, 2 ** 160, 1, true);
  }

  function test_clean_with_0_wants_ejects_offer() public {
    quote.approve($(mgv), 1 ether);
    uint mkrBal = base.balanceOf(address(mkr));
    uint ofr = failmkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    int offerLogPrice = mgv.offers(olKey, ofr).logPrice();

    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, offerLogPrice, 100_000, 0)), $(this));
    assertTrue(successes == 1, "clean should succeed");
    assertTrue(failmkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(mgv.best(olKey), 0, "offer should be gone");
    assertEq(base.balanceOf(address(mkr)), mkrBal, "mkr balance should not change");
  }

  function test_unsafe_gas_left_fails_order() public {
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    mgv.setGasbase(olKey, 1);
    int logPrice = mgv.offers(olKey, ofr).logPrice();

    vm.expectRevert("mgv/notEnoughGasForMakerTrade");
    mgv.marketOrderByLogPrice{gas: 145_000}(olKey, logPrice, 1 ether, true);
  }

  function test_unsafe_gas_left_fails_posthook() public {
    mgv.setGasbase(olKey, 1);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();

    vm.expectRevert("mgv/notEnoughGasForMakerPosthook");
    mgv.marketOrderByLogPrice{gas: 280_000}(olKey, logPrice, 1 ether, true);
  }

  // FIXME Make a token that goes out of gas on transfer to taker
  // So we don't have to find exact gas values here
  // function test_unsafe_gas_left_fails_to_pay_taker() public {
  //   mgv.setGasbase(olKey, 1);
  //   quote.approve($(mgv), 1 ether);
  //   uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 220_000, 0);
  //   Tick offerTick = mgv.offers(olKey,ofr).tick();
  //   vm.expectRevert("mgv/MgvFailToPayTaker");
  //   testMgv.snipesInTest{gas: 240_000}($(mgv), olKey, wrap_dynamic([ofr, logPrice, 1 ether, 220_000]), true);
  // }

  function test_marketOrder_on_empty_book_does_not_revert() public {
    mgv.marketOrderByVolume(olKey, 1 ether, 1 ether, true);
  }

  function test_marketOrder_on_empty_book_does_not_leave_lock_on() public {
    mgv.marketOrderByVolume(olKey, 1 ether, 1 ether, true);
    assertTrue(!mgv.locked(olKey), "mgv should not be locked after marketOrder on empty OB");
  }

  function test_takerWants_is_zero_succeeds() public {
    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 0, 1 ether, true);
    assertEq(got, 0, "Taker got too much");
    assertEq(gave, 0 ether, "Taker gave too much");
  }

  function test_takerGives_is_zero_succeeds() public {
    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 1 ether, 0, true);
    assertEq(got, 0, "Taker got too much");
    assertEq(gave, 0 ether, "Taker gave too much");
  }

  function test_failing_offer_volume_does_not_count_toward_filled_volume() public {
    quote.approve($(mgv), 1 ether);
    uint failing_ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    (uint got,,,) = mgv.marketOrderByVolume(olKey, 1 ether, 0, true);
    assertTrue(failmkr.makerPosthookWasCalled(failing_ofr), "failing_ofr posthook must be called or test is void");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(got, 1 ether, "should have gotten 1 ether");
  }

  // function test_reverting_monitor_on_notify() public {
  //   BadMonitor badMonitor = new BadMonitor({revertNotify:true,revertRead:false});
  //   mgv.setMonitor(badMonitor);
  //   mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
  //   quote.approve($(mgv), 2 ether);
  //   (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 1 ether, 1 ether, true);

  /* When Mangrove gets a revert from `flashloan` that doesn't match known revert
   * cases, it returns `mgv/swapError`. This can happen if the flashloan runs out
   * of gas, but should never happen in another case. I (adhusson) did not manage
   * to trigger the 'flash loan is OOG' condition because flashloan itself uses
   * very little gas. If you make it OOG, then its caller will OOG too before
   * reaching the `revert("mgv/swapError")` statement. To trigger that error, I
   * make a BadMangrove contract with a misbehaving `flashloan` function. */
  function test_unreachable_swapError() public {
    BadMangrove badMgv = new BadMangrove({
      governance: $(this),
      gasprice: 40,
      gasmax: 2_000_000
    });
    vm.label($(badMgv), "Bad Mangrove");
    badMgv.activate(olKey, 0, 0, 0);

    TestMaker mkr2 = new TestMaker(badMgv,olKey);
    badMgv.fund{value: 10 ether}($(mkr2));
    mkr2.newOfferByVolume(1 ether, 1 ether, 1, 0);
    vm.expectRevert("mgv/swapError");
    badMgv.marketOrderByVolume{gas: 150000}(olKey, 1 ether, 1 ether, true);
  }

  /* # Clean tests */
  /* Clean parameter validation */
  function test_gives_tick_outside_range_fails_clean() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 1 << 23, 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_gives_volume_above_96bits_fails_clean() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 0, 1 << 96)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  // FIXME implement a test that checks a gives+price too high results in an error (should p

  /* Clean offer state&match validation */
  function test_clean_on_nonexistent_offer_fails() public {
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(1, 0, 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_clean_non_live_offer_fails() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    failmkr.retractOffer(ofr);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == 0, "clean must not have changed the book");
  }

  function test_cleaning_with_exact_offer_details_succeeds() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_giving_smaller_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, -1, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_bigger_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 1, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_smaller_gasreq_to_clean_fails() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 99_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_bigger_gasreq_to_clean_succeeds() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_001, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  /* Clean - offer execution */
  function test_cleaning_non_failing_offer_fails() public {
    int logPrice = 0;
    uint ofr = mkr.newOfferByLogPrice(logPrice, 1 ether, 100_000);

    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 0 ether);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), ofr, $(this), 0 ether, LogPriceLib.inboundFromOutbound(logPrice, 0 ether));

    (uint successes,) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_cleaning_failing_offer_transfers_bounty() public {
    uint balanceBefore = $(this).balance;
    int logPrice = 0;
    uint ofr = failmkr.newOfferByLogPrice(logPrice, 1 ether, 100_000);

    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 0 ether, 0 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );

    vm.expectEmit(true, true, true, false, $(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, /*penalty*/ 0);

    (, uint bounty) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertTrue(bounty > 0, "cleaning should have yielded a bounty");
    uint balanceAfter = $(this).balance;
    assertEq(balanceBefore + bounty, balanceAfter, "the bounty was not transfered to the cleaner");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_clean_multiple_failing_offers() public {
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    uint ofr2 = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets =
      wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0), MgvLib.CleanTarget(ofr2, 0, 100_000, 0));

    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 0 ether, 0 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr2, $(this), 0 ether, 0 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );

    vm.expectEmit(true, true, true, false, $(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, /*penalty1 + penalty2*/ 0);

    (uint successes, uint bounty) = mgv.cleanByImpersonation(olKey, targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "both offers should have been cleaned");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_cleans_failing_offers_despite_one_not_failing() public {
    deal($(quote), $(this), 10 ether);
    uint ofr = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);
    uint ofr2 = mkr.newOfferByLogPrice(0, 1 ether, 100_000);
    uint ofr3 = failmkr.newOfferByLogPrice(0, 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets = wrap_dynamic(
      MgvLib.CleanTarget(ofr, 0, 100_000, 0),
      MgvLib.CleanTarget(ofr2, 0, 100_000, 0),
      MgvLib.CleanTarget(ofr3, 0, 100_000, 0)
    );

    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(this), 0 ether, 0 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0 ether);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), ofr2, $(this), 0 ether, 0 ether);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr3, $(this), 0 ether, 0 ether, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );

    vm.expectEmit(true, true, true, false, $(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, /*penalty1 + penalty3*/ 0);

    (uint successes, uint bounty) = mgv.cleanByImpersonation(olKey, targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "cleaning should succeed for all but one offer");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
    assertTrue(mgv.best(olKey) == ofr2, "clean must have left ofr2 in the book");
  }

  function test_cleaning_by_impersonation_succeeds_and_does_not_transfer_funds() public {
    uint ofr = failNonZeroMkr.newOfferByLogPrice(0, 1 ether, 100_000);
    // $this cannot clean with taker because of lack of funds/approval
    (, uint bounty) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(this));
    assertEq(bounty, 0, "cleaning should have failed");

    uint balanceNativeBefore = $(this).balance;
    uint balanceBaseBefore = base.balanceOf($(this));
    uint balanceQuoteBefore = quote.balanceOf($(this));

    // Create another taker that has the needed funds and have approved Mangrove
    TestTaker otherTkr = setupTaker(olKey, "otherTkr[$(A),$(B)]");
    deal($(quote), $(otherTkr), 10 ether);
    otherTkr.approveMgv(quote, 1 ether);
    uint otherTkrBalanceNativeBefore = $(otherTkr).balance;
    uint otherTkrBalanceBaseBefore = base.balanceOf($(otherTkr));
    uint otherTkrBalanceQuoteBefore = quote.balanceOf($(otherTkr));

    // Clean by impersonating the other taker
    expectFrom($(mgv));
    emit OrderStart();

    expectFrom($(quote));
    emit Transfer($(otherTkr), $(mgv), 1);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failNonZeroMkr), 1);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), ofr, $(otherTkr), 1, 1, "mgv/makerRevert");
    //TODO: when events can be checked instead of expected, take given penalty instead of ignoring it
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failNonZeroMkr), 0 /*mkr_provision - penalty*/ );

    vm.expectEmit(true, true, true, false, $(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0 ether, 0 ether, 0, /*penalty*/ 0);

    (, bounty) = mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(otherTkr));
    assertTrue(bounty > 0, "cleaning should have yielded a bounty");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");

    assertEq(balanceNativeBefore + bounty, $(this).balance, "the bounty was not transfered to the cleaner");
    assertEq(balanceBaseBefore, base.balanceOf($(this)), "taker's base balance should not change");
    assertEq(balanceQuoteBefore, quote.balanceOf($(this)), "taker's quote balance should not change");

    assertEq(otherTkrBalanceNativeBefore, $(otherTkr).balance, "other taker's native balance should not have changed");
    assertEq(otherTkrBalanceBaseBefore, base.balanceOf($(otherTkr)), "other taker's base balance should not change");
    assertEq(otherTkrBalanceQuoteBefore, quote.balanceOf($(otherTkr)), "other taker's quote balance should not change");
  }

  function test_unconsumed_tick_leaves_correct_leaf_start_at_tick_leave_one_only(
    int24 _tick,
    bool crossTick,
    bool leaveOneOnly
  ) public {
    quote.approve($(mgv), 10_000 ether);
    _tick = int24(bound(_tick, -100, 100));
    int24 _firstPostedTick = crossTick ? _tick - 1 : _tick;
    mkr.newOfferByLogPrice(_firstPostedTick, 1 ether, 100_000);
    mkr.newOfferByLogPrice(_tick, 1 ether, 100_000);
    uint ofr3 = mkr.newOfferByLogPrice(_tick, 1 ether, 100_000);
    uint ofr4 = mkr.newOfferByLogPrice(_tick, 1 ether, 100_000);
    uint volume = leaveOneOnly ? 3 ether : 2 ether;
    mgv.marketOrderByLogPrice(olKey, _tick, volume, true);

    Tick tick = Tick.wrap(_tick);

    uint bestId = leaveOneOnly ? ofr4 : ofr3;
    MgvStructs.OfferPacked best = mgv.offers(olKey, bestId);
    Leaf leaf = mgv.leafs(olKey, best.tick(olKey.tickScale).leafIndex());
    assertEq(leaf.firstOfIndex(tick.posInLeaf()), bestId, "wrong first of tick");
    assertEq(leaf.lastOfIndex(tick.posInLeaf()), ofr4, "wrong last of tick");
    (, MgvStructs.LocalPacked local) = mgv.config(olKey);
    assertEq(local.tickPosInLeaf(), tick.posInLeaf(), "wrong local.tickPosInleaf");
    assertEq(best.prev(), 0, "best.prev should be 0");
    Leaf emptyLeaf = leaf.setTickFirst(tick, 0).setTickLast(tick, 0);
    assertTrue(emptyLeaf.isEmpty(), "leaf should not have other tick used");
  }
}

contract BadMangrove is AbstractMangrove {
  constructor(address governance, uint gasprice, uint gasmax)
    AbstractMangrove(governance, gasprice, gasmax, "BadMangrove")
  {}

  function executeEnd(MultiOrder memory, MgvLib.SingleOrder memory) internal override {}

  function beforePosthook(MgvLib.SingleOrder memory) internal override {}

  function flashloan(MgvLib.SingleOrder calldata, address) external pure override returns (uint, bytes32) {
    revert("badRevert");
  }
}
