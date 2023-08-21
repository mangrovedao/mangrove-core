// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MAX_TICK, MIN_TICK} from "mgv_lib/TickLib.sol";

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

    mkr = setupMaker($(base), $(quote), "maker");
    refusemkr = setupMaker($(base), $(quote), "refusing mkr");
    refusemkr.shouldFail(true);
    failmkr = setupMaker($(base), $(quote), "reverting mkr");
    failmkr.shouldRevert(true);
    failNonZeroMkr = setupMaker($(base), $(quote), "reverting on non-zero mkr");
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

  function test_snipe_reverts_if_taker_is_blacklisted_for_quote() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    quote.blacklists($(this));

    vm.expectRevert("mgv/takerTransferFail");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  function test_snipe_reverts_if_taker_is_blacklisted_for_base() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    base.blacklists($(this));

    vm.expectRevert("mgv/MgvFailToPayTaker");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
  }

  function test_snipe_fails_if_price_has_changed() public {
    uint weiBalanceBefore = mgv.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick) - 1), 0.5 ether, 100_000]), false
    );
    assertTrue(successes == 0, "Snipe should fail");
    assertEq(weiBalanceBefore, mgv.balanceOf($(this)), "Taker should not take bounty");
    assertTrue((got == gave && gave == 0), "Taker should not give or take anything");
  }

  function test_taker_cannot_drain_maker() public {
    mgv.setDensityFixed($(base), $(quote), 0);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(9, 10, 100_000, 0);
    uint oldBal = quote.balanceOf($(this));
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(MAX_TICK), 1, 100_000]), true);
    uint newBal = quote.balanceOf($(this));
    assertGt(oldBal, newBal, "oldBal should be strictly higher");
  }

  function test_snipe_fillWants() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);
    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick) + 1), 0.5 ether, 100_000]), true
    );
    assertTrue(successes == 1, "Snipe should not fail");
    assertEq(got, 0.5 ether, "Taker did not get correct amount");
    assertEq(gave, 0.5 ether, "Taker did not give correct amount");
  }

  function test_multiple_snipes_fillWants() public {
    uint i;
    uint[] memory ofrs = new uint[](3);
    ofrs[i++] = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    ofrs[i++] = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    ofrs[i++] = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offersTick = mgv.offers($(base), $(quote), ofrs[0]).tick();

    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 3 ether);
    uint[4][] memory targets = new uint[4][](3);
    uint j;
    targets[j] = [ofrs[j], uint(Tick.unwrap(offersTick) + 2), 0.5 ether, 100_000];
    j++;
    targets[j] = [ofrs[j], uint(Tick.unwrap(offersTick)), 1 ether, 100_000];
    j++;
    targets[j] = [ofrs[j], uint(Tick.unwrap(offersTick) + 1), 0.8 ether, 100_000];

    expectFrom($(mgv));
    emit OrderStart();
    expectFrom($(mgv));
    emit OrderComplete($(base), $(quote), $(this), 2.3 ether, 2.3 ether, 0, 0);

    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest($(base), $(quote), targets, true);
    assertTrue(successes == 3, "Snipes should not fail");
    assertEq(got, 2.3 ether, "Taker did not get correct amount");
    assertEq(gave, 2.3 ether, "Taker did not give correct amount");
  }

  event Transfer(address indexed from, address indexed to, uint value);

  function test_snipe_fillWants_zero() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    expectFrom($(quote));
    emit Transfer($(this), address(mgv), 0);
    expectFrom($(quote));
    emit Transfer($(mgv), address(mkr), 0);

    (uint successes, uint got, uint gave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 0, 100_000]), true);
    assertTrue(successes == 1, "Snipe should not fail");
    assertEq(got, 0 ether, "Taker had too much");
    assertEq(gave, 0 ether, "Taker gave too much");
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer should not be in the book");
  }

  function test_snipe_free_offer_fillWants_respects_spec() public {
    uint ofr = mkr.newOfferByVolume(1, 1 ether, 100_000, 0);
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    /* Setting fillWants = true means we should not receive more than `wants`.
       Here we are asking for 0.1 eth to an offer that gives 1eth for ~nothing.
       We should still only receive 0.1 eth */
    Tick snipeTick = TickLib.tickFromPrice_e18(1 ether);
    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(snipeTick)), 0.1 ether, 100_000]), true
    );
    assertTrue(successes == 1, "Snipe should not fail");
    assertApproxEqRel(got, 0.1 ether, relError(10), "Wrong got value");
    assertApproxEqRel(gave, 1, relError(10), "Wrong gave value");
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer should not be in the book");
  }

  function test_snipe_free_offer_fillGives_respects_spec() public {
    uint ofr = mkr.newOfferByVolume(0.01 ether, 1 ether, 100_000, 0);
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    /* Setting fillWants = false means we should spend as little as possible to receive
       as much as possible.
       Here despite asking for .1eth the offer gives 1eth for ~0 so we should receive 1eth. */

    Tick snipeTick = TickLib.tickFromPrice_e18(1 ether);
    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(snipeTick)), 0.01 ether, 100_000]), false
    );
    assertTrue(successes == 1, "Snipe should not fail");
    assertApproxEqRel(got, 1 ether, relError(10), "Wrong got value");
    assertApproxEqRel(gave, 0.01 ether, relError(10), "Wrong gave value");
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer should not be in the book");
  }

  function test_snipe_fillGives_zero() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    (uint successes, uint got, uint gave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 0, 100_000]), false);
    assertTrue(successes == 1, "Snipe should not fail");
    assertEq(got, 0 ether, "Taker had too much");
    assertEq(gave, 0 ether, "Taker gave too much");
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer should not be in the book");
  }

  function test_snipe_fillGives() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 1 ether);

    Tick snipeTick = TickLib.tickFromPrice_e18(1 ether);
    (uint successes, uint got, uint gave,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(snipeTick)), 1 ether, 100_000]), false
    );
    assertTrue(successes == 1, "Snipe should not fail");
    assertEq(got, 1 ether, "Taker did not get correct amount");
    assertEq(gave, 1 ether, "Taker did not get correct amount");
  }

  function test_mo_fillWants() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 1.1 ether, 1.9 ether, true);
    assertEq(got, 1.1 ether, "Taker did not get correct amount");
    assertEq(gave, 1.1 ether, "Taker did not get correct amount");
  }

  function test_mo_newBest() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    quote.approve($(mgv), 2 ether);
    assertEq(pair.best(), ofr, "wrong best offer");
    mgv.marketOrderByVolume($(base), $(quote), 2 ether, 4 ether, true);
    assertEq(pair.best(), 0, "there should not be a best offer anymore");
  }

  function test_mo_fillGives() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 1.1 ether, 1.9 ether, false);
    assertEq(got, 1.9 ether, "Taker did not get correct amount");
    assertEq(gave, 1.9 ether, "Taker did not give correct amount");
  }

  function test_mo_fillGivesAll_no_approved_fails() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 2 ether);
    vm.expectRevert("mgv/takerTransferFail");
    mgv.marketOrderByVolume($(base), $(quote), 0 ether, 3 ether, false);
  }

  function test_mo_fillGivesAll_succeeds() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quote.approve($(mgv), 3 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 0 ether, 3 ether, false);
    assertEq(got, 3 ether, "Taker did not get correct amount");
    assertEq(gave, 3 ether, "Taker did not get correct amount");
  }

  function test_taker_reimbursed_if_maker_doesnt_pay() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = refusemkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail($(base), $(quote), ofr, $(this), 1 ether, 1 ether, "mgv/makerTransferFail");
    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    emit Credit(address(refusemkr), mkr_provision - penalty);
  }

  function test_taker_reverts_on_penalty_triggers_revert() public {
    uint ofr = refusemkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    refuseReceive = true;
    quote.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/sendPenaltyReverted");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_base() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook

    base.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail($(base), $(quote), ofr, $(this), 1 ether, 1 ether, "mgv/makerTransferFail");
    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_quote() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), 100_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/makerReceiveFail"); // status visible in the posthook

    quote.blacklists(address(mkr));
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));

    emit OfferFail($(base), $(quote), ofr, $(this), 1 ether, 1 ether, "mgv/makerReceiveFail");
    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function test_taker_collects_failing_offer() public {
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    uint beforeWei = $(this).balance;

    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 0, 100_000]), true);
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(takerGot == takerGave && takerGave == 0, "Transaction data should be 0");
    assertTrue($(this).balance > beforeWei, "Taker was not compensated");
  }

  function test_taker_reimbursed_if_maker_reverts() public {
    uint mkr_provision = reader.getProvision($(base), $(quote), 50_000);
    quote.approve($(mgv), 1 ether);
    uint ofr = failmkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    uint beforeQuote = quote.balanceOf($(this));
    uint beforeWei = $(this).balance;

    expectFrom($(mgv));
    emit OfferFail($(base), $(quote), ofr, $(this), 1 ether, 1 ether, "mgv/makerRevert");
    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]), true);
    uint penalty = $(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(takerGot == takerGave && takerGave == 0, "Incorrect transaction information");
    assertTrue(beforeQuote == quote.balanceOf($(this)), "taker balance should not be lower if maker doesn't pay back");
    emit Credit(address(failmkr), mkr_provision - penalty);
  }

  function test_taker_hasnt_approved_base_succeeds_order_with_fee() public {
    mgv.setFee($(base), $(quote), 3);

    uint balTaker = base.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 1 ether);
    uint shouldGet = reader.minusFee($(base), $(quote), 1 ether);
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
    assertEq(base.balanceOf($(this)) - balTaker, shouldGet, "Incorrect delivered amount");
  }

  function test_taker_hasnt_approved_base_succeeds_order_wo_fee() public {
    uint balTaker = base.balanceOf($(this));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 1 ether);
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
    assertEq(base.balanceOf($(this)) - balTaker, 1 ether, "Incorrect delivered amount");
  }

  function test_taker_hasnt_approved_quote_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    base.approve($(mgv), 1 ether);

    vm.expectRevert("mgv/takerTransferFail");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
  }

  function test_simple_snipe() public {
    uint ofr = mkr.newOfferByVolume(1.1 ether, 1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    base.approve($(mgv), 10 ether);
    quote.approve($(mgv), 10 ether);
    uint balTaker = base.balanceOf($(this));
    uint balMaker = quote.balanceOf(address(mkr));
    MgvStructs.OfferPacked offer = pair.offers(ofr);

    expectFrom($(mgv));
    emit OfferSuccess($(base), $(quote), ofr, $(this), 1 ether, offer.tick().inboundFromOutbound(1 ether));
    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
    assertTrue(successes == 1, "Snipe should succeed");
    assertApproxEqRel(base.balanceOf($(this)) - balTaker, 1 ether, relError(10), "Incorrect delivered amount (taker)");
    assertApproxEqRel(
      quote.balanceOf(address(mkr)) - balMaker, 1.1 ether, relError(10), "Incorrect delivered amount (maker)"
    );
    assertApproxEqRel(takerGot, 1 ether, relError(10), "Incorrect transaction information");
    assertApproxEqRel(takerGave, 1.1 ether, relError(10), "Incorrect transaction information");
  }

  function test_simple_marketOrder() public {
    mkr.newOfferByVolume(1.1 ether, 1 ether, 50_000, 0);
    mkr.newOfferByVolume(1.2 ether, 1 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");

    base.approve($(mgv), 10 ether);
    quote.approve($(mgv), 10 ether);
    uint balTaker = base.balanceOf($(this));
    uint balMaker = quote.balanceOf(address(mkr));

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume($(base), $(quote), 2 ether, 4 ether, true);
    assertApproxEqRel(takerGot, 2 ether, relError(10), "Incorrect declared delivered amount (taker)");
    assertApproxEqRel(takerGave, 2.3 ether, relError(10), "Incorrect declared delivered amount (maker)");
    assertApproxEqRel(base.balanceOf($(this)) - balTaker, 2 ether, relError(10), "Incorrect delivered amount (taker)");
    assertApproxEqRel(
      quote.balanceOf(address(mkr)) - balMaker, 2.3 ether, relError(10), "Incorrect delivered amount (maker)"
    );
  }

  function test_simple_fillWants() public {
    mkr.newOfferByVolume(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume($(base), $(quote), 1 ether, 2 ether, true);
    assertEq(takerGot, 1 ether, "Incorrect declared delivered amount (taker)");
    assertEq(takerGave, 1 ether, "Incorrect declared delivered amount (maker)");
  }

  function test_simple_fillGives() public {
    mkr.newOfferByVolume(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume($(base), $(quote), 1 ether, 2 ether, false);
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  // before ticks: testing whether a wants of 0 works
  // after ticks: wants of 0 not possible since we store log(wants/gives) as tick. Testing with an extremely small amount.
  function test_fillGives_at_0_wants_works() public {
    uint ofr = mkr.newOfferByVolume(10, 2 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint successes, uint takerGot, uint takerGave,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 10, 300_000]), false);
    assertEq(successes, 1, "snipe should succeed");
    // console.log("offer wants",pair.offers(ofr).wants());
    // console.log("offer tick",pair.offers(ofr).tick().toString());
    assertEq(takerGave, 10, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillGives() public {
    mkr.newOfferByVolume(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume($(base), $(quote), 0 ether, 2 ether, false);
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillWants() public {
    mkr.newOfferByVolume(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quote.approve($(mgv), 10 ether);

    (uint takerGot, uint takerGave,,) = mgv.marketOrderByVolume($(base), $(quote), 0 ether, 2 ether, true);
    assertEq(takerGave, 0 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 0 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_taker_has_no_quote_fails_order() public {
    uint ofr = mkr.newOfferByVolume(100 ether, 2 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/tradeSuccess");

    quote.approve($(mgv), 100 ether);
    base.approve($(mgv), 1 ether); // not necessary since no fee

    vm.expectRevert("mgv/takerTransferFail");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 2 ether, 100_000]), true);
  }

  function test_maker_has_not_enough_base_fails_order() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    mkr.expect("mgv/makerTransferFail");
    // getting rid of base tokens
    //mkr.transferToken(base,$(this),5 ether);
    quote.approve($(mgv), 0.5 ether);
    MgvStructs.OfferPacked offer = pair.offers(ofr);

    expectFrom($(mgv));
    uint takerWants = 50 ether;
    emit OfferFail(
      $(base), $(quote), ofr, $(this), takerWants, offer.tick().inboundFromOutbound(takerWants), "mgv/makerTransferFail"
    );
    (uint successes,,,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 50 ether, 100_000]), true
    );
    assertTrue(successes == 0, "order should fail");
  }

  // FIXME remove this manual test when the reason for why it was failing is clear
  /* It stops failing if I redefine inboundFromOutboundUpTick as
      uint nextPrice_e18 = Tick.wrap(Tick.unwrap(tick)+1).priceFromTick_e18();
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

  //   mgv.setDensityFixed($(base), $(quote), 0);
  //   uint ofr = mkr.newOfferByVolume(makerWants, makerGives, 100_000, 0);
  //   MgvStructs.OfferPacked offer = pair.offers(ofr);
  //   pc = uint16(bound(pc, 0, 10_000));
  //   Tick takerTick = offer.tick();
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
  //       Tick.wrap(Tick.unwrap(takerTick) + 1).priceFromTick_e18(),
  //       "TakerGives should not overestimate too much"
  //     );
  //   }

  //   // Tick takerTick = Tick.wrap(Tick.unwrap(offer.tick())*10_000/(pc*10_000));
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
  //     testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, takerWants, takerGives, 100_000]), true);
  //   assertEq(successes, 1, "order should succeed");
  //   assertEq(takerGot, takerWants, "wrong takerGot");
  //   // Taker does not give all it has since it overestimates price - assertEq(takerGave, takerGives, "wrong takerGave");
  // }

  function test_maker_revert_is_logged() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    MgvStructs.OfferPacked offer = pair.offers(ofr);
    Tick offerTick = offer.tick();
    mkr.expect("mgv/makerRevert");
    mkr.shouldRevert(true);
    quote.approve($(mgv), 1 ether);
    expectFrom($(mgv));
    emit OfferFail($(base), $(quote), ofr, $(this), 1 ether, 1 ether, "mgv/makerRevert");
    testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
  }

  function test_snipe_on_higher_price_fails() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 0.5 ether);

    (uint successes,,,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick) - 1), 1 ether, 100_000]), true
    );
    assertTrue(successes == 0, "Order should fail when order price is higher than offer");
  }

  function test_snipe_on_higher_gas_fails() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 1 ether);

    (uint successes,,,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 50_000]), true);
    assertTrue(successes == 0, "Order should fail when order gas is higher than offer");
  }

  function test_detect_lowgas() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 100 ether);

    uint[4][] memory targets = wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 100_000]);
    bytes memory cd = abi.encodeCall(testMgv.snipesInTest, ($(base), $(quote), targets, true));

    (bool noRevert, bytes memory data) = $(mgv).call{gas: 130000}(cd);
    if (noRevert) {
      fail("take should fail due to low gas");
    } else {
      assertEq(getReason(data), "mgv/notEnoughGasForMakerTrade", "wrong revert reason");
    }
  }

  function test_snipe_on_lower_price_succeeds() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    Tick offerTick = pair.offers(ofr).tick();
    quote.approve($(mgv), 2 ether);
    uint balTaker = base.balanceOf($(this));
    uint balMaker = quote.balanceOf(address(mkr));

    (uint successes,,,,) = testMgv.snipesInTest(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick) + 1), 1 ether, 100_000]), true
    );
    assertTrue(successes == 1, "Order should succeed when order price is lower than offer");
    // checking order was executed at Maker's price
    assertEq(base.balanceOf($(this)) - balTaker, 1 ether, "Incorrect delivered amount (taker)");
    assertEq(quote.balanceOf(address(mkr)) - balMaker, 1 ether, "Incorrect delivered amount (maker)");
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
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 50_000, 0);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 50_000, 1);
    mkr.expect("mgv/tradeSuccess");
    (uint takerGot,,,) = mgv.marketOrderByVolume($(base), $(quote), 0.15 ether, 0.15 ether, true);
    assertEq(takerGot, 0.15 ether, "Incorrect declared partial fill amount");
    assertEq(base.balanceOf($(this)), 0.15 ether, "incorrect partial fill");
  }

  // ! unreliable test, depends on gas use
  function test_market_order_stops_for_high_price() public {
    quote.approve($(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOfferByVolume((i + 1) * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 2 * (0.1 ether + 0.1 ether);
    uint takerGives = 2 * (0.1 ether + 0.2 ether);
    mgv.marketOrderByVolume{gas: 350_000}($(base), $(quote), takerWants, takerGives, true);
  }

  // ! unreliable test, depends on gas use
  function test_market_order_stops_for_filled_mid_offer() public {
    quote.approve($(mgv), 1 ether);
    for (uint i = 1; i < 11; i++) {
      mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.05 ether;
    uint takerGives = 0.1 ether + 0.1 ether;
    mgv.marketOrderByVolume{gas: 450_000}($(base), $(quote), takerWants, takerGives, true);
  }

  function test_market_order_stops_for_filled_after_offer() public {
    quote.approve($(mgv), 1 ether);
    for (uint i = 1; i < 11; i++) {
      mkr.newOfferByVolume(i * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.1 ether;
    uint takerGives = 0.1 ether + 0.2 ether;
    mgv.marketOrderByVolume{gas: 450_000}($(base), $(quote), takerWants, takerGives, true);
  }

  function test_takerWants_wider_than_160_bits_fails_marketOrder() public {
    vm.expectRevert("mgv/mOrder/takerWants/160bits");
    mgv.marketOrderByVolume($(base), $(quote), 2 ** 160, 1, true);
  }

  function test_snipe_with_0_wants_ejects_offer() public {
    quote.approve($(mgv), 1 ether);
    uint mkrBal = base.balanceOf(address(mkr));
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 50_000, 0);
    Tick offerTick = pair.offers(ofr).tick();

    (uint successes,,,,) =
      testMgv.snipesInTest($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 0, 50_000]), true);
    assertTrue(successes == 1, "snipe should succeed");
    assertEq(mgv.best($(base), $(quote)), 0, "offer should be gone");
    assertEq(base.balanceOf(address(mkr)), mkrBal, "mkr balance should not change");
  }

  function test_unsafe_gas_left_fails_order() public {
    mgv.setGasbase($(base), $(quote), 1);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    Tick offerTick = pair.offers(ofr).tick();

    uint[4][] memory targets = wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 120_000]);
    vm.expectRevert("mgv/notEnoughGasForMakerTrade");
    testMgv.snipesInTest{gas: 120_000}($(base), $(quote), targets, true);
  }

  function test_unsafe_gas_left_fails_posthook() public {
    mgv.setGasbase($(base), $(quote), 1);
    quote.approve($(mgv), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 120_000, 0);
    Tick offerTick = pair.offers(ofr).tick();

    uint[4][] memory targets = wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 120_000]);
    vm.expectRevert("mgv/notEnoughGasForMakerPosthook");
    testMgv.snipesInTest{gas: 280_000}($(base), $(quote), targets, true);
  }

  // FIXME Make a token that goes out of gas on transfer to taker
  // So we don't have to find exact gas values here
  // function test_unsafe_gas_left_fails_to_pay_taker() public {
  //   mgv.setGasbase($(base), $(quote), 1);
  //   quote.approve($(mgv), 1 ether);
  //   uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 220_000, 0);
  //   Tick offerTick = pair.offers(ofr).tick();
  //   vm.expectRevert("mgv/MgvFailToPayTaker");
  //   testMgv.snipesInTest{gas: 240_000}($(mgv), $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(offerTick)), 1 ether, 220_000]), true);
  // }

  function test_marketOrder_on_empty_book_does_not_revert() public {
    mgv.marketOrderByVolume($(base), $(quote), 1 ether, 1 ether, true);
  }

  function test_marketOrder_on_empty_book_does_not_leave_lock_on() public {
    mgv.marketOrderByVolume($(base), $(quote), 1 ether, 1 ether, true);
    assertTrue(!mgv.locked($(base), $(quote)), "mgv should not be locked after marketOrder on empty OB");
  }

  function test_takerWants_is_zero_succeeds() public {
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 0, 1 ether, true);
    assertEq(got, 0, "Taker got too much");
    assertEq(gave, 0 ether, "Taker gave too much");
  }

  function test_takerGives_is_zero_succeeds() public {
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 1 ether, 0, true);
    assertEq(got, 0, "Taker got too much");
    assertEq(gave, 0 ether, "Taker gave too much");
  }

  function test_failing_offer_volume_does_not_count_toward_filled_volume() public {
    quote.approve($(mgv), 1 ether);
    failmkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000);
    (uint got,,,) = mgv.marketOrderByVolume($(base), $(quote), 1 ether, 0, true);
    assertEq(got, 1 ether, "should have gotten 1 ether");
  }

  // function test_reverting_monitor_on_notify() public {
  //   BadMonitor badMonitor = new BadMonitor({revertNotify:true,revertRead:false});
  //   mgv.setMonitor(badMonitor);
  //   mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
  //   quote.approve($(mgv), 2 ether);
  //   (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), 1 ether, 1 ether, true);

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
    badMgv.activate($(base), $(quote), 0, 0, 0);

    TestMaker mkr2 = new TestMaker(badMgv,base,quote);
    badMgv.fund{value: 10 ether}($(mkr2));
    mkr2.newOfferByVolume(1 ether, 1 ether, 1, 0);
    vm.expectRevert("mgv/swapError");
    badMgv.marketOrderByVolume{gas: 150000}($(base), $(quote), 1 ether, 1 ether, true);
  }

  /* # Clean tests */
  /* Clean parameter validation */
  function test_gives_tick_outside_range_fails_clean() public {
    uint ofr = mkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 1 << 23, 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_gives_volume_above_96bits_fails_clean() public {
    uint ofr = mkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 0, 1 << 96)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  /* Clean offer state&match validation */
  function test_clean_on_nonexistent_offer_fails() public {
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(1, 0, 0, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_clean_non_live_offer_fails() public {
    uint ofr = mkr.newOfferByTick(0, 1 ether, 100_000);
    mkr.retractOffer(ofr);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_cleaning_with_exact_offer_details_succeeds() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
  }

  function test_giving_smaller_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, -1, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_giving_bigger_tick_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 1, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have succeeded");
  }

  function test_giving_smaller_gasreq_to_clean_fails() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 99_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_giving_bigger_gasreq_to_clean_succeeds() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_001, 0)), $(this));
    assertTrue(successes > 0, "cleaning should have succeeded");
  }

  /* Clean - offer execution */
  function test_cleaning_non_failing_offer_fails() public {
    uint ofr = mkr.newOfferByTick(0, 1 ether, 100_000);
    (uint successes,) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertEq(successes, 0, "cleaning should have failed");
  }

  function test_cleaning_failing_offer_transfers_bounty() public {
    uint balanceBefore = $(this).balance;
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    (, uint bounty) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0)), $(this));
    assertTrue(bounty > 0, "cleaning should have yielded a bounty");
    uint balanceAfter = $(this).balance;
    assertEq(balanceBefore + bounty, balanceAfter, "the bounty was not transfered to the cleaner");
  }

  function test_clean_multiple_failing_offers() public {
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    uint ofr2 = failmkr.newOfferByTick(0, 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets =
      wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 0), MgvLib.CleanTarget(ofr2, 0, 100_000, 0));
    (uint successes, uint bounty) = mgv.cleanByImpersonation($(base), $(quote), targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "both offers should have been cleaned");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
  }

  function test_cleans_failing_offers_despite_one_not_failing() public {
    deal($(quote), $(this), 10 ether);
    uint ofr = failmkr.newOfferByTick(0, 1 ether, 100_000);
    uint ofr2 = mkr.newOfferByTick(0, 1 ether, 100_000);
    uint ofr3 = failmkr.newOfferByTick(0, 1 ether, 100_000);

    uint oldBal = $(this).balance;

    MgvLib.CleanTarget[] memory targets = wrap_dynamic(
      MgvLib.CleanTarget(ofr, 0, 100_000, 0),
      MgvLib.CleanTarget(ofr2, 0, 100_000, 0),
      MgvLib.CleanTarget(ofr3, 0, 100_000, 0)
    );
    (uint successes, uint bounty) = mgv.cleanByImpersonation($(base), $(quote), targets, $(this));

    uint newBal = $(this).balance;

    assertEq(successes, 2, "cleaning should succeed for all but one offer");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
  }

  function test_cleaning_by_impersonation_succeeds_and_does_not_transfer_funds() public {
    uint ofr = failNonZeroMkr.newOfferByTick(0, 1 ether, 100_000);
    // $this cannot clean with taker because of lack of funds/approval
    (, uint bounty) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(this));
    assertEq(bounty, 0, "cleaning should have failed");

    uint balanceNativeBefore = $(this).balance;
    uint balanceBaseBefore = base.balanceOf($(this));
    uint balanceQuoteBefore = quote.balanceOf($(this));

    // Create another taker that has the needed funds and have approved Mangrove
    TestTaker otherTkr = setupTaker($(base), $(quote), "otherTkr[$(A),$(B)]");
    deal($(quote), $(otherTkr), 10 ether);
    otherTkr.approveMgv(quote, 1 ether);
    uint otherTkrBalanceNativeBefore = $(otherTkr).balance;
    uint otherTkrBalanceBaseBefore = base.balanceOf($(otherTkr));
    uint otherTkrBalanceQuoteBefore = quote.balanceOf($(otherTkr));

    // Clean by impersonating the other taker
    (, bounty) =
      mgv.cleanByImpersonation($(base), $(quote), wrap_dynamic(MgvLib.CleanTarget(ofr, 0, 100_000, 1)), $(otherTkr));
    assertTrue(bounty > 0, "cleaning should have yielded a bounty");

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
    mkr.newOfferByTick(_firstPostedTick, 1 ether, 100_000);
    mkr.newOfferByTick(_tick, 1 ether, 100_000);
    uint ofr3 = mkr.newOfferByTick(_tick, 1 ether, 100_000);
    uint ofr4 = mkr.newOfferByTick(_tick, 1 ether, 100_000);
    uint volume = leaveOneOnly ? 3 ether : 2 ether;
    mgv.marketOrderByTick($(base), $(quote), _tick, volume, true);

    Tick tick = Tick.wrap(_tick);

    uint bestId = leaveOneOnly ? ofr4 : ofr3;
    MgvStructs.OfferPacked best = pair.offers(bestId);
    Leaf leaf = pair.leafs(best.tick().leafIndex());
    assertEq(leaf.firstOfIndex(tick.posInLeaf()), bestId, "wrong first of tick");
    assertEq(leaf.lastOfIndex(tick.posInLeaf()), ofr4, "wrong last of tick");
    assertEq(pair.local().tickPosInLeaf(), tick.posInLeaf(), "wrong local.tickPosInleaf");
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
