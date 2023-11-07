// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import {OfferData} from "@mgv/test/lib/agents/TestMaker.sol";
import "@mgv/src/core/MgvLib.sol";
import {Density, DensityLib} from "@mgv/lib/core/DensityLib.sol";

contract TestMonitor is IMgvMonitor {
  function notifySuccess(MgvLib.SingleOrder calldata sor, address taker) external {}

  function notifyFail(MgvLib.SingleOrder calldata sor, address taker) external {}

  function read(OLKey memory olKey) external pure returns (uint gasprice, Density density) {
    olKey; // shh
    gasprice = 40;
    density = Density.wrap(2 ** 32);
  }
}

contract MakerOperationsTest is MangroveTest, IMaker {
  TestMaker mkr;
  TestMaker mkr2;
  TestTaker tkr;
  TestMonitor monitor;
  Local localCopy;
  Global globalCopy;

  function setUp() public override {
    super.setUp();

    mkr = setupMaker(olKey, "maker");
    mkr2 = setupMaker(olKey, "maker2");
    tkr = setupTaker(olKey, "taker");

    mkr.approveMgv(base, 10 ether);
    mkr2.approveMgv(base, 10 ether);

    deal($(quote), address(tkr), 1 ether);
    tkr.approveMgv(quote, 1 ether);
  }

  // checks that exactly the right SOR fields are hidden from maker
  function assertSORFieldsFilteredCorrectly(MgvLib.SingleOrder calldata order) public {
    // OLKey is not filtered
    assertEq(order.olKey.outbound_tkn, $(base), "olKey.base should not be hidden");
    assertEq(order.olKey.inbound_tkn, $(quote), "olKey.quote should not be hidden");
    assertEq(order.olKey.tickSpacing, olKey.tickSpacing, "olKey.tickSpacing should not be hidden");

    // Offer is partially filtered
    //   hidden
    assertEq(order.offer.prev(), 0, "offer.prev should be hidden");
    assertEq(order.offer.next(), 0, "offer.next should be hidden");
    //   not hidden
    assertEq(order.offer.tick(), Tick.wrap(1), "offer.tick should not be hidden");
    assertEq(order.offer.gives(), 1 ether, "offer.gives should not be hidden");

    // OfferDetail is not filtered
    assertEq(order.offerDetail.maker(), $(mkr), "offerDetail.maker should not be hidden");
    assertEq(order.offerDetail.gasprice(), globalCopy.gasprice(), "offerDetail.gasprice should not be hidden");
    assertEq(
      order.offerDetail.kilo_offer_gasbase(),
      localCopy.kilo_offer_gasbase(),
      "offerDetail.kilo_offer_gasbase should not be hidden"
    );
    assertEq(order.offerDetail.gasreq(), 200_000, "offerDetail.gasreq should not be hidden");

    // wants and gives are not filtered
    assertEq(order.takerWants, 0.1 ether, "wants should not be hidden");
    assertEq(order.takerGives, 0.10001 ether, "gives should not be hidden");

    // Gloabl is not filtered
    assertEq(order.global.monitor(), address(monitor), "global.monitor should not be hidden");
    assertTrue(order.global.useOracle(), "global.useOracle should not be hidden");
    assertTrue(order.global.notify(), "global.notify should not be hidden");
    assertEq(order.global.gasprice(), globalCopy.gasprice(), "global.gasprice should not be hidden");
    assertEq(order.global.gasmax(), globalCopy.gasmax(), "global.gasmax should not be hidden");
    assertFalse(order.global.dead(), "global.dead should not be hidden");

    // Local is partially filtered
    //   hidden
    assertEq(order.local.binPosInLeaf(), 0, "binPosInLeaf should be hidden");
    assertEq(order.local.level3(), FieldLib.EMPTY, "level3 should be hidden");
    assertEq(order.local.level2(), FieldLib.EMPTY, "level2 should be hidden");
    assertEq(order.local.level1(), FieldLib.EMPTY, "level1 should be hidden");
    assertEq(order.local.last(), 0, "last should be hidden");
    //   not hidden
    assertTrue(order.local.active(), "active should not be hidden");
    assertEq(order.local.fee(), localCopy.fee(), "fee should not be hidden");
    assertTrue(order.local.density().eq(localCopy.density()), "density should not be hidden");
    assertEq(
      order.local.kilo_offer_gasbase(), localCopy.kilo_offer_gasbase(), "kilo_offer_gasbase should not be hidden"
    );
    assertTrue(order.local.lock(), "lock should not be hidden");
  }

  function test_fields_are_hidden_correctly_in_makerExecute() public {
    monitor = new TestMonitor();
    mgv.setMonitor(address(monitor));
    mgv.setUseOracle(true);
    mgv.setNotify(true);
    mgv.setFee(olKey, 1);
    localCopy = mgv.local(olKey);
    globalCopy = mgv.global();

    mkr.provisionMgv(1 ether);
    mkr.setExecuteCallback($(this), this.assertSORFieldsFilteredCorrectly.selector);
    deal($(base), $(mkr), 1 ether);

    uint ofr = mkr.newOfferByTick(Tick.wrap(1), 1 ether, 200_000);
    require(tkr.marketOrderWithSuccess(0.1 ether), "take must work or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
  }

  function test_fund_maker_fn(address anyone, uint64 amount) public {
    uint oldBal = mgv.balanceOf(address(anyone));
    mgv.fund{value: amount}(anyone);
    uint newBal = mgv.balanceOf(address(anyone));
    assertEq(newBal, oldBal + amount);
  }

  function test_fund_fn(uint64 amount) public {
    uint oldBal = mgv.balanceOf(address(this));
    mgv.fund{value: amount}();
    uint newBal = mgv.balanceOf(address(this));
    assertEq(newBal, oldBal + amount);
  }

  function test_provision_adds_mgv_balance_and_ethers() public {
    uint mgv_bal = $(mgv).balance;
    uint amt1 = 235;
    uint amt2 = 1.3 ether;

    mkr.provisionMgv(amt1);

    assertEq(mkr.mgvBalance(), amt1, "incorrect mkr mgvBalance amount (1)");
    assertEq($(mgv).balance, mgv_bal + amt1, "incorrect mgv ETH balance (1)");

    mkr.provisionMgv(amt2);

    assertEq(mkr.mgvBalance(), amt1 + amt2, "incorrect mkr mgvBalance amount (2)");
    assertEq($(mgv).balance, mgv_bal + amt1 + amt2, "incorrect mgv ETH balance (2)");
  }

  // since we check calldata, execute must be internal
  function makerExecute(MgvLib.SingleOrder calldata order) external returns (bytes32 ret) {
    ret; // silence unused function parameter warning
    uint num_args = 10; // UPDATE IF SIZE OF SingleOrder changes
    uint selector_bytes = 4;
    uint length = selector_bytes + num_args * 32;
    assertEq(msg.data.length, length, "calldata length in execute is incorrect");

    assertEq(order.olKey.outbound_tkn, $(base), "wrong base");
    assertEq(order.olKey.inbound_tkn, $(quote), "wrong quote");
    assertEq(order.olKey.tickSpacing, olKey.tickSpacing, "wrong tickspacing");
    assertEq(order.takerWants, 0.05 ether, "wrong takerWants");
    assertEq(order.takerGives, 0.05 ether, "wrong takerGives");
    assertEq(order.offerDetail.gasreq(), 200_000, "wrong gasreq");
    assertEq(order.offerId, 1, "wrong offerId");
    assertEq(order.offer.wants(), 0.05 ether, "wrong offerWants");
    assertEq(order.offer.gives(), 0.05 ether, "wrong offerGives");
    // test flashloan
    assertEq(quote.balanceOf($(mkr)), 0.05 ether, "wrong quote balance");
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external {}

  function test_calldata_and_balance_in_makerExecute_are_correct() public {
    mkr.provisionMgv(1 ether);
    mkr.setExecuteCallback($(this), this.makerExecute.selector);
    deal($(base), $(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(olKey, 0.05 ether, 0.05 ether, 200_000);
    require(tkr.marketOrderWithSuccess(0.05 ether), "take must work or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
  }

  function test_withdraw_removes_mgv_balance_and_ethers() public {
    uint mgv_bal = $(mgv).balance;
    uint amt1 = 0.86 ether;
    uint amt2 = 0.12 ether;

    mkr.provisionMgv(amt1);
    bool success = mkr.withdrawMgv(amt2);
    assertTrue(success, "mkr was not able to withdraw from mgv");
    assertEq(mkr.mgvBalance(), amt1 - amt2, "incorrect mkr mgvBalance amount");
    assertEq($(mgv).balance, mgv_bal + amt1 - amt2, "incorrect mgv ETH balance");
  }

  function test_withdraw_too_much_fails() public {
    uint amt1 = 6.003 ether;
    mkr.provisionMgv(amt1);
    vm.expectRevert("mgv/insufficientProvision");
    mkr.withdrawMgv(amt1 + 1);
  }

  function test_newOffer_without_mgv_balance_fails() public {
    vm.expectRevert("mgv/insufficientProvision");
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
  }

  function test_fund_newOffer() public {
    uint oldBal = mgv.balanceOf(address(mkr));
    expectFrom($(mgv));
    emit Credit(address(mkr), 1 ether);
    mkr.newOfferByVolumeWithFunding(1 ether, 1 ether, 100_000, 0, 1 ether);
    assertGt(mgv.balanceOf(address(mkr)), oldBal, "balance should have increased");
  }

  function test_fund_updateOffer() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    expectFrom($(mgv));
    emit Credit(address(mkr), 0.9 ether);
    mkr.updateOfferByVolumeWithFunding(1 ether, 1 ether, 100_000, ofr, 0.9 ether);
  }

  function test_posthook_fail_message() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);

    mkr.setShouldFailHook(true);
    expectFrom($(mgv));
    emit OfferSuccessWithPosthookData(olKey.hash(), $(tkr), ofr, 0.1 ether, 0.1 ether, "posthookFail");
    tkr.marketOrderWithSuccess(0.1 ether); // fails but we don't care
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
  }

  function test_returnData_succeeds() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr =
      mkr.newOfferByVolume(1 ether, 1 ether, 100_000, OfferData({shouldRevert: false, executeData: "someData"}));

    bool success = tkr.marketOrderWithSuccess(0.1 ether);
    assertTrue(success, "market order should work");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
  }

  function test_delete_restores_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.mgvBalance(); // should be 1 ether
    uint offerId = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    uint _bal = mkr.mgvBalance(); // 1 ether minus provision
    uint collected = mkr.retractOfferWithDeprovision(offerId); // provision
    assertEq(bal - _bal, collected, "retract does not return a correct amount");
    assertEq(mkr.mgvBalance(), bal, "delete has not restored balance");
  }

  function test_delete_offer_log() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(mkr), ofr, true);
    mkr.retractOfferWithDeprovision(ofr);
  }

  function test_retract_retracted_does_not_drain() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 10_000, 0);

    mkr.retractOffer(ofr);

    uint bal1 = mgv.balanceOf(address(mkr));
    uint collected = mkr.retractOfferWithDeprovision(ofr);
    assertTrue(collected > 0, "deprovision should give credit");
    uint bal2 = mgv.balanceOf(address(mkr));
    assertLt(bal1, bal2, "Balance should have increased");

    uint collected2 = mkr.retractOfferWithDeprovision(ofr);
    assertTrue(collected2 == 0, "second deprovision should not give credit");
    uint bal3 = mgv.balanceOf(address(mkr));
    assertEq(bal3, bal2, "Balance should not have increased");
  }

  function test_retract_taken_does_not_drain() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);

    bool success = tkr.marketOrderWithSuccess(0.1 ether);
    assertEq(success, true, "market order should succeed");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");

    uint bal1 = mgv.balanceOf(address(mkr));
    mkr.retractOfferWithDeprovision(ofr);
    uint bal2 = mgv.balanceOf(address(mkr));
    assertLt(bal1, bal2, "Balance should have increased");

    uint collected = mkr.retractOfferWithDeprovision(ofr);
    assertTrue(collected == 0, "second deprovision should not give credit");
    uint bal3 = mgv.balanceOf(address(mkr));
    assertEq(bal3, bal2, "Balance should not have increased");
  }

  function test_retract_offer_log() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(0.9 ether, 1 ether, 2300, 100);
    expectFrom($(mgv));
    emit OfferRetract(olKey.hash(), $(mkr), ofr, false);
    mkr.retractOffer(ofr);
  }

  function test_retract_offer_maintains_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.mgvBalance();
    uint prov = reader.getProvision(olKey, 2300, 0);
    mkr.retractOffer(mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0));
    assertEq(mkr.mgvBalance(), bal - prov, "unexpected maker balance");
  }

  function test_retract_middle_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(0.9 ether, 1 ether, 2300, 100);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 2300, 100);

    mkr.retractOffer(ofr);
    assertTrue(!mgv.offers(olKey, ofr).isLive(), "Offer was not removed from OB");
    Offer offer = mgv.offers(olKey, ofr);
    OfferDetail detail = mgv.offerDetails(olKey, ofr);

    assertEq(reader.prevOfferId(olKey, offer), ofr0, "Invalid prev");
    assertEq(reader.nextOfferId(olKey, offer), ofr1, "Invalid next");
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    assertEq(detail.gasprice(), 100, "offer gasprice is incorrect");

    assertTrue(mgv.offers(olKey, reader.prevOfferId(olKey, offer)).isLive(), "Invalid OB");
    assertTrue(mgv.offers(olKey, reader.nextOfferId(olKey, offer)).isLive(), "Invalid OB");
    Offer offer0 = mgv.offers(olKey, reader.prevOfferId(olKey, offer));
    Offer offer1 = mgv.offers(olKey, reader.nextOfferId(olKey, offer));

    assertEq(reader.prevOfferId(olKey, offer1), ofr0, "Invalid stitching for ofr1");
    assertEq(reader.nextOfferId(olKey, offer0), ofr1, "Invalid stitching for ofr0");
  }

  function test_retract_best_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    assertTrue(!mgv.offers(olKey, ofr).isLive(), "Offer was not removed from OB");
    Offer offer = mgv.offers(olKey, ofr);
    OfferDetail detail = mgv.offerDetails(olKey, ofr);
    assertEq(reader.prevOfferId(olKey, offer), 0, "Invalid prev");
    assertEq(reader.nextOfferId(olKey, offer), ofr1, "Invalid next");
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    assertEq(detail.gasprice(), 100, "offer gasprice is incorrect");

    assertTrue(mgv.offers(olKey, reader.nextOfferId(olKey, offer)).isLive(), "Invalid OB");
    Offer offer1 = mgv.offers(olKey, reader.nextOfferId(olKey, offer));
    assertEq(reader.prevOfferId(olKey, offer1), 0, "Invalid stitching for ofr1");
    assertEq(mgv.best(olKey), ofr1, "Invalid best after retract");
  }

  function test_retract_worst_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr0 = mkr.newOfferByVolume(0.9 ether, 1 ether, 2300, 100);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer was not removed from OB");
    mkr.retractOffer(ofr);
    Offer offer = mgv.offers(olKey, ofr);
    // note: a former version of this test was checking reader.prevOfferId(olKey,offer) and offer.next () but:
    // 1. There is no spec of what prev() next() are for a non-live offer (nor of what prev/nextOffer are)
    // 2. prev() and next() are not meaningful with tick trees
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    Offer offer0 = mgv.offers(olKey, ofr0);
    assertTrue(offer0.isLive(), "Invalid OB");
    assertEq(reader.nextOfferId(olKey, offer0), 0, "Invalid stitching for ofr0");
    assertEq(mgv.best(olKey), ofr0, "Invalid best after retract");
  }

  function test_delete_wrong_offer_fails() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    vm.expectRevert("mgv/retractOffer/unauthorized");
    mkr2.retractOfferWithDeprovision(ofr);
  }

  function test_retract_wrong_offer_fails() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    vm.expectRevert("mgv/retractOffer/unauthorized");
    mkr2.retractOffer(ofr);
  }

  function test_gasreq_max_with_newOffer_ok() public {
    mkr.provisionMgv(1 ether);
    uint gasmax = 750000;
    mgv.setGasmax(gasmax);
    mkr.newOfferByVolume(1 ether, 1 ether, gasmax, 0);
  }

  function test_gasreq_too_high_fails_newOffer() public {
    uint gasmax = 12;
    mgv.setGasmax(gasmax);
    vm.expectRevert("mgv/writeOffer/gasreq/tooHigh");
    mkr.newOfferByVolume(1 ether, 1 ether, gasmax + 1, 0);
  }

  function test_min_density_with_newOffer_ok() public {
    mkr.provisionMgv(1 ether);
    uint density96X32 = (10 ** 7) << 32;
    mgv.setGasbase(olKey, 1);
    mgv.setDensity96X32(olKey, density96X32);
    mkr.newOfferByVolume(1 ether, DensityLib.from96X32(density96X32).multiply(1), 0, 0);
  }

  function test_low_density_fails_newOffer() public {
    uint density96X32 = (10 ** 7) << 32;
    mgv.setGasbase(olKey, 1000);
    mgv.setDensity96X32(olKey, density96X32);
    vm.expectRevert("mgv/writeOffer/density/tooLow");
    mkr.newOfferByVolume(1 ether, DensityLib.from96X32(density96X32).multiply(1000) - 1, 0, 0);
  }

  function test_maker_gets_no_mgv_balance_on_partial_fill() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.marketOrderWithSuccess(0.1 ether);
    assertTrue(success, "market order must succeed");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(mgv.balanceOf(address(mkr)), oldBalance, "mkr balance must not change");
  }

  function test_maker_gets_no_mgv_balance_on_full_fill() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.marketOrderWithSuccess(1 ether);
    assertTrue(success, "take must succeed");
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(mgv.balanceOf(address(mkr)), oldBalance, "mkr balance must not change");
  }

  function test_insertions_are_correctly_ordered() public {
    mkr.provisionMgv(10 ether);
    uint ofr2 = mkr.newOfferByVolume(1.1 ether, 1 ether, 100_000, 0);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 50_000, 0);
    uint ofr01 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    assertTrue(mgv.offers(olKey, ofr0).isLive(), "Oldest equivalent offer should be first");
    Offer offer = mgv.offers(olKey, ofr0);
    uint _ofr01 = reader.nextOfferId(olKey, offer);
    assertEq(_ofr01, ofr01, "Wrong 2nd offer");
    assertTrue(mgv.offers(olKey, _ofr01).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers(olKey, _ofr01);
    uint _ofr2 = reader.nextOfferId(olKey, offer);
    assertEq(_ofr2, ofr2, "Wrong 3rd offer");
    assertTrue(mgv.offers(olKey, _ofr2).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers(olKey, _ofr2);
    uint _ofr1 = reader.nextOfferId(olKey, offer);
    assertEq(_ofr1, ofr1, "Wrong 4th offer");
    assertTrue(mgv.offers(olKey, _ofr1).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers(olKey, _ofr1);
    assertEq(reader.nextOfferId(olKey, offer), 0, "Invalid OB");
  }

  // insertTest ratio, density (gives/gasreq) vs (gives'/gasreq'), age
  // nolongerBest
  // idemRatio
  // idemBest
  // A.BCD --> ABC.D

  function test_update_offer_resets_age_and_updates_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_000, ofr0);
    assertEq(ofr1, mgv.best(olKey), "Best offer should have changed");
  }

  function test_update_offer_ratio_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether + 1, 1.0 ether, 100_000, ofr0);
    assertEq(ofr1, mgv.best(olKey), "Best offer should have changed");
  }

  function test_update_offer_density_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_001, ofr0);
    assertEq(ofr1, mgv.best(olKey), "Best offer should have changed");
  }

  // before ticks: worsening an offer's density keeps it in best position if it still has the best density
  // after ticks: improving an offer's density does not make it best
  function test_update_offer_density_does_not_become_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1.0 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 99_999, ofr1);
    logOrderBook(olKey, 2);
    assertEq(mgv.best(olKey), ofr0, "Best offer should not have changed");
  }

  function test_update_offer_ratio_changes_prevnext() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOfferByVolume(1.2 ether, 1 ether, 100_000, 0);

    assertTrue(mgv.offers(olKey, ofr).isLive(), "Insertion error");
    Offer offer = mgv.offers(olKey, ofr);
    assertEq(reader.prevOfferId(olKey, offer), ofr0, "Wrong prev offer");
    assertEq(reader.nextOfferId(olKey, offer), ofr1, "Wrong next offer");
    mkr.updateOfferByVolume(1.1 ether, 1.0 ether, 100_000, ofr);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Insertion error");
    offer = mgv.offers(olKey, ofr);
    assertEq(reader.prevOfferId(olKey, offer), ofr2, "Wrong prev offer after update");
    assertEq(reader.nextOfferId(olKey, offer), ofr3, "Wrong next offer after update");
  }

  function test_update_offer_density_changes_prevnext() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_002, 0);

    assertTrue(mgv.offers(olKey, ofr).isLive(), "Insertion error");
    Offer offer = mgv.offers(olKey, ofr);
    assertEq(reader.prevOfferId(olKey, offer), ofr0, "Wrong prev offer");
    assertEq(reader.nextOfferId(olKey, offer), ofr1, "Wrong next offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_001, ofr);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "Update error");
    offer = mgv.offers(olKey, ofr);
    assertEq(reader.prevOfferId(olKey, offer), ofr3, "Wrong prev offer after update");
    assertEq(reader.nextOfferId(olKey, offer), 0, "Wrong next offer after update");
  }

  function test_update_offer_after_higher_gasprice_change_fails() public {
    uint provision = reader.getProvision(olKey, 100_000, 0);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    (Global cfg,) = mgv.config(olKey);
    mgv.setGasprice(cfg.gasprice() + 1); //gasprice goes up
    vm.expectRevert("mgv/insufficientProvision");
    mkr.updateOfferByVolume(1.0 ether + 2, 1.0 ether, 100_000, ofr0);
  }

  function test_update_offer_after_higher_gasprice_change_succeeds_when_over_provisioned() public {
    (Global cfg,) = mgv.config(olKey);
    uint gasprice = cfg.gasprice();
    uint provision = reader.getProvision(olKey, 100_000, gasprice);
    expectFrom($(mgv));
    emit Credit(address(mkr), provision * 2);
    mkr.provisionMgv(provision * 2); // provisionning twice the required amount
    expectFrom($(mgv));
    emit OfferWrite(
      olKey.hash(),
      address(mkr),
      0, //tick
      1.0 ether,
      gasprice, // offer at old gasprice
      100_000,
      1
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), provision); // transfering missing provision into offer bounty
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0); // locking exact bounty
    mgv.setGasprice(gasprice + 1); //gasprice goes up
    uint _provision = reader.getProvision(olKey, 100_000, gasprice + 1); // new theoretical provision
    (cfg,) = mgv.config(olKey);
    expectFrom($(mgv));
    emit OfferWrite(
      olKey.hash(),
      address(mkr),
      0, //tick
      1.0 ether,
      cfg.gasprice(), // offer gasprice should be the new gasprice
      100_000,
      ofr0
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), _provision - provision); // transfering missing provision into offer bounty
    mkr.updateOfferByVolume(1.0 ether + 2, 1.0 ether, 100_000, ofr0);
  }

  function test_update_offer_after_lower_gasprice_change_succeeds() public {
    uint provision = reader.getProvision(olKey, 100_000, 0);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    (Global cfg,) = mgv.config(olKey);
    mgv.setGasprice(cfg.gasprice() - 1); //gasprice goes down
    uint _provision = reader.getProvision(olKey, 100_000, 0);
    expectFrom($(mgv));
    emit Credit(address(mkr), provision - _provision);
    mkr.updateOfferByVolume(1.0 ether + 2, 1.0 ether, 100_000, ofr0);
    assertEq(mgv.balanceOf(address(mkr)), provision - _provision, "Maker balance is incorrect");
  }

  function test_update_offer_next_to_itself_does_not_break_ob() public {
    mkr.provisionMgv(1 ether);
    uint left = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOfferByVolume(1 ether + 0.03 ether, 1 ether, 100_000, 0);
    uint center = mkr.newOfferByVolume(1 ether + 0.01 ether, 1 ether, 100_000, 0);
    assertEq(reader.prevOfferId(olKey, mgv.offers(olKey, center)), left, "wrong initial prev for center");
    assertEq(reader.nextOfferId(olKey, mgv.offers(olKey, center)), right, "wrong initial next for center");
    mkr.updateOfferByVolume(1 ether + 0.02 ether, 1 ether, 100_000, center);
    Offer ofr = mgv.offers(olKey, center);
    assertEq(reader.prevOfferId(olKey, ofr), left, "ofr.prev should be unchanged");
    assertEq(reader.nextOfferId(olKey, ofr), right, "ofr.next should be unchanged");
  }

  function test_update_on_retracted_offer() public {
    uint provision = reader.getProvision(olKey, 100_000, 0);
    mkr.provisionMgv(provision);
    uint offerId = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.retractOfferWithDeprovision(offerId);
    mkr.withdrawMgv(provision);
    assertEq(mgv.balanceOf(address(mkr)), 0, "Maker should have no more provision on Mangrove");
    Offer ofr = mgv.offers(olKey, offerId);
    OfferDetail dtl = mgv.offerDetails(olKey, offerId);
    assertEq(ofr.gives(), 0, "Retracted offer should have 0 gives");
    assertEq(dtl.gasprice(), 0, "Deprovisioned offer should have 0 gasprice");
    vm.expectRevert("mgv/insufficientProvision");
    mkr.updateOfferByVolume(1 ether + 2, 1 ether, 100_000, offerId);
    mkr.provisionMgv(provision);
    mkr.updateOfferByVolume(1 ether + 2, 1 ether, 100_000, offerId);
    ofr = mgv.offers(olKey, offerId);
    assertEq(ofr.gives(), 1 ether, "Offer not correctly updated");
  }

  function testOBBest(uint id) internal {
    Offer ofr = mgv.offers(olKey, id);
    assertEq(mgv.best(olKey), id, "testOBBest: not best");
    assertEq(reader.prevOfferId(olKey, ofr), 0, "testOBBest: prev not 0");
  }

  function testOBWorst(uint id) internal {
    Offer ofr = mgv.offers(olKey, id);
    assertEq(reader.nextOfferId(olKey, ofr), 0, "testOBWorst fail");
  }

  function testOBLink(uint left, uint right) internal {
    Offer ofr = mgv.offers(olKey, left);
    assertEq(reader.nextOfferId(olKey, ofr), right, "testOBLink: wrong ofr.next");
    ofr = mgv.offers(olKey, right);
    assertEq(reader.prevOfferId(olKey, ofr), left, "testOBLink: wrong ofr.prev");
  }

  function testOBOrder(uint[1] memory ids) internal {
    testOBBest(ids[0]);
    testOBWorst(ids[0]);
  }

  function testOBOrder(uint[2] memory ids) internal {
    testOBBest(ids[0]);
    testOBLink(ids[0], ids[1]);
    testOBWorst(ids[1]);
  }

  function testOBOrder(uint[3] memory ids) internal {
    testOBBest(ids[0]);
    testOBLink(ids[0], ids[1]);
    testOBLink(ids[1], ids[2]);
    testOBWorst(ids[2]);
  }

  function test_complex_offer_update_left_1_1() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    mkr.updateOfferByVolume(x + 0.001 ether, x, g, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_1() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    mkr.updateOfferByVolume(x + 0.001 ether, x, g, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_left_1_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 3, x, g, 0);
    mkr.updateOfferByVolume(x + 5, x, g, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_1_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    mkr.updateOfferByVolume(x + 0.005 ether, x, g, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_left_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    uint three = mkr.newOfferByVolume(x + 0.005 ether, x, g, 0);
    mkr.updateOfferByVolume(x + 0.001 ether, x, g, three);

    testOBOrder([one, three, two]);
  }

  function test_complex_offer_update_right_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    uint three = mkr.newOfferByVolume(x + 0.005 ether, x, g, 0);
    mkr.updateOfferByVolume(x + 0.004 ether, x, g, one);

    testOBOrder([two, one, three]);
  }

  function test_complex_offer_update_left_3() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    mkr.retractOffer(two);
    mkr.updateOfferByVolume(x + 0.003 ether, x, g, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_3() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOfferByVolume(x, x, g, 0);
    uint two = mkr.newOfferByVolume(x + 0.003 ether, x, g, 0);
    mkr.retractOffer(one);
    mkr.updateOfferByVolume(x, x, g, one);

    testOBOrder([one, two]);
  }

  function test_update_offer_prev_to_itself_does_not_break_ob() public {
    mkr.provisionMgv(1 ether);
    uint left = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOfferByVolume(1 ether + 0.03 ether, 1 ether, 100_000, 0);
    uint center = mkr.newOfferByVolume(1 ether + 0.02 ether, 1 ether, 100_000, 0);
    assertEq(reader.prevOfferId(olKey, mgv.offers(olKey, center)), left, "wrong initial prev for center");
    assertEq(reader.nextOfferId(olKey, mgv.offers(olKey, center)), right, "wrong initial next for center");
    mkr.updateOfferByVolume(1 ether + 0.01 ether, 1 ether, 100_000, center);
    Offer ofr = mgv.offers(olKey, center);
    assertEq(reader.prevOfferId(olKey, ofr), left, "ofr.prev should be unchanged");
    assertEq(reader.nextOfferId(olKey, ofr), right, "ofr.next should be unchanged");
  }

  function test_update_offer_ratio_stays_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1.0 ether + 0.02 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether + 0.01 ether, 1.0 ether, 100_000, ofr0);
    // csl.log(mgv.offers(olKey,ofr0).bin().toString());
    assertEq(ofr0, mgv.best(olKey), "Best offer should not have changed");
  }

  // before ticks: worsening an offer's density keeps it in best position if it still has the best density
  // after ticks: even improving an offer's density makes it last of its tick
  function test_update_offer_density_becomes_last() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_002, 0);
    uint ofr2 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_003, 0);
    assertEq(ofr0, mgv.best(olKey), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 99_000, ofr0);
    assertEq(mgv.best(olKey), ofr1, "Best offer should have changed");
    assertEq(reader.nextOfferIdById(olKey, ofr2), ofr0, "ofr0 should come after ofr2");
    assertEq(reader.nextOfferIdById(olKey, ofr0), 0, "ofr0 should be last");
  }

  function test_gasbase_is_deducted_1() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase(olKey, offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensity96X32(olKey, 0);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    tkr.clean(ofr, 0.1 ether);
    assertEq(mgv.balanceOf(address(mkr)), 1 ether - offer_gasbase * 1e6, "Wrong gasbase deducted");
  }

  function test_gasbase_is_deducted_2() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase(olKey, offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensity96X32(olKey, 0);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    tkr.clean(ofr, 0.1 ether);
    assertEq(mgv.balanceOf(address(mkr)), 1 ether - offer_gasbase * 1e6, "Wrong gasbase deducted");
  }

  function test_penalty_gasprice_is_mgv_gasprice() public {
    mgv.setGasprice(10);
    mkr.shouldFail(true);
    mkr.provisionMgv(1 ether);
    mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint oldProvision = mgv.balanceOf(address(mkr));
    mgv.setGasprice(10000);
    (uint gave, uint got) = tkr.marketOrder(1 ether, 1 ether);
    assertTrue(gave == got && got == 0, "market Order should be noop");
    uint gotBack = mgv.balanceOf(address(mkr)) - oldProvision;
    assertEq(gotBack, 0, "Should not have gotten any provision back");
  }

  function test_offer_gasbase_conversion() public {
    // Local, packed
    Local local;
    local = local.offer_gasbase(1900);
    assertEq(local.kilo_offer_gasbase(), 1, "local,packed: wrong kilo_offer_gasbase");
    assertEq(local.offer_gasbase(), 1000, "local,packed: wrong offer_gasbase");
    local = local.offer_gasbase(230_082);
    assertEq(local.kilo_offer_gasbase(), 230, "local,packed: wrong kilo_offer_gasbase");
    assertEq(local.offer_gasbase(), 230_000, "local,packed: wrong offer_gasbase");
    local = local.kilo_offer_gasbase(31);
    assertEq(local.offer_gasbase(), 31000, "local,packed: wrong offer_gasbase");
    local = local.kilo_offer_gasbase(12);
    assertEq(local.offer_gasbase(), 12000, "local,packed: wrong offer_gasbase");

    // Local, unpacked
    LocalUnpacked memory u_local;
    u_local.offer_gasbase(1900);
    assertEq(u_local.kilo_offer_gasbase, 1, "local,unpacked: wrong kilo_offer_gasbase");
    assertEq(u_local.offer_gasbase(), 1000, "local,unpacked: wrong offer_gasbase");
    u_local.offer_gasbase(230_082);
    assertEq(u_local.kilo_offer_gasbase, 230, "local,unpacked: wrong kilo_offer_gasbase");
    assertEq(u_local.offer_gasbase(), 230_000, "local,unpacked: wrong offer_gasbase");
    u_local.kilo_offer_gasbase = 31;
    assertEq(u_local.offer_gasbase(), 31000, "local,unpacked: wrong offer_gasbase");
    u_local.kilo_offer_gasbase = 12;
    assertEq(u_local.offer_gasbase(), 12000, "local,unpacked: wrong offer_gasbase");

    // OfferDetail, packed
    OfferDetail offerDetail;
    offerDetail = offerDetail.offer_gasbase(1900);
    assertEq(offerDetail.kilo_offer_gasbase(), 1, "offerDetail,packed: wrong kilo_offer_gasbase");
    assertEq(offerDetail.offer_gasbase(), 1000, "offerDetail,packed: wrong offer_gasbase");
    offerDetail = offerDetail.offer_gasbase(230_082);
    assertEq(offerDetail.kilo_offer_gasbase(), 230, "offerDetail,packed: wrong kilo_offer_gasbase");
    assertEq(offerDetail.offer_gasbase(), 230_000, "offerDetail,packed: wrong offer_gasbase");
    offerDetail = offerDetail.kilo_offer_gasbase(31);
    assertEq(offerDetail.offer_gasbase(), 31000, "offerDetail,packed: wrong offer_gasbase");
    offerDetail = offerDetail.kilo_offer_gasbase(12);
    assertEq(offerDetail.offer_gasbase(), 12000, "offerDetail,packed: wrong offer_gasbase");

    // OfferDetail, unpacked
    OfferDetailUnpacked memory u_offerDetail;
    u_offerDetail.offer_gasbase(1900);
    assertEq(u_offerDetail.kilo_offer_gasbase, 1, "offerDetail,unpacked: wrong kilo_offer_gasbase");
    assertEq(u_offerDetail.offer_gasbase(), 1000, "offerDetail,unpacked: wrong offer_gasbase");
    u_offerDetail.offer_gasbase(230_082);
    assertEq(u_offerDetail.kilo_offer_gasbase, 230, ": wrong kilo_offer_gasbase");
    assertEq(u_offerDetail.offer_gasbase(), 230_000, "offerDetail,unpacked: wrong offer_gasbase");
    u_offerDetail.kilo_offer_gasbase = 31;
    assertEq(u_offerDetail.offer_gasbase(), 31000, "offerDetail,unpacked: wrong offer_gasbase");
    u_offerDetail.kilo_offer_gasbase = 12;
    assertEq(u_offerDetail.offer_gasbase(), 12000, "offerDetail,unpacked: wrong offer_gasbase");
  }

  function test_update_branch_on_retract_posInLeaf() public {
    mkr.provisionMgv(10 ether);
    uint wants = 5 ether;
    mkr.newOfferByVolume(wants, Tick.wrap(3).outboundFromInbound(wants), 100_000, 0);
    uint posInLeaf = mgv.local(olKey).binPosInLeaf();
    uint ofr = mkr.newOfferByVolume(wants, Tick.wrap(2).outboundFromInbound(wants), 100_000, 0);
    assertGt(
      posInLeaf, mgv.local(olKey).binPosInLeaf(), "test void if posInLeaf does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(posInLeaf, mgv.local(olKey).binPosInLeaf(), "posInLeaf should have been restored");
  }

  function test_update_branch_on_retract_level3() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level3 = mgv.local(olKey).level3();
    int level3Index = mgv.local(olKey).bestBin().level3Index();
    uint ofr = mkr.newOfferByVolume(1 ether, 10 ether, 100_000, 0);
    assertGt(
      level3Index,
      mgv.local(olKey).bestBin().level3Index(),
      "test void if level3 does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(level3, mgv.local(olKey).level3(), "level3 should have been restored");
  }

  // function test_firstOffer_fuzz_ratio() public {
  //   mkr.provisionMgv(10 ether);
  //   uint ofr = mkr.newOfferByTick(300_000, 0.0001 ether, 100_000, 0);
  // }

  function test_update_branch_on_retract_level2() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level2 = mgv.local(olKey).level2();
    int level2Index = mgv.local(olKey).bestBin().level2Index();
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    assertGt(
      level2Index,
      mgv.local(olKey).bestBin().level2Index(),
      "test void if level2 does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(level2, mgv.local(olKey).level2(), "level2 should have been restored");
  }

  function test_update_branch_on_retract_level1() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level1 = mgv.local(olKey).level1();
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    assertTrue(
      !level1.eq(mgv.local(olKey).level1()), "test void if level1 does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(level1, mgv.local(olKey).level1(), "level1 should have been restored");
  }

  function test_update_branch_on_insert_posInLeaf() public {
    mkr.provisionMgv(10 ether);
    Bin bin0 = Bin.wrap(0);
    mkr.newOfferByTick(olKey.tick(bin0), 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByTick(Tick.wrap(-46055), 100 ether, 100_000, 0);
    Offer offer = mgv.offers(olKey, ofr);
    assertTrue(
      offer.bin(olKey.tickSpacing).posInLeaf() != Bin.wrap(0).posInLeaf(),
      "test void if posInLeaf of second offer is not different"
    );
    assertEq(mgv.local(olKey).binPosInLeaf(), offer.bin(olKey.tickSpacing).posInLeaf(), "posInLeaf should have changed");
  }
  /* 
  When an offer ofr is updated, ofr is removed then re-added. In that case, if
  ofr is about to be inserted as the best offer, we don't go fetch the "next
  best offer" just after removing ofr. Instead we leave the updated bin branch
  in local as-is, to be flushed to storage when ofr gets inserted again. Since
  `local.bestBin()` is deduced from branch stored in local, `local.bestBin()` becomes
  wrong (it becomes higher than it really is). So we must check that it gets
  cached, otherwise we will 
    a) fail to flush the local level3/level2 to the right index
    b) flush the local level3/level2 to the wrong current index
  To really test a), we need to have some data already where level3/level2
  should be flushed (to check if the flushing has an effect), so we write an
  offer there (at lowBin) before it's best, and then we make it best so it gets
  cached to local (but the original data is still in storage)
  */

  function test_currentBin_is_cached_no_level31_erasure() public {
    // Create a very low bin so that later the branch of lowBin will be both in storage and in cache
    Bin veryLowBin = Bin.wrap(-100000);
    uint ofr_veryLow = mgv.newOfferByTick(olKey, olKey.tick(veryLowBin), 1 ether, 10_000, 0);

    // Create an offer at lowTick
    Bin lowBin = Bin.wrap(10);
    uint ofr = mgv.newOfferByTick(olKey, olKey.tick(lowBin), 1 ether, 10_000, 0);

    // Make sure very low bin uses a different branch
    assertTrue(
      veryLowBin.level3Index() != lowBin.level3Index(), "test setup: [very]lowBin level3Index should be different"
    );
    assertTrue(
      veryLowBin.level2Index() != lowBin.level2Index(), "test setup: [very]lowBin level2Index should be different"
    );

    // Remove veryLowBin. Now lowBin is the best, and its branch is in cache, but also in storage!
    mgv.retractOffer(olKey, ofr_veryLow, true);

    // Derive a "bad" local from it
    Local local = mgv.local(olKey);
    // Derive a new level3, level2
    uint leafPos = local.level3().firstOnePosition();
    Field otherLevel3 = Field.wrap(1 << (leafPos + 1) % uint(LEVEL_SIZE));
    uint level3Pos = local.level2().firstOnePosition();
    Field otherLevel2 = Field.wrap(1 << (level3Pos + 1) % uint(LEVEL_SIZE));
    Local badLocal = local.level3(otherLevel3).level2(otherLevel2);
    // Make sure we changed the implied bin of badLocal
    assertTrue(!badLocal.bestBin().eq(lowBin), "test setup: bad bin should not be original lowBin");
    // Make sure we have changed level indices
    assertTrue(
      badLocal.bestBin().level3Index() != lowBin.level3Index(), "test setup: bad bin level3Index should be different"
    );
    // Create a bin there
    mgv.newOfferByTick(olKey, olKey.tick(badLocal.bestBin()), 1 ether, 10_000, 0);
    // Save level3, level2
    Field highLevel3 = mgv.level3s(olKey, badLocal.bestBin().level3Index());
    // Update the new bin to an even better tick
    mgv.updateOfferByTick(olKey, olKey.tick(veryLowBin), 1 ether, 10_000, 0, ofr);

    // Make sure we the high offer's branch is still fine
    assertEq(
      mgv.level3s(olKey, badLocal.bestBin().level3Index()),
      highLevel3,
      "badLocal's tick's level3 should not have changed"
    );
    // Make sure the previously local offer's branch is now empty
    assertEq(mgv.level3s(olKey, lowBin.level3Index()), FieldLib.EMPTY, "lowBin's level3 should have been flushed");
  }

  function test_higher_tick() public {
    mgv.newOfferByTick(olKey, Tick.wrap(2), 1 ether, 100_000, 0);
    (, Local local) = mgv.config(olKey);

    mgv.newOfferByTick(olKey, Tick.wrap(3), 1 ether, 100_000, 0);
    (, local) = mgv.config(olKey);
    assertEq(local.binPosInLeaf(), 2);
  }

  function test_leaf_update_both_first_and_last(Tick tick) public {
    tick = Tick.wrap(bound(Tick.unwrap(tick), MIN_TICK, MAX_TICK));
    uint ofr0 = mgv.newOfferByTick(olKey, tick, 1 ether, 0, 0);
    Bin bin = olKey.nearestBin(tick);
    Leaf expected = LeafLib.EMPTY;
    expected = expected.setPosFirstOrLast(bin.posInLeaf(), ofr0, true);
    expected = expected.setPosFirstOrLast(bin.posInLeaf(), ofr0, false);
    assertEq(mgv.leafs(olKey, bin.leafIndex()), expected, "leaf not as expected");
    mgv.retractOffer(olKey, ofr0, true);
    assertEq(mgv.leafs(olKey, bin.leafIndex()), LeafLib.EMPTY, "leaf should be empty");
  }

  function test_cannot_update_offer_with_no_owner(uint32 ofrId) public {
    vm.assume(mgv.offerDetails(olKey, ofrId).maker() == address(0));

    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByTick(olKey, Tick.wrap(0), 1 ether, 100_000, 30, ofrId);
  }

  function test_max_offer_wants() public {
    mkr.provisionMgv(1 ether);
    uint ofrId = mkr.newOfferByTick(Tick.wrap(MAX_TICK), MAX_SAFE_VOLUME, 100_000);
    uint wants = mgv.offers(olKey, ofrId).wants();
    assertEq(wants, MAX_RATIO_MANTISSA * MAX_SAFE_VOLUME);
  }

  function test_new_offer_extremas_ok() public {
    mkr.provisionMgv(1 ether);
    mgv.setDensity96X32(olKey, 0);
    uint ofr = mkr.newOfferByTick(Tick.wrap(0), MAX_SAFE_VOLUME, 100_000, 0);
    mkr.updateOfferByTick(Tick.wrap(0), MAX_SAFE_VOLUME, 100_000, 0, ofr);
    mkr.updateOfferByTick(Tick.wrap(MAX_TICK), 1, 100_000, 0, ofr);
    mkr.newOfferByTick(Tick.wrap(MAX_TICK), 1, 100_000, 0);
  }

  function test_new_offer_extremas_ko() public {
    mgv.setDensity96X32(olKey, 0);
    vm.expectRevert("mgv/writeOffer/gives/tooBig");
    uint ofr = mkr.newOfferByTick(Tick.wrap(0), MAX_SAFE_VOLUME + 1, 100_000, 0);
    vm.expectRevert("mgv/writeOffer/gives/tooBig");
    mkr.updateOfferByTick(Tick.wrap(0), MAX_SAFE_VOLUME + 1, 100_000, 0, ofr);
    vm.expectRevert("mgv/writeOffer/tick/outOfRange");
    mkr.updateOfferByTick(Tick.wrap(MAX_TICK + 1), 1, 100_000, 0, ofr);
    vm.expectRevert("mgv/writeOffer/tick/outOfRange");
    mkr.newOfferByTick(Tick.wrap(MAX_TICK + 1), 1, 100_000, 0);
  }
}
