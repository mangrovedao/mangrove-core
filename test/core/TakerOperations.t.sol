// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import "@mgv/lib/core/Constants.sol";
import "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/lib/core/TickLib.sol";

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
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    quote.blacklists($(this));

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  function test_execute_reverts_if_taker_is_blacklisted_for_base() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    base.blacklists($(this));

    vm.expectRevert("mgv/MgvFailToPayTaker");
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  // The purpose of this test is to make sure inbound volumes are rounded up when partially
  // taking an offer i.e. you can't have the taker pay 0 if the maker sends > 0 to the taker.
  // The test sets this up with a price slightly below 1/2, gives=10, and then taker asks for 1. So it should give < 1/2. If maker balance does not increase, it was drained.
  function test_taker_cannot_drain_maker() public {
    mgv.setDensity96X32(olKey, 0);
    quote.approve($(mgv), 1 ether);
    Tick tick = Tick.wrap(-7000); // price slightly < 1/2
    mkr.newOfferByTick(tick, 10, 100_000, 0);
    uint oldBal = quote.balanceOf($(this));
    mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), 1, true);
    uint newBal = quote.balanceOf($(this));
    assertGt(oldBal, newBal, "oldBal should be strictly higher");
  }

  function test_execute_fillWants() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, Tick.wrap(Tick.unwrap(tick) + 1), 0.5 ether, true);
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
    Tick tick = TickLib.tickFromRatio(1, 0);
    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, tick, 0.1 ether, true);
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
    Tick tick = TickLib.tickFromRatio(1, 0);
    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, tick, 0.1 ether, false);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertApproxEqRel(got, 1 ether, relError(10), "Wrong got value");
    assertApproxEqRel(gave, 0.01 ether, relError(10), "Wrong gave value");
    assertTrue(!mgv.offers(olKey, ofr).isLive(), "Offer should not be in the book");
  }

  function test_execute_fillGives() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    Tick tick = TickLib.tickFromRatio(1, 0);
    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, tick, 1 ether, false);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(got, 1 ether, "Taker did not get correct amount");
    assertEq(gave, 1 ether, "Taker did not get correct amount");
  }

  /* # Market order tests */

  event Transfer(address indexed from, address indexed to, uint value);

  function test_mo_fillWants() public {
    uint ofr1 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick1 = mgv.offers(olKey, ofr1).tick();
    Tick offerTick2 = mgv.offers(olKey, ofr2).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    Tick maxTick = TickLib.tickFromVolumes(1.9 ether, 1.1 ether);

    expectFrom($(mgv));
    emit OrderStart(olKey.hash(), $(this), maxTick, 1.1 ether, true);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 1 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 1 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 1 ether);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0.1 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0.1 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 0.1 ether);

    expectFrom($(base));
    emit Transfer($(mgv), $(this), 1.1 ether);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), $(this), ofr2, 0.1 ether, offerTick2.inboundFromOutbound(0.1 ether));
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), $(this), ofr1, 1 ether, offerTick1.inboundFromOutbound(1 ether));
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0);

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
    Tick tick = mgv.offers(olKey, ofr).tick();
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    quote.approve($(mgv), 1 ether);

    expectFrom($(mgv));
    emit OrderStart(olKey.hash(), $(this), tick, 0 ether, true);
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0);

    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, tick, 0, true);

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
    Tick tick = mgv.offers(olKey, ofr).tick();
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    expectFrom($(mgv));
    emit OrderStart(olKey.hash(), $(this), tick, 0 ether, false);
    expectFrom($(mgv));
    emit OrderComplete(olKey.hash(), $(this), 0);

    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, tick, 0 ether, false);
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
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit Credit($(refusemkr), 81680000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 1 ether, 1 ether, 11278320000000, "mgv/makerTransferFail");
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, tick, 100_000, 1 ether)), $(this));
    assertEq(successes, 1, "clean should succeed");
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(refusemkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_reverts_on_penalty_triggers_revert() public {
    uint ofr = refusemkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    refuseReceive = true;
    quote.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/sendPenaltyReverted");
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_base() public {
    // uint mkr_provision = reader.getProvision(olKey, 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook

    base.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit Credit($(mkr), 1126680000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 1 ether, 1 ether, 10233320000000, "mgv/makerTransferFail");
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByTick(olKey, tick, 1 ether, true);
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
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/makerReceiveFail"); // status visible in the posthook

    quote.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit Credit($(mkr), 2654520000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 1 ether, 1 ether, 8705480000000, "mgv/makerReceiveFail");
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_collects_failing_offer() public {
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    uint beforeWei = $(this).balance;

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertTrue(takerGot == takerGave && takerGave == 0, "Transaction data should be 0");
    assertTrue($(this).balance > beforeWei, "Taker was not compensated");
    assertTrue(failmkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_taker_reimbursed_if_maker_reverts() public {
    // uint mkr_provision = reader.getProvision(olKey, 50_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit Credit($(failmkr), 1422160000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 1 ether, 1 ether, 9937840000000, "mgv/makerRevert");
    (uint takerGot, uint takerGave,,) = mgv.marketOrderByTick(olKey, tick, 1 ether, true);
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
    Tick tick = mgv.offers(olKey, ofr).tick();
    quote.approve($(mgv), 1 ether);
    uint shouldGet = reader.minusFee(olKey, 1 ether);
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertEq(base.balanceOf($(this)) - balTaker, shouldGet, "Incorrect delivered amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr execute must be called or test is void");
  }

  function test_taker_hasnt_approved_base_succeeds_order_wo_fee() public {
    uint balTaker = base.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    quote.approve($(mgv), 1 ether);
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertEq(base.balanceOf($(this)) - balTaker, 1 ether, "Incorrect delivered amount");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr execute must be called or test is void");
  }

  function test_taker_hasnt_approved_quote_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    base.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
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

  function test_fillGives_at_1_wants_works() public {
    uint wants = 0;
    uint ofr = mkr.newOfferByVolume(wants, 2 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByTick(olKey, tick, 10, false);
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(takerGave, 1, "Incorrect declared delivered amount (maker)");
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
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/tradeSuccess");

    quote.approve($(mgv), 100 ether);
    base.approve($(mgv), 1 ether); // not necessary since no fee

    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByTick(olKey, tick, 2 ether, true);
  }

  function test_maker_has_not_enough_base_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/makerTransferFail");
    // getting rid of base tokens
    //mkr.transferToken(base,$(this),5 ether);
    quote.approve($(mgv), 0.5 ether);
    Offer offer = mgv.offers(olKey, ofr);

    uint takerWants = 50 ether;
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferFail(
      olKey.hash(),
      $(this),
      ofr,
      takerWants,
      offer.tick().inboundFromOutboundUp(takerWants),
      /*penalty*/
      0,
      "mgv/makerTransferFail"
    );
    (,, uint bounty,) = mgv.marketOrderByTick(olKey, tick, 50 ether, true);
    assertTrue(bounty > 0, "offer should fail");
    assertTrue(mkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
  }

  function test_maker_revert_is_logged() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    mkr.expect("mgv/makerRevert");
    mkr.shouldRevert(true);
    quote.approve($(mgv), 1 ether);
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferFailWithPosthookData(olKey.hash(), $(this), ofr, 1 ether, 1 ether, /*penalty*/ 0, "mgv/makerRevert", "");
    mgv.marketOrderByTick(olKey, tick, 1 ether, true);
    assertFalse(mkr.makerPosthookWasCalled(ofr), "ofr posthook must not be called or test is void");
  }

  function test_detect_low_gas() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();
    // Change gasbase so that gas limit checks does not prevent execution attempt
    mgv.setGasbase(olKey, 1);
    quote.approve($(mgv), 100 ether);

    vm.expectRevert("mgv/notEnoughGasForMakerTrade");
    mgv.marketOrderByTick{gas: 130000}(olKey, tick, 1 ether, true);
  }

  /* Note as of jan 5 2021: by locally pushing the block gas limit to 38M, you can go up to 162 levels of recursion before hitting "revert for an unknown reason" -- I'm assuming that's the stack limit. */
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
  function test_market_order_stops_for_high_ratio() public {
    quote.approve($(mgv), 1 ether);
    uint offerCount = 10;
    uint offersExpectedTaken = 2;
    uint[] memory ofrs = new uint[](offerCount);
    for (uint i = 1; i <= offerCount; i++) {
      ofrs[i - 1] = mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 100_000, i - 1);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right ratio
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
    // first two offers are at right ratio
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
    // first two offers are at right ratio
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

  // none should revert
  function test_marketOrderByVolume_takerGives_extrema_volumes_ok() public {
    mgv.marketOrderByVolume(olKey, MAX_SAFE_VOLUME, 1, true);
    mgv.marketOrderByVolume(olKey, MAX_SAFE_VOLUME, 1, false);
    mgv.marketOrderByVolume(olKey, 1, MAX_SAFE_VOLUME, true);
    mgv.marketOrderByVolume(olKey, 1, MAX_SAFE_VOLUME, false);
    mgv.marketOrderForByVolume(olKey, MAX_SAFE_VOLUME, 1, true, address(this));
    mgv.marketOrderForByVolume(olKey, MAX_SAFE_VOLUME, 1, false, address(this));
    mgv.marketOrderForByVolume(olKey, 1, MAX_SAFE_VOLUME, true, address(this));
    mgv.marketOrderForByVolume(olKey, 1, MAX_SAFE_VOLUME, false, address(this));
  }

  function test_marketOrderByVolume_takerGives_extrema_ko() public {
    vm.expectRevert("mgv/ratioFromVol/inbound/tooBig");
    mgv.marketOrderByVolume(olKey, 0, MAX_SAFE_VOLUME + 1, true);

    vm.expectRevert("mgv/ratioFromVol/outbound/tooBig");
    mgv.marketOrderByVolume(olKey, MAX_SAFE_VOLUME + 1, 0, true);

    vm.expectRevert("mgv/ratioFromVol/inbound/tooBig");
    mgv.marketOrderByVolume(olKey, 0, MAX_SAFE_VOLUME + 1, false);

    vm.expectRevert("mgv/ratioFromVol/outbound/tooBig");
    mgv.marketOrderByVolume(olKey, MAX_SAFE_VOLUME + 1, 0, false);

    vm.expectRevert("mgv/ratioFromVol/inbound/tooBig");
    mgv.marketOrderForByVolume(olKey, 0, MAX_SAFE_VOLUME + 1, true, address(0));

    vm.expectRevert("mgv/ratioFromVol/outbound/tooBig");
    mgv.marketOrderForByVolume(olKey, MAX_SAFE_VOLUME + 1, 0, true, address(0));

    vm.expectRevert("mgv/ratioFromVol/inbound/tooBig");
    mgv.marketOrderForByVolume(olKey, 0, MAX_SAFE_VOLUME + 1, false, address(0));

    vm.expectRevert("mgv/ratioFromVol/outbound/tooBig");
    mgv.marketOrderForByVolume(olKey, MAX_SAFE_VOLUME + 1, 0, false, address(0));
  }

  function test_marketOrderByTick_extrema_volume_ok() public {
    mgv.marketOrderByTick(olKey, Tick.wrap(0), MAX_SAFE_VOLUME, true);
  }

  function test_marketOrderByTick_extrema_volume_ko() public {
    vm.expectRevert("mgv/mOrder/fillVolume/tooBig");
    mgv.marketOrderByTick(olKey, Tick.wrap(0), MAX_SAFE_VOLUME + 1, true);
  }

  function test_marketOrderByTick_extrema_ko() public {
    vm.expectRevert("mgv/mOrder/tick/outOfRange");
    mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK + 1), 100, true);

    vm.expectRevert("mgv/mOrder/tick/outOfRange");
    mgv.marketOrderByTick(olKey, Tick.wrap(MIN_TICK - 1), 100, true);

    vm.expectRevert("mgv/mOrder/tick/outOfRange");
    mgv.marketOrderForByTick(olKey, Tick.wrap(MAX_TICK + 1), 100, true, address(0));

    vm.expectRevert("mgv/mOrder/tick/outOfRange");
    mgv.marketOrderForByTick(olKey, Tick.wrap(MIN_TICK - 1), 100, true, address(0));
  }

  function test_clean_with_0_wants_ejects_offer() public {
    quote.approve($(mgv), 1 ether);
    uint mkrBal = base.balanceOf(address(mkr));
    uint ofr = failmkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    Tick offerTick = mgv.offers(olKey, ofr).tick();

    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, offerTick, 100_000, 0)), $(this));
    assertTrue(successes == 1, "clean should succeed");
    assertTrue(failmkr.makerPosthookWasCalled(ofr), "ofr posthook must be called or test is void");
    assertEq(mgv.best(olKey), 0, "offer should be gone");
    assertEq(base.balanceOf(address(mkr)), mkrBal, "mkr balance should not change");
  }

  function test_unsafe_gas_left_fails_order() public {
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    mgv.setGasbase(olKey, 1);
    Tick tick = mgv.offers(olKey, ofr).tick();

    vm.expectRevert("mgv/notEnoughGasForMakerTrade");
    mgv.marketOrderByTick{gas: 145_000}(olKey, tick, 1 ether, true);
  }

  function test_unsafe_gas_left_fails_posthook() public {
    mgv.setGasbase(olKey, 1);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    Tick tick = mgv.offers(olKey, ofr).tick();

    vm.expectRevert("mgv/notEnoughGasForMakerPosthook");
    mgv.marketOrderByTick{gas: 291_000}(olKey, tick, 1 ether, true);
  }

  // Check conditions under which MgvFailToPayTaker can occur
  // This happens when:
  // - outbound token goes OOG / reverts
  // - Mangrove still has enough gas to revert
  // Here we test the OOG case with a special token "OutOfGasToken"
  function test_unsafe_gas_left_fails_to_pay_taker() public {
    OutOfGasToken oogtt = new OutOfGasToken(address(this),"OutOfGasToken","OOGTT",18);
    oogtt.setTaker(address(this));
    deal($(oogtt), address(mkr), 100 ether);
    mkr.approveMgv(oogtt, type(uint).max);

    IERC20(olKey.inbound_tkn).approve($(mgv), type(uint).max);

    olKey.outbound_tkn = address(oogtt);
    mgv.activate(olKey, 0, 0, 1);

    Tick tick = Tick.wrap(0);
    mkr.newOfferByTick(olKey, tick, 1 ether, 220_000, 0);
    vm.expectRevert("mgv/MgvFailToPayTaker");

    // Give a normal gas amount (gas available in tests is so high the gas-waste of OutOfGasToken would run for ages)
    mgv.marketOrderByTick{gas: 400_000}(olKey, tick, 1 ether, true);
  }

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
    (uint got,,,) = mgv.marketOrderByVolume(olKey, 1 ether, 1 ether, true);
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
    IMangrove badMgv = IMangrove(
      payable(
        new BadMangrove({
        governance: $(this),
        gasprice: 40,
        gasmax: 2_000_000
        })
      )
    );
    vm.label($(badMgv), "Bad Mangrove");
    badMgv.activate(olKey, 0, 0, 0);

    TestMaker mkr2 = new TestMaker(IMangrove($(badMgv)),olKey);
    badMgv.fund{value: 10 ether}($(mkr2));
    mkr2.newOfferByVolume(1 ether, 1 ether, 1, 0);
    vm.expectRevert("mgv/swapError");
    badMgv.marketOrderByVolume{gas: 150000}(olKey, 1 ether, 1 ether, true);
  }

  /* # Clean tests */
  /* Clean parameter validation */
  function test_gives_tick_outside_range_fails_clean() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(1 << 23), 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_gives_volume_tooBig_fails_clean() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) = mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 0, MAX_SAFE_VOLUME + 1)), $(this)
    );
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  /* Clean offer state&match validation */
  function test_clean_on_nonexistent_offer_fails() public {
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(1, Tick.wrap(0), 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_clean_non_live_offer_fails() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    failmkr.retractOffer(ofr);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == 0, "clean must not have changed the book");
  }

  function test_cleaning_with_exact_offer_details_succeeds() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_giving_smaller_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(-1), 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_bigger_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(1), 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_smaller_gasreq_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 99_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_giving_bigger_gasreq_to_clean_succeeds() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_001, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  /* Clean - offer execution */
  function test_cleaning_non_failing_offer_fails() public {
    Tick tick = Tick.wrap(0);
    uint ofr = mkr.newOfferByTick(tick, 1 ether, 100_000);

    expectFrom($(mgv));
    emit CleanStart(olKey.hash(), $(this), 1);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0 ether);
    expectFrom($(base));
    emit Transfer($(mkr), $(mgv), 0 ether);

    (uint successes,) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
    assertTrue(mgv.best(olKey) == ofr, "clean must have left ofr in the book");
  }

  function test_cleaning_failing_offer_transfers_bounty() public {
    uint balanceBefore = $(this).balance;
    Tick tick = Tick.wrap(0);
    uint ofr = failmkr.newOfferByTick(tick, 1 ether, 100_000);

    expectFrom($(mgv));
    emit CleanStart(olKey.hash(), $(this), 1);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit Credit($(failmkr), 1422160000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 0 ether, 0 ether, 9937840000000, "mgv/makerRevert");

    expectFrom($(mgv));
    emit CleanComplete();

    (, uint bounty) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 0)), $(this));
    assertTrue(bounty > 0, "cleaning should have yielded a bounty");
    uint balanceAfter = $(this).balance;
    assertEq(balanceBefore + bounty, balanceAfter, "the bounty was not transfered to the cleaner");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_clean_multiple_failing_offers() public {
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    uint ofr2 = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets = wrap_dynamic(
      MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 0), MgvLib.CleanTarget(ofr2, Tick.wrap(0), 100_000, 0)
    );

    expectFrom($(mgv));
    emit CleanStart(olKey.hash(), $(this), 2);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit Credit($(failmkr), 1422160000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 0 ether, 0 ether, 9937840000000, "mgv/makerRevert");

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    expectFrom($(mgv));
    emit Credit($(failmkr), 1902160000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr2, 0 ether, 0 ether, 9457840000000, "mgv/makerRevert");

    expectFrom($(mgv));
    emit CleanComplete();

    (uint successes, uint bounty) = mgv.cleanByImpersonation(olKey, targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "both offers should have been cleaned");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
    assertTrue(mgv.best(olKey) == 0, "clean must have emptied mgv");
  }

  function test_cleans_failing_offers_despite_one_not_failing() public {
    deal($(quote), $(this), 10 ether);
    uint ofr = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    uint ofr2 = mkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    uint ofr3 = failmkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets = wrap_dynamic(
      MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 0),
      MgvLib.CleanTarget(ofr2, Tick.wrap(0), 100_000, 0),
      MgvLib.CleanTarget(ofr3, Tick.wrap(0), 100_000, 0)
    );

    expectFrom($(mgv));
    emit CleanStart(olKey.hash(), $(this), 3);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr, 0 ether, 0 ether, /*penalty*/ 0, "mgv/makerRevert");

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(mkr), 0 ether);

    expectFrom($(quote));
    emit Transfer($(this), $(mgv), 0 ether);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failmkr), 0 ether);
    vm.expectEmit(true, true, true, false, $(mgv));
    emit Credit($(failmkr), 0 /*mkr_provision - penalty*/ );
    vm.expectEmit(true, true, true, false, $(mgv));
    emit OfferFail(olKey.hash(), $(this), ofr3, 0 ether, 0 ether, /*penalty*/ 0, "mgv/makerRevert");

    vm.expectEmit(true, true, true, false, $(mgv));
    emit CleanComplete();

    (uint successes, uint bounty) = mgv.cleanByImpersonation(olKey, targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "cleaning should succeed for all but one offer");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
    assertTrue(mgv.best(olKey) == ofr2, "clean must have left ofr2 in the book");
  }

  function test_cleaning_by_impersonation_succeeds_and_does_not_transfer_funds() public {
    uint ofr = failNonZeroMkr.newOfferByTick(Tick.wrap(0), 1 ether, 100_000);
    // $this cannot clean with taker because of lack of funds/approval
    (, uint bounty) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 1)), $(this));
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
    emit CleanStart(olKey.hash(), $(otherTkr), 1);

    expectFrom($(quote));
    emit Transfer($(otherTkr), $(mgv), 1);
    expectFrom($(quote));
    emit Transfer($(mgv), $(failNonZeroMkr), 1);
    expectFrom($(mgv));
    emit Credit($(failNonZeroMkr), 1411600000000);
    expectFrom($(mgv));
    emit OfferFail(olKey.hash(), $(otherTkr), ofr, 1, 1, 9948400000000, "mgv/makerRevert");
    expectFrom($(mgv));
    emit CleanComplete();

    (, bounty) =
      mgv.cleanByImpersonation(olKey, wrap_dynamic(MgvLib.CleanTarget(ofr, Tick.wrap(0), 100_000, 1)), $(otherTkr));
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
    Bin bin,
    bool crossBin,
    bool leaveOneOnly
  ) public {
    quote.approve($(mgv), 10_000 ether);
    bin = Bin.wrap(bound(Bin.unwrap(bin), -100, 100));
    Bin firstPostedBin = Bin.wrap(Bin.unwrap(bin) - (crossBin ? int(1) : int(0)));
    mkr.newOfferByTick(olKey.tick(firstPostedBin), 1 ether, 100_000);
    mkr.newOfferByTick(olKey.tick(bin), 1 ether, 100_000);
    uint ofr3 = mkr.newOfferByTick(olKey.tick(bin), 1 ether, 100_000);
    uint ofr4 = mkr.newOfferByTick(olKey.tick(bin), 1 ether, 100_000);
    uint volume = leaveOneOnly ? 3 ether : 2 ether;
    mgv.marketOrderByTick(olKey, olKey.tick(bin), volume, true);

    uint bestId = leaveOneOnly ? ofr4 : ofr3;
    Offer best = mgv.offers(olKey, bestId);
    Leaf leaf = mgv.leafs(olKey, best.bin(olKey.tickSpacing).leafIndex());
    assertEq(leaf.firstOfPos(bin.posInLeaf()), bestId, "wrong first of tick");
    assertEq(leaf.lastOfPos(bin.posInLeaf()), ofr4, "wrong last of tick");
    (, Local local) = mgv.config(olKey);
    assertEq(local.binPosInLeaf(), bin.posInLeaf(), "wrong local.binPosInLeaf");
    assertEq(best.prev(), 0, "best.prev should be 0");
    Leaf emptyLeaf = leaf.setBinFirst(bin, 0).setBinLast(bin, 0);
    assertTrue(emptyLeaf.isEmpty(), "leaf should not have other bin used");
  }

  function test_exact_market_order_uses_roundup_price() public {
    // forgefmt: disable-start
    mgv.setFee(olKey,0);
    quote.approve($(mgv),type(uint).max);

    uint amount = 4901713;// arbitrary amount
    Tick tick = Tick.wrap(13);

    assertTrue(
      tick.inboundFromOutbound(amount) != tick.inboundFromOutboundUp(amount),"rounding up should be distinguishable from not rounding up"
    );

    mkr.newOfferByTick(tick,amount,100_000,0);

    (,uint gave,,)= mgv.marketOrderByTick(olKey,Tick.wrap(MAX_TICK),amount,true);

    assertEq(
      gave,
      tick.inboundFromOutboundUp(amount),
      "got wrong amount"
    );
    // forgefmt: disable-end
  }

  function test_partial_fill_market_order_uses_roundup_price() public {
    // forgefmt: disable-start
    mgv.setFee(olKey,0);
    quote.approve($(mgv),type(uint).max);

    uint amount = 4901713;// arbitrary amount
    Tick tick = Tick.wrap(13);

    assertTrue(
      tick.inboundFromOutbound(amount) != tick.inboundFromOutboundUp(amount),
      "rounding up should be distinguishable from not rounding up"
    );

    uint ofrId = mkr.newOfferByTick(tick,amount+100,100_000,0);
    Offer ofr = mgv.offers(olKey,ofrId);

    assertGt(
      ofr.gives(), amount,
      "market order should partial fill"
    );

    (,uint gave,,)= mgv.marketOrderByTick(olKey,Tick.wrap(MAX_TICK),amount,true);

    assertEq(
      gave,
      tick.inboundFromOutboundUp(amount),
      "got wrong amount"
    );
    // forgefmt: disable-end
  }

  /* 
  An attempt to check for overflow when accumulating sor.takerGives into mor.totalGave.
  I have not found a way to actually trigger it by mutating state somewhere.
  This test just considers as many offers as possible that each have a maximal `wants` and makes sure the error will be about stack overflow, not uint overflow. 
  */
  function test_maximal_wants_is_ok() public {
    uint maxOfferWants = Tick.wrap(MAX_TICK).inboundFromOutboundUp(type(uint96).max);
    unchecked {
      uint recp = mgv.global().maxRecursionDepth() + 1;
      assertTrue(
        maxOfferWants * recp / recp == maxOfferWants,
        "mor.totalGave += sor.takerGives could overflow, check MgvOfferTaking"
      );
    }
  }

  function test_mo_with_extremely_high_offer_wants() public {
    mkr.provisionMgv(1 ether);
    mkr.approveMgv(base, type(uint).max);
    quote.approve($(mgv), type(uint).max);
    deal($(base), address(mkr), type(uint).max);
    deal($(quote), address(this), type(uint).max);

    mkr.newOfferByTick(Tick.wrap(MAX_TICK), MAX_SAFE_VOLUME, 100_000);
    mkr.newOfferByTick(Tick.wrap(MAX_TICK), MAX_SAFE_VOLUME, 100_000);
    (uint got, uint gave,,) = mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), MAX_SAFE_VOLUME, true);
    assertEq(got, MAX_SAFE_VOLUME);
    assertEq(gave, MAX_SAFE_VOLUME * MAX_RATIO_MANTISSA);
  }
}

contract BadMangrove is Mangrove {
  constructor(address governance, uint gasprice, uint gasmax) Mangrove(governance, gasprice, gasmax) {}

  function flashloan(MgvLib.SingleOrder calldata, address) external pure override returns (uint, bytes32) {
    revert("badRevert");
  }
}

// simulates what happens if the call to transfer tokens to the taker runs out of gas
// runs out of gas when transferring to taker
contract OutOfGasToken is TestToken {
  constructor(address admin, string memory name, string memory symbol, uint8 _decimals)
    TestToken(admin, name, symbol, _decimals)
  {}

  address taker;
  mapping(uint => bool) internal waste;

  function setTaker(address t) external {
    taker = t;
  }

  function transfer(address to, uint amount) public virtual override returns (bool ret) {
    if (to == taker) {
      uint i;
      while (++i > 0) {
        waste[i] = true;
      }
    } else {
      ret = super.transfer(to, amount);
    }
  }
}
