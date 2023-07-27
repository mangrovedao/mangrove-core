// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./KandelTest.t.sol";
import {console} from "forge-std/console.sol";

abstract contract GeometricKandelTest is KandelTest {
  function full_compound() internal view returns (uint24) {
    return uint24(10 ** PRECISION);
  }

  function test_populates_order_book_correctly() public {
    printOB();
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_bid_complete_fill_compound_1() public {
    test_bid_complete_fill(full_compound(), 0);
  }

  function test_bid_complete_fill_compound_0() public {
    test_bid_complete_fill(0, full_compound());
  }

  function test_bid_complete_fill_compound_half() public {
    test_bid_complete_fill(5_000, full_compound());
  }

  function test_ask_complete_fill_compound_1() public {
    test_ask_complete_fill(0, full_compound());
  }

  function test_ask_complete_fill_compound_0() public {
    test_ask_complete_fill(full_compound(), 0);
  }

  function test_ask_complete_fill_compound_half() public {
    test_ask_complete_fill(0, full_compound() / 2);
  }

  function test_bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote) public {
    bid_complete_fill(compoundRateBase, compoundRateQuote, 4);
  }

  function bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    virtual
    returns (uint takerGot, uint takerGave, uint fee)
  {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateQuote <= full_compound());
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldAsk = kdl.getOffer(Ask, index + STEP);
    uint successes;
    (successes, takerGot, takerGave,, fee) = sellToBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newAsk = kdl.getOffer(Ask, index + STEP);
    assertTrue(newAsk.gives() <= takerGave + oldAsk.gives(), "Cannot give more than what was received");
    assertTrue(newAsk.gives() > oldAsk.gives(), "Should give more than what was previously asked");
    if (compoundRateBase == full_compound()) {
      assertTrue(newAsk.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    }
  }

  function test_ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote) public {
    ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
  }

  function test_update_compoundRateQuote(uint24 compoundRateQuote) public {
    vm.assume(compoundRateQuote <= full_compound());
    vm.assume(compoundRateQuote > 0);

    GeometricKandel.Params memory params = getParams(kdl);
    // taking ask #5
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);
    // updates bid #4
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants(),
      takerWants: ask.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 5);
    order.offer = ask;

    MgvStructs.OfferPacked bid_;
    uint gives_for_0;
    uint snapshotId = vm.snapshot();
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    bid_ = kdl.getOffer(Bid, 4);
    gives_for_0 = bid_.gives();
    require(vm.revertTo(snapshotId), "snapshot restore failed");

    // at 0% compounding, one wants to buy back what was sent
    // computation might have rounding error because bid_.wants is derived from bid_.gives
    console.log(bid_.wants(), bid.wants(), ask.gives());
    assertApproxEqRel(bid_.wants(), bid.wants() + ask.gives(), 10 ** 9, "Incorrect wants when 0% compounding");

    // changing compoundRates
    vm.prank(maker);
    kdl.setCompoundRates(params.compoundRateBase, compoundRateQuote);
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);

    bid_ = kdl.getOffer(Bid, 4);
    if (compoundRateQuote == full_compound()) {
      // 100% compounding, one gives what one got
      assertEq(bid_.gives(), bid.gives() + ask.wants(), "Incorrect gives when 100% compounding");
    } else {
      // in between one just checks that one is giving more than before
      assertTrue(bid_.gives() > gives_for_0, "Incorrect gives compounding");
    }
  }

  function test_update_compoundRateBase(uint24 compoundRateBase) public {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateBase > 0);

    GeometricKandel.Params memory params = getParams(kdl);
    // taking bid #4
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);
    // updates ask #5
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Bid, 4);
    order.offer = bid;

    MgvStructs.OfferPacked ask_;
    uint gives_for_0;
    uint snapshotId = vm.snapshot();
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    ask_ = kdl.getOffer(Ask, 5);
    gives_for_0 = ask_.gives();
    require(vm.revertTo(snapshotId), "snapshot restore failed");

    // at 0% compounding, one wants to buy back what was sent
    // computation might have rounding error because ask_.wants is derived from ask_.gives
    console.log(ask_.wants(), ask.wants(), bid.gives());
    assertEq(ask_.wants(), ask.wants() + bid.gives(), "Incorrect wants when 0% compounding");

    // changing compoundRates
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, params.compoundRateQuote);
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);

    ask_ = kdl.getOffer(Ask, 5);
    if (compoundRateBase == full_compound()) {
      // 100% compounding, one gives what one got
      assertEq(ask_.gives(), ask.gives() + bid.wants(), "Incorrect gives when 100% compounding");
    } else {
      // in between one just checks that one is giving more than before
      assertTrue(ask_.gives() > gives_for_0, "Incorrect gives compounding");
    }
  }

  function ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    virtual
    returns (uint takerGot, uint takerGave, uint fee)
  {
    vm.assume(compoundRateBase <= full_compound());
    vm.assume(compoundRateQuote <= full_compound());
    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    MgvStructs.OfferPacked oldBid = kdl.getOffer(Bid, index - STEP);
    uint successes;
    (successes, takerGot, takerGave,, fee) = buyFromBestAs(taker, 1000 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    uint[] memory expectedStatus = new uint[](10);
    // Build this for index=5: assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
    for (uint i = 0; i < 10; i++) {
      expectedStatus[i] = i < index ? 1 : i == index ? 0 : 2;
    }
    assertStatus(expectedStatus);
    MgvStructs.OfferPacked newBid = kdl.getOffer(Bid, index - STEP);
    assertTrue(newBid.gives() <= takerGave + oldBid.gives(), "Cannot give more than what was received");
    assertTrue(newBid.gives() > oldBid.gives(), "Should give more than previous value");

    if (compoundRateQuote == full_compound()) {
      assertTrue(newBid.wants() >= takerGot + fee, "Auto compounding should want more than what taker gave");
    }
  }

  function test_bid_partial_fill() public {
    (uint successes, uint takerGot,,,) = sellToBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill() public {
    (uint successes, uint takerGot,,,) = buyFromBestAs(taker, 0.01 ether);
    assertTrue(successes == 1 && takerGot > 0, "Snipe failed");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_ask_partial_fill_existingDual() public {
    partial_fill(Ask, true);
  }

  function test_bid_partial_fill_existingDual() public {
    partial_fill(Bid, true);
  }

  function test_ask_partial_fill_noDual() public {
    partial_fill(Ask, false);
  }

  function test_bid_partial_fill_noDual() public {
    partial_fill(Bid, false);
  }

  function testFail_ask_partial_fill_noDual_noIncident() public {
    vm.expectEmit(false, false, false, false, $(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, 0, "", "");
    partial_fill(Ask, false);
  }

  function partial_fill(OfferType ba, bool existingDual) internal {
    // Arrange
    uint successes;
    uint takerGot;
    if (!existingDual) {
      // Completely fill dual
      (successes, takerGot,,,) = ba == Bid ? buyFromBestAs(taker, 1000 ether) : sellToBestAs(taker, 1000 ether);
      assertTrue(successes == 1 && takerGot > 0, "Snipe of dual failed");
    }

    // Act
    (successes, takerGot,,,) = ba == Ask ? buyFromBestAs(taker, 1 wei) : sellToBestAs(taker, 1 wei);

    // Assert
    assertTrue(successes == 1, "Snipe failed");
    if (ba == Ask) {
      // taker gets nothing for Bid due to sending so little and rounding
      assertTrue(takerGot > 0, "Taker did not get expected");
    }
    if (existingDual) {
      // a tiny bit ends up as pending - but all offers still live
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    } else {
      // the dual offer could not be made live due to too little transported - but residual still reposted
      if (ba == Ask) {
        assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      } else {
        assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      }
    }
  }

  function test_all_bids_all_asks_and_back() public {
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    vm.prank(taker);
    mgv.marketOrder($(base), $(quote), type(uint96).max, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 1, 1, 1, 1, 0]));
    vm.prank(taker);
    mgv.marketOrder($(quote), $(base), 1 ether, type(uint96).max, false);
    assertStatus(dynamic([uint(0), 2, 2, 2, 2, 2, 2, 2, 2, 2]));
    uint askVol = kdl.offeredVolume(Ask);
    vm.prank(taker);
    mgv.marketOrder($(base), $(quote), askVol / 2, type(uint96).max, true);
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
  }

  function test_take_new_offer() public {
    sellToBestAs(taker, 1 ether);
    sellToBestAs(taker, 1 ether);
    // MM state:
    assertStatus(dynamic([uint(1), 1, 1, 0, 2, 2, 2, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
  }

  function test_retractOffers() public {
    uint preBalance = maker.balance;
    uint preMgvBalance = mgv.balanceOf(address(kdl));

    expectFrom($(kdl));
    emit RetractStart();
    expectFrom($(mgv));
    emit OfferRetract(address(quote), address(base), kdl.offerIdOfIndex(Bid, 0), true);
    expectFrom($(kdl));
    emit RetractEnd();

    vm.prank(maker);
    kdl.retractOffers(0, 5);
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    assertEq(0, kdl.offeredVolume(Ask), "All ask volume should be retracted");
    assertEq(0, kdl.offeredVolume(Bid), "All bid volume should be retracted");
    assertGt(mgv.balanceOf(address(kdl)), preMgvBalance, "Kandel should have balance on mgv after retract");
    assertEq(maker.balance, preBalance, "maker should not be credited yet");

    vm.prank(maker);
    kdl.withdrawFromMangrove(type(uint).max, maker);
    assertGt(maker.balance, preBalance, "maker should be credited");
  }

  function take_full_bid_and_ask_repeatedly(
    uint loops,
    uint24 compoundRateBase,
    uint24 compoundRateQuote,
    ExpectedChange baseVolumeChange,
    ExpectedChange quoteVolumeChange
  ) internal {
    deal($(base), taker, cash(base, 5000));
    deal($(quote), taker, cash(quote, 7000000));
    uint initialTotalVolumeBase;
    uint initialTotalVolumeQuote;
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    for (uint i = 0; i < loops; i++) {
      ask_complete_fill(compoundRateBase, compoundRateQuote, 5);
      assertStatus(dynamic([uint(1), 1, 1, 1, 1, 0, 2, 2, 2, 2]));
      if (i == 0) {
        // With the ask filled, what is the current volume for bids?
        initialTotalVolumeQuote = kdl.offeredVolume(Bid);
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(quoteVolumeChange, initialTotalVolumeQuote, kdl.offeredVolume(Bid), "quote volume");
      }

      bid_complete_fill(compoundRateBase, compoundRateQuote, 4);

      assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));
      if (i == 0) {
        // With the bid filled, what is the current volume for asks?
        initialTotalVolumeBase = kdl.offeredVolume(Ask);
      } else if (i == loops - 1) {
        // final loop - assert volume delta
        assertChange(baseVolumeChange, initialTotalVolumeBase, kdl.offeredVolume(Ask), "base volume");
      }
    }
  }

  function test_take_full_bid_and_ask_10_times_full_compound() public {
    take_full_bid_and_ask_repeatedly(
      10, full_compound(), full_compound(), ExpectedChange.Increase, ExpectedChange.Increase
    );
  }

  function test_take_full_bid_and_ask_10_times_zero_quote_compound() public {
    take_full_bid_and_ask_repeatedly(10, full_compound(), 0, ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_zero_base_compound() public {
    take_full_bid_and_ask_repeatedly(10, 0, full_compound(), ExpectedChange.Same, ExpectedChange.Same);
  }

  function test_take_full_bid_and_ask_10_times_close_to_zero_base_compound() public {
    take_full_bid_and_ask_repeatedly(10, 1, full_compound(), ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_increasing_boundary() public {
    take_full_bid_and_ask_repeatedly(10, 49040, 49040, ExpectedChange.Increase, ExpectedChange.Increase);
  }

  function test_take_full_bid_and_ask_10_times_partial_compound_decreasing_boundary() public {
    take_full_bid_and_ask_repeatedly(10, 49030, 49030, ExpectedChange.Decrease, ExpectedChange.Decrease);
  }

  function test_take_full_bid_and_ask_10_times_zero_compound() public {
    take_full_bid_and_ask_repeatedly(10, 0, 0, ExpectedChange.Decrease, ExpectedChange.Decrease);
  }

  function test_populateChunk_invalidArrayLength_reverts() public {
    vm.prank(maker);
    // pivot
    vm.expectRevert();
    GeometricKandel.Distribution memory dist;
    dist.indices = new uint[](1);
    dist.baseDist = new uint[](1);
    dist.quoteDist = new uint[](1);
    kdl.populateChunk(dist, new uint[](0), 0);

    // base
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.baseDist = new uint[](0);
    dist.quoteDist = new uint[](1);
    kdl.populateChunk(dist, new uint[](1), 0);

    // quote
    vm.prank(maker);
    vm.expectRevert();
    dist.indices = new uint[](1);
    dist.baseDist = new uint[](1);
    dist.quoteDist = new uint[](0);
    kdl.populateChunk(dist, new uint[](1), 0);
  }

  function test_populate_retracts_at_zero() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);

    populateSingle(kdl, index, 123, 0, 0, 5, bytes(""));
    // Bid should be retracted
    assertStatus(index, OfferStatus.Dead);
  }

  function test_populate_density_too_low_reverted() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    populateSingle(kdl, index, 1, 123, 0, 5, "mgv/writeOffer/density/tooLow");
  }

  function test_populate_existing_offer_is_updated() public {
    uint index = 3;
    assertStatus(index, OfferStatus.Bid);
    uint offerId = kdl.offerIdOfIndex(Bid, index);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);

    populateSingle(kdl, index, bid.wants() * 2, bid.gives() * 2, 0, 5, "");

    uint offerIdPost = kdl.offerIdOfIndex(Bid, index);
    assertEq(offerIdPost, offerId, "offerId should be unchanged (offer updated)");
    MgvStructs.OfferPacked bidPost = kdl.getOffer(Bid, index);
    assertEq(bidPost.gives(), bid.gives() * 2, "gives should be changed");
  }

  function test_step_higher_than_kandel_size_jumps_to_last() public {
    uint n = getParams(kdl).pricePoints;
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, n - 1);
    // placing a bid on the last position
    // dual of this bid will try to place an ask at n+1 and should place it at n-1 instead of n
    populateSingle(kdl, n - 1, ask.gives(), ask.wants(), 0, n, "");
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, n - 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Bid, n - 1);
    order.offer = bid;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked ask_ = kdl.getOffer(Ask, n - 1);

    assertTrue(ask.gives() < ask_.gives(), "Ask was not updated");
    assertEq(ask.gives() * ask_.wants(), ask.wants() * ask_.gives(), "Incorrect price");
  }

  function test_transport_below_min_price_accumulates_at_index_0() public {
    uint24 ratio = uint24(108 * 10 ** PRECISION / 100);

    (GeometricKandel.Distribution memory distribution1, uint lastQuote) =
      KandelLib.calculateDistribution(0, 5, initBase, initQuote, ratio, PRECISION);

    (GeometricKandel.Distribution memory distribution2,) =
      KandelLib.calculateDistribution(5, 10, initBase, lastQuote, ratio, PRECISION);

    // setting params.spread to 2
    GeometricKandel.Params memory params = getParams(kdl);
    params.spread = 4;
    vm.prank(maker);
    kdl.setParams(params);
    // repopulating to update the spread (but with the same distribution)
    mgv.fund{value: 1 ether}($(kdl));
    vm.prank(maker);
    kdl.populateChunk(distribution1, dynamic([uint(0), 1, 2, 3, 4]), 5);
    vm.prank(maker);
    kdl.populateChunk(distribution2, dynamic([uint(0), 1, 2, 3, 4]), 5);
    // placing an ask at index 1
    // dual of this ask will try to place a bid at -1 and should place it at 0
    populateSingle(kdl, 1, 0.1 ether, 100 * 10 ** 6, 0, 0, "");

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 1);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants(),
      takerWants: ask.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 1);
    order.offer = ask;
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    MgvStructs.OfferPacked bid_ = kdl.getOffer(Bid, 0);
    assertTrue(bid.gives() < bid_.gives(), "Bid was not updated");
  }

  function test_fail_to_create_dual_offer_logs_incident() public {
    // closing bid market
    vm.prank(mgv.governance());
    mgv.deactivate(address(base), address(quote));
    // taking a bid
    uint offerId = kdl.offerIdOfIndex(Bid, 3);
    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 3);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });

    order.offerId = offerId;
    order.offer = bid;

    expectFrom($(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, 0, "Kandel/newOfferFailed", "mgv/inactive");
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
  }

  function test_fail_to_update_dual_offer_logs_incident() public {
    // closing bid market
    vm.prank(mgv.governance());
    mgv.deactivate(address(base), address(quote));
    // taking a bid that already has a dual ask
    uint offerId = kdl.offerIdOfIndex(Bid, 4);
    uint offerId_ = kdl.offerIdOfIndex(Ask, 5);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 4);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockSellOrder({
      takerGives: bid.wants(),
      takerWants: bid.gives(),
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });

    order.offerId = offerId;
    order.offer = bid;

    expectFrom($(kdl));
    emit LogIncident(IMangrove($(mgv)), base, quote, offerId_, "Kandel/updateOfferFailed", "mgv/inactive");
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
  }

  function test_posthook_density_too_low_still_posts_to_dual() public {
    uint index = 4;
    uint offerId = kdl.offerIdOfIndex(Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    // Take almost all - offer will not be reposted due to density too low
    uint amount = bid.wants() - 1;
    vm.prank(taker);
    mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);

    // verify dual is increased
    MgvStructs.OfferPacked askPost = kdl.getOffer(Ask, index + STEP);
    assertGt(askPost.gives(), ask.gives(), "Dual should offer more even though bid failed to post");
  }

  function test_posthook_dual_density_too_low_not_posted_via_newOffer() public {
    //assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]));
    sellToBestAs(taker, 1000 ether);
    // assertStatus(dynamic([uint(1), 1, 1, 1, 0, 2, 2, 2, 2, 2]));

    uint index = 3;
    uint offerId = kdl.offerIdOfIndex(Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    assertTrue(mgv.isLive(bid), "bid should be live");
    assertTrue(!mgv.isLive(ask), "ask should not be live");

    // Take very little and expect dual posting to fail.
    uint amount = 10000;
    vm.prank(taker);
    (uint successes,,,,) = mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
    assertTrue(successes == 1, "Snipe failed");
    ask = kdl.getOffer(Ask, index + STEP);
    assertTrue(!mgv.isLive(ask), "ask should still not be live");
  }

  function test_posthook_dual_density_too_low_not_posted_via_updateOffer() public {
    // make previous live ask dead
    buyFromBestAs(taker, 1000 ether);

    uint index = 4;
    uint offerId = kdl.offerIdOfIndex(Bid, index);

    MgvStructs.OfferPacked bid = kdl.getOffer(Bid, index);
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, index + STEP);

    assertTrue(mgv.isLive(bid), "bid should be live");
    assertTrue(!mgv.isLive(ask), "ask should not be live");

    // Take very little and expect dual posting to fail.
    uint amount = 10000;
    vm.prank(taker);
    (uint successes,,,,) = mgv.snipes($(quote), $(base), wrap_dynamic([offerId, 0, amount, type(uint).max]), false);
    assertTrue(successes == 1, "Snipe failed");

    ask = kdl.getOffer(Ask, index + STEP);
    assertTrue(!mgv.isLive(ask), "ask should still not be live");
  }

  GeometricKandel.Distribution emptyDist;
  uint[] empty = new uint[](0);

  function test_populate_can_get_set_params_keeps_offers() public {
    GeometricKandel.Params memory params = getParams(kdl);

    uint offeredVolumeBase = kdl.offeredVolume(Ask);
    uint offeredVolumeQuote = kdl.offeredVolume(Bid);

    GeometricKandel.Params memory paramsNew;
    paramsNew.pricePoints = params.pricePoints;
    paramsNew.ratio = params.ratio + 1;
    paramsNew.spread = params.spread + 1;
    paramsNew.compoundRateBase = params.compoundRateBase + 1;
    paramsNew.compoundRateQuote = params.compoundRateQuote + 2;
    paramsNew.gasprice = params.gasprice + 1;
    paramsNew.gasreq = params.gasreq + 1;

    expectFrom(address(kdl));
    emit SetGeometricParams(paramsNew.spread, paramsNew.ratio);
    expectFrom(address(kdl));
    emit SetGasprice(paramsNew.gasprice);
    expectFrom(address(kdl));
    emit SetGasreq(paramsNew.gasreq);
    expectFrom(address(kdl));
    emit SetCompoundRates(paramsNew.compoundRateBase, paramsNew.compoundRateQuote);
    vm.prank(maker);
    kdl.setParams(paramsNew);

    vm.prank(maker);
    kdl.populateChunk(emptyDist, empty, 0);

    GeometricKandel.Params memory params_ = getParams(kdl);

    assertEq(params_.gasprice, paramsNew.gasprice, "gasprice should be changed");
    assertEq(params_.gasreq, paramsNew.gasreq, "gasreq should be changed");
    assertEq(params_.pricePoints, params.pricePoints, "pricePoints should not be changed");
    assertEq(params_.ratio, paramsNew.ratio, "ratio should be changed");
    assertEq(params_.compoundRateBase, paramsNew.compoundRateBase, "compoundRateBase should be changed");
    assertEq(params_.compoundRateQuote, paramsNew.compoundRateQuote, "compoundRateQuote should be changed");
    assertEq(params_.spread, params.spread + 1, "spread should be changed");
    assertEq(offeredVolumeBase, kdl.offeredVolume(Ask), "ask volume should be unchanged");
    assertEq(offeredVolumeQuote, kdl.offeredVolume(Bid), "ask volume should be unchanged");
    assertStatus(dynamic([uint(1), 1, 1, 1, 1, 2, 2, 2, 2, 2]), type(uint).max, type(uint).max);
  }

  function test_populate_throws_on_invalid_ratio() public {
    uint precision = PRECISION;
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** precision - 1);
    params.spread = 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidRatio");
    kdl.setParams(params);
  }

  function test_populate_throws_on_invalid_spread_low() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** PRECISION);
    params.spread = 0;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.setParams(params);
  }

  function test_populate_throws_on_invalid_spread_high() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** PRECISION);
    params.spread = 9;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidSpread");
    kdl.setParams(params);
  }

  function test_populate_invalidCompoundRatesBase_reverts() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** PRECISION);
    params.spread = 1;
    params.compoundRateBase = uint24(10 ** PRECISION + 1);
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateBase");
    kdl.setParams(params);
  }

  function test_populate_invalidCompoundRatesQuote_reverts() public {
    GeometricKandel.Params memory params;
    params.pricePoints = 10;
    params.ratio = uint24(10 ** PRECISION);
    params.spread = 1;
    params.compoundRateQuote = uint24(10 ** PRECISION + 1);
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateQuote");
    kdl.setParams(params);
  }

  function test_setCompoundRatesBase_reverts() public {
    uint wrong_rate = 10 ** PRECISION + 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateBase");
    kdl.setCompoundRates(wrong_rate, 0);
  }

  function test_setCompoundRatesQuote_reverts() public {
    uint wrong_rate = 10 ** PRECISION + 1;
    vm.prank(maker);
    vm.expectRevert("Kandel/invalidCompoundRateQuote");
    kdl.setCompoundRates(0, wrong_rate);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate0() public {
    test_populate_can_repopulate_other_size_and_other_params(0, 0);
  }

  function test_populate_can_repopulate_decreased_size_and_other_params_compoundRate1() public {
    test_populate_can_repopulate_other_size_and_other_params(full_compound(), full_compound());
  }

  function test_populate_can_repopulate_other_size_and_other_params(uint24 compoundRateBase, uint24 compoundRateQuote)
    internal
  {
    vm.prank(maker);
    kdl.retractOffers(0, 10);

    uint24 ratio = uint24(102 * 10 ** PRECISION / 100);
    (GeometricKandel.Distribution memory distribution,) =
      KandelLib.calculateDistribution(0, 5, initBase, initQuote, ratio, PRECISION);

    GeometricKandel.Params memory params;
    params.pricePoints = 5;
    params.ratio = ratio;
    params.spread = 2;
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;

    expectFrom(address(kdl));
    emit SetLength(params.pricePoints);
    vm.prank(maker);
    kdl.setParams(params);
    vm.prank(maker);
    kdl.populateChunk(distribution, dynamic([uint(0), 1, 2, 3, 4]), 3);

    vm.prank(maker);
    kdl.setCompoundRates(compoundRateBase, compoundRateQuote);

    // This only verifies KandelLib
    assertStatus(dynamic([uint(1), 1, 1, 2, 2]));

    sellToBestAs(taker, 1 ether);

    // This verifies dualWantsGivesOfOffer
    assertStatus(dynamic([uint(1), 1, 0, 2, 2]));
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 0, 0, 2, 2]));
    sellToBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(0), 0, 2, 2, 2]));
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    buyFromBestAs(taker, 1 ether);
    assertStatus(dynamic([uint(1), 1, 1, 0, 0]));
  }

  // function test_populates_emits() public {
  //   expectFrom($(mgv));
  //   emit Credit($(kdl), 0.1 ether);

  //   // vm.expectEmit(false, false, false, false, $(mgv));
  //   // emit OfferWrite(address(0), address(0), address(0), 0, 0, 0, 0, 0, 0);
  //   // expectFrom($(kdl));
  //   // emit PopulateEnd();
  //   populateSingle(kdl, 1, 1 ether, 1 ether, 0, 2, bytes(""));
  // }

  function test_setGasprice_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasprice(42);
    vm.prank(maker);
    kdl.setGasprice(42);
    (uint16 gasprice,,,,,,) = kdl.params();
    assertEq(gasprice, uint16(42), "Incorrect gasprice in params");
  }

  function test_setGasprice_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gaspriceTooHigh");
    kdl.setGasprice(2 ** 16);
  }

  function test_setGasreq_valid_setsAndEmits() public {
    expectFrom($(kdl));
    emit SetGasreq(42);
    vm.prank(maker);
    kdl.setGasreq(42);
    (, uint24 gasreq,,,,,) = kdl.params();
    assertEq(gasreq, uint24(42), "Incorrect gasprice in params");
  }

  function test_setGasreq_invalid_reverts() public {
    vm.prank(maker);
    vm.expectRevert("Kandel/gasreqTooHigh");
    kdl.setGasreq(2 ** 24);
  }

  function test_marketOrder_dualOfferUpdate_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(false, 87985);
  }

  function test_marketOrder_dualOfferNew_expectedGasreq() public {
    marketOrder_dualOffer_expectedGasreq(true, 0);
  }

  function marketOrder_dualOffer_expectedGasreq(bool dualNew, uint deltaGasForNew) internal {
    // Arrange
    MgvLib.SingleOrder memory order = mockBuyOrder({takerGives: cash(quote, 100), takerWants: 0.1 ether});
    order.offerId = kdl.offerIdOfIndex(Ask, dualNew ? 6 : 5);

    // Act
    vm.prank($(mgv));
    uint gasTemp = gasleft();
    bytes32 makerData = kdl.makerExecute(order);
    uint makerExecuteCost = gasTemp - gasleft();

    assertTrue(makerData == bytes32(0) || makerData == "IS_FIRST_PULLER", "Unexpected returned data");

    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: makerData, mgvData: "mgv/tradeSuccess"});

    vm.prank($(mgv));
    gasTemp = gasleft();
    kdl.makerPosthook(order, result);
    uint posthookCost = gasTemp - gasleft();
    // Assert
    (, MgvStructs.LocalPacked local) = mgv.config(address(base), address(quote));
    console.log("makerExecute: %d, posthook: %d, deltaGasForNew", makerExecuteCost, posthookCost, deltaGasForNew);
    console.log(
      "Strat gasreq (%d), mockup (%d)",
      kdl.offerGasreq() + local.offer_gasbase(),
      makerExecuteCost + posthookCost + deltaGasForNew
    );
    //assertTrue(makerExecuteCost + posthookCost <= kdl.offerGasreq() + local.offer_gasbase(), "Strat is spending more gas");
  }

  struct TestPivot {
    uint firstAskIndex;
    uint funds;
    uint[] pivotIds;
    uint gas0Pivot;
    uint gasPivots;
    uint baseAmountRequired;
    uint quoteAmountRequired;
    uint snapshotId;
  }

  function test_dualWantsGivesOfOffer_maxBitsPartialTakeFullCompound_correctCalculation() public {
    dualWantsGivesOfOffer_maxBits_correctCalculation(true, 2, true);
  }

  function test_dualWantsGivesOfOffer_maxBitsPartialTakeZeroCompound_correctCalculation() public {
    dualWantsGivesOfOffer_maxBits_correctCalculation(true, 2, false);
  }

  function test_dualWantsGivesOfOffer_maxBitsFullTakeZeroCompound_correctCalculation() public {
    dualWantsGivesOfOffer_maxBits_correctCalculation(false, 2, false);
  }

  function test_dualWantsGivesOfOffer_maxBitsFullTakeFullCompound_correctCalculation() public {
    dualWantsGivesOfOffer_maxBits_correctCalculation(false, 2, true);
  }

  function dualWantsGivesOfOffer_maxBits_correctCalculation(bool partialTake, uint numTakes, bool fullCompound)
    internal
  {
    // With partialTake false we verify uint160(givesR) != givesR in dualWantsGivesOfOffer
    // With partialTake true we verify the edge cases
    // uint160(givesR) != givesR
    // uint96(wants) != wants
    // uint96(gives) != gives
    // in dualWantsGivesOfOffer

    uint8 spread = 8;
    uint8 pricePoints = type(uint8).max;

    uint precision = PRECISION;

    uint compoundRate = fullCompound ? 10 ** precision : 0;

    vm.prank(maker);
    kdl.retractOffers(0, 10);

    for (uint i = 0; i < numTakes; i++) {
      populateSingle(
        PopulateArgs({
          kandel: kdl,
          index: 0,
          base: type(uint96).max,
          quote: type(uint96).max,
          pivotId: 0,
          firstAskIndex: 2,
          pricePoints: pricePoints,
          ratio: 2 * 10 ** precision,
          spread: spread,
          expectRevert: bytes("")
        })
      );

      vm.prank(maker);
      kdl.setCompoundRates(compoundRate, compoundRate);
      // This only verifies KandelLib

      MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);

      deal($(quote), address(kdl), bid.gives());
      deal($(base), address(taker), bid.wants());

      uint amount = partialTake ? 1 ether : bid.wants();

      (uint successes,,,,) = sellToBestAs(taker, amount);
      assertEq(successes, 1, "offer should be sniped");
    }
    uint askOfferId = mgv.best($(base), $(quote));
    uint askIndex = kdl.indexOfOfferId(Ask, askOfferId);

    uint[] memory statuses = new uint[](askIndex+2);
    if (partialTake) {
      MgvStructs.OfferPacked ask = kdl.getOffer(Ask, askIndex);
      if (fullCompound) {
        assertEq(1 ether * numTakes, ask.gives(), "ask should offer the provided 1 ether for each take");
      } else {
        assertGt(
          1 ether * numTakes, ask.gives(), "due to low compound ask should not offer the full ether for each take"
        );
      }
      statuses[0] = uint(OfferStatus.Bid);
    }
    statuses[askIndex] = uint(OfferStatus.Ask);
    assertStatus(statuses, type(uint96).max, type(uint96).max);
  }

  function test_dualWantsGivesOfOffer_bidNearBoundary_correctPrice() public {
    dualWantsGivesOfOffer_nearBoundary_correctPrice(Bid);
  }

  function test_dualWantsGivesOfOffer_askNearBoundary_correctPrice() public {
    dualWantsGivesOfOffer_nearBoundary_correctPrice(Ask);
  }

  function dualWantsGivesOfOffer_nearBoundary_correctPrice(OfferType ba) internal {
    uint8 spread = 3;
    uint8 pricePoints = 6;

    uint precision = PRECISION;

    vm.prank(maker);
    kdl.retractOffers(0, 10);

    populateSingle(
      PopulateArgs({
        kandel: kdl,
        index: ba == Bid ? 4 : 1,
        base: initBase,
        quote: initQuote,
        pivotId: 0,
        firstAskIndex: ba == Bid ? pricePoints : 0,
        pricePoints: pricePoints,
        ratio: 2 * 10 ** precision,
        spread: spread,
        expectRevert: bytes("")
      })
    );
    uint compoundRate = full_compound();
    vm.prank(maker);
    kdl.setCompoundRates(compoundRate, compoundRate);

    (uint successes,,,,) = ba == Bid ? sellToBestAs(taker, 1 ether) : buyFromBestAs(taker, 1 ether);
    assertEq(successes, 1, "offer should be sniped");

    if (ba == Bid) {
      MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 5);
      assertEq(ask.gives(), initBase, "incorrect gives for ask");
      assertEq(ask.wants(), initQuote * 2, "incorrect wants for ask");
    } else {
      MgvStructs.OfferPacked bid = kdl.getOffer(Bid, 0);
      assertEq(bid.gives(), initQuote, "incorrect gives for bid");
      assertEq(bid.wants(), initBase * 2, "incorrect wants for bid");
    }
  }

  function test_allExternalFunctions_differentCallers_correctAuth() public virtual {
    // Arrange
    bytes[] memory selectors = AllMethodIdentifiersTest.getAllMethodIdentifiers(vm, getAbiPath());

    assertGt(selectors.length, 0, "Some functions should be loaded");

    for (uint i = 0; i < selectors.length; i++) {
      // Assert that all are called - to decode the selector search in the abi file
      vm.expectCall(address(kdl), selectors[i]);
    }

    // Act/assert - invoke all functions - if any are missing, add them.

    // No auth
    kdl.BASE();
    kdl.MGV();
    kdl.NO_ROUTER();
    kdl.OFFER_GASREQ();
    kdl.PRECISION();
    kdl.QUOTE();
    kdl.RESERVE_ID();
    kdl.admin();
    kdl.checkList(new IERC20[](0));
    kdl.getOffer(Ask, 0);
    kdl.indexOfOfferId(Ask, 42);
    kdl.offerIdOfIndex(Ask, 0);
    kdl.offerGasreq();
    kdl.offeredVolume(Ask);
    kdl.params();
    kdl.pending(Ask);
    kdl.reserveBalance(Ask);
    kdl.provisionOf(base, quote, 0);
    kdl.router();

    GeometricKandel.Distribution memory dist;
    CheckAuthArgs memory args;
    args.callee = $(kdl);
    args.callers = dynamic([address($(mgv)), maker, $(this)]);
    args.revertMessage = "AccessControlled/Invalid";

    // Only admin
    args.allowed = dynamic([address(maker)]);
    checkAuth(args, abi.encodeCall(kdl.activate, dynamic([IERC20(base)])));
    checkAuth(args, abi.encodeCall(kdl.approve, (base, taker, 42)));
    checkAuth(args, abi.encodeCall(kdl.setAdmin, (maker)));
    checkAuth(args, abi.encodeCall(kdl.setGasprice, (42)));
    checkAuth(args, abi.encodeCall(kdl.setGasreq, (42)));
    checkAuth(args, abi.encodeCall(kdl.setRouter, (kdl.router())));
    checkAuth(args, abi.encodeCall(kdl.populateChunk, (dist, new uint[](0), 42)));
    checkAuth(args, abi.encodeCall(kdl.retractOffers, (0, 0)));
    checkAuth(args, abi.encodeCall(kdl.withdrawFromMangrove, (0, maker)));
    checkAuth(args, abi.encodeCall(kdl.setCompoundRates, (0, 0)));
    GeometricKandel.Params memory p;
    p.ratio = 10 ** 5;
    p.spread = 1;
    checkAuth(args, abi.encodeCall(kdl.setParams, (p)));

    // Only Mgv
    MgvLib.OrderResult memory oResult = MgvLib.OrderResult({makerData: bytes32(0), mgvData: ""});
    args.allowed = dynamic([address($(mgv))]);
    checkAuth(args, abi.encodeCall(kdl.makerExecute, mockBuyOrder(1, 1)));
    checkAuth(args, abi.encodeCall(kdl.makerPosthook, (mockBuyOrder(1, 1), oResult)));
  }
}