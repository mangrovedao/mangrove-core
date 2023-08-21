// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, Leaf} from "mgv_src/MgvLib.sol";
import {MgvRoot} from "mgv_src/MgvRoot.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";

contract MakerOperationsTest is MangroveTest, IMaker {
  TestMaker mkr;
  TestMaker mkr2;
  TestTaker tkr;

  function setUp() public override {
    super.setUp();

    mkr = setupMaker($(base), $(quote), "maker");
    mkr2 = setupMaker($(base), $(quote), "maker2");
    tkr = setupTaker($(base), $(quote), "taker");

    mkr.approveMgv(base, 10 ether);
    mkr2.approveMgv(base, 10 ether);

    deal($(quote), address(tkr), 1 ether);
    tkr.approveMgv(quote, 1 ether);
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
    uint num_args = 9;
    uint selector_bytes = 4;
    uint length = selector_bytes + num_args * 32;
    assertEq(msg.data.length, length, "calldata length in execute is incorrect");

    assertEq(order.outbound_tkn, $(base), "wrong base");
    assertEq(order.inbound_tkn, $(quote), "wrong quote");
    assertEq(order.wants, 0.05 ether, "wrong takerWants");
    assertEq(order.gives, 0.05 ether, "wrong takerGives");
    assertEq(order.offerDetail.gasreq(), 200_000, "wrong gasreq");
    assertEq(order.offerId, 1, "wrong offerId");
    assertEq(order.offer.wants(), 0.05 ether, "wrong offerWants");
    assertEq(order.offer.gives(), 0.05 ether, "wrong offerGives");
    // test flashloan
    assertEq(quote.balanceOf($(this)), 0.05 ether, "wrong quote balance");
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result) external {}

  function test_calldata_and_balance_in_makerExecute_are_correct() public {
    bool funded;
    (funded,) = $(mgv).call{value: 1 ether}("");
    deal($(base), $(this), 1 ether);
    uint ofr = mgv.newOfferByVolume($(base), $(quote), 0.05 ether, 0.05 ether, 200_000, 0);
    require(tkr.take(ofr, 0.05 ether), "take must work or test is void");
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
    mkr.newOfferByVolumeWithFunding(1 ether, 1 ether, 50000, 0, 1 ether);
    assertGt(mgv.balanceOf(address(mkr)), oldBal, "balance should have increased");
  }

  function test_fund_updateOffer() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50000, 0);
    expectFrom($(mgv));
    emit Credit(address(mkr), 0.9 ether);
    mkr.updateOfferByVolumeWithFunding(1 ether, 1 ether, 50000, ofr, 0.9 ether);
  }

  function test_posthook_fail_message() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50000, 0);

    mkr.setShouldFailHook(true);
    expectFrom($(mgv));
    emit PosthookFail("posthookFail");
    tkr.take(ofr, 0.1 ether); // fails but we don't care
  }

  function test_returnData_succeeds() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50000, OfferData({shouldRevert: false, executeData: "someData"}));

    bool success = tkr.take(ofr, 0.1 ether);
    assertTrue(success, "take should work");
  }

  function test_delete_restores_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.mgvBalance(); // should be 1 ether
    uint offerId = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    uint bal_ = mkr.mgvBalance(); // 1 ether minus provision
    uint collected = mkr.retractOfferWithDeprovision(offerId); // provision
    assertEq(bal - bal_, collected, "retract does not return a correct amount");
    assertEq(mkr.mgvBalance(), bal, "delete has not restored balance");
  }

  function test_delete_offer_log() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0);
    expectFrom($(mgv));
    emit OfferRetract($(base), $(quote), ofr, true);
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

    bool success = tkr.take(ofr, 0.1 ether);
    assertEq(success, true, "Snipe should succeed");

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
    emit OfferRetract($(base), $(quote), ofr, false);
    mkr.retractOffer(ofr);
  }

  function test_retract_offer_maintains_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.mgvBalance();
    uint prov = reader.getProvision($(base), $(quote), 2300);
    mkr.retractOffer(mkr.newOfferByVolume(1 ether, 1 ether, 2300, 0));
    assertEq(mkr.mgvBalance(), bal - prov, "unexpected maker balance");
  }

  function test_retract_middle_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(0.9 ether, 1 ether, 2300, 100);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 2300, 100);

    mkr.retractOffer(ofr);
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer was not removed from OB");
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(base), $(quote), ofr);

    assertEq(pair.prevOfferId(offer), ofr0, "Invalid prev");
    assertEq(pair.nextOfferId(offer), ofr1, "Invalid next");
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    assertEq(detail.gasprice(), 100, "offer gasprice is incorrect");

    assertTrue(mgv.offers($(base), $(quote), pair.prevOfferId(offer)).isLive(), "Invalid OB");
    assertTrue(mgv.offers($(base), $(quote), pair.nextOfferId(offer)).isLive(), "Invalid OB");
    MgvStructs.OfferPacked offer0 = mgv.offers($(base), $(quote), pair.prevOfferId(offer));
    MgvStructs.OfferPacked offer1 = mgv.offers($(base), $(quote), pair.nextOfferId(offer));

    assertEq(pair.prevOfferId(offer1), ofr0, "Invalid stitching for ofr1");
    assertEq(pair.nextOfferId(offer0), ofr1, "Invalid stitching for ofr0");
  }

  function test_retract_best_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    assertTrue(!mgv.offers($(base), $(quote), ofr).isLive(), "Offer was not removed from OB");
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr);
    MgvStructs.OfferDetailPacked detail = mgv.offerDetails($(base), $(quote), ofr);
    assertEq(pair.prevOfferId(offer), 0, "Invalid prev");
    assertEq(pair.nextOfferId(offer), ofr1, "Invalid next");
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    assertEq(detail.gasprice(), 100, "offer gasprice is incorrect");

    assertTrue(mgv.offers($(base), $(quote), pair.nextOfferId(offer)).isLive(), "Invalid OB");
    MgvStructs.OfferPacked offer1 = mgv.offers($(base), $(quote), pair.nextOfferId(offer));
    assertEq(pair.prevOfferId(offer1), 0, "Invalid stitching for ofr1");
    assertEq(pair.best(), ofr1, "Invalid best after retract");
  }

  function test_retract_worst_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOfferByVolume({wants: 1 ether, gives: 1 ether, gasreq: 2300, gasprice: 100});
    uint ofr0 = mkr.newOfferByVolume(0.9 ether, 1 ether, 2300, 100);
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Offer was not removed from OB");
    MgvStructs.OfferPacked offerx = mgv.offers($(base), $(quote), ofr);
    console.log("PREV", reader.prevOfferId($(base), $(quote), offerx));
    mkr.retractOffer(ofr);
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr);
    // note: a former version of this test was checking pair.prevOfferId(offer) and offer.next () but:
    // 1. There is no spec of what prev() next() are for a non-live offer (nor of what prev/nextOffer are)
    // 2. prev() and next() are not meaningful with tick trees
    assertEq(offer.gives(), 0, "offer gives was not set to 0");
    MgvStructs.OfferPacked offer0 = mgv.offers($(base), $(quote), ofr0);
    assertTrue(offer0.isLive(), "Invalid OB");
    assertEq(reader.nextOfferId($(base), $(quote), offer0), 0, "Invalid stitching for ofr0");
    assertEq(pair.best(), ofr0, "Invalid best after retract");
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
    uint densityFixed = (10 ** 7) << DensityLib.FIXED_FRACTIONAL_BITS;
    mgv.setGasbase($(base), $(quote), 1);
    mgv.setDensityFixed($(base), $(quote), densityFixed);
    mkr.newOfferByVolume(1 ether, DensityLib.fromFixed(densityFixed).multiply(1), 0, 0);
  }

  function test_low_density_fails_newOffer() public {
    uint densityFixed = (10 ** 7) << DensityLib.FIXED_FRACTIONAL_BITS;
    mgv.setGasbase($(base), $(quote), 1000);
    mgv.setDensityFixed($(base), $(quote), densityFixed);
    vm.expectRevert("mgv/writeOffer/density/tooLow");
    mkr.newOfferByVolume(1 ether, DensityLib.fromFixed(densityFixed).multiply(1000) - 1, 0, 0);
  }

  function test_maker_gets_no_mgv_balance_on_partial_fill() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 0.1 ether);
    assertTrue(success, "take must succeed");
    assertEq(mgv.balanceOf(address(mkr)), oldBalance, "mkr balance must not change");
  }

  function test_maker_gets_no_mgv_balance_on_full_fill() public {
    mkr.provisionMgv(1 ether);
    deal($(base), address(mkr), 1 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(success, "take must succeed");
    assertEq(mgv.balanceOf(address(mkr)), oldBalance, "mkr balance must not change");
  }

  function test_insertions_are_correctly_ordered() public {
    mkr.provisionMgv(10 ether);
    uint ofr2 = mkr.newOfferByVolume(1.1 ether, 1 ether, 100_000, 0);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.1 ether, 1 ether, 50_000, 0);
    uint ofr01 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    assertTrue(mgv.offers($(base), $(quote), ofr0).isLive(), "Oldest equivalent offer should be first");
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr0);
    uint _ofr01 = reader.nextOfferId($(base), $(quote), offer);
    assertEq(_ofr01, ofr01, "Wrong 2nd offer");
    assertTrue(mgv.offers($(base), $(quote), _ofr01).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers($(base), $(quote), _ofr01);
    uint _ofr2 = reader.nextOfferId($(base), $(quote), offer);
    assertEq(_ofr2, ofr2, "Wrong 3rd offer");
    assertTrue(mgv.offers($(base), $(quote), _ofr2).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers($(base), $(quote), _ofr2);
    uint _ofr1 = reader.nextOfferId($(base), $(quote), offer);
    assertEq(_ofr1, ofr1, "Wrong 4th offer");
    assertTrue(mgv.offers($(base), $(quote), _ofr1).isLive(), "Oldest equivalent offer should be first");
    offer = mgv.offers($(base), $(quote), _ofr1);
    assertEq(reader.nextOfferId($(base), $(quote), offer), 0, "Invalid OB");
  }

  // insertTest price, density (gives/gasreq) vs (gives'/gasreq'), age
  // nolongerBest
  // idemPrice
  // idemBest
  // A.BCD --> ABC.D

  function test_update_offer_resets_age_and_updates_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_000, ofr0);
    assertEq(ofr1, pair.best(), "Best offer should have changed");
  }

  function test_update_offer_price_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether + 1, 1.0 ether, 100_000, ofr0);
    assertEq(ofr1, pair.best(), "Best offer should have changed");
  }

  function test_update_offer_density_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_001, ofr0);
    assertEq(ofr1, pair.best(), "Best offer should have changed");
  }

  // before ticks: worsening an offer's density keeps it in best position if it still has the best density
  // after ticks: improving an offer's density does not make it best
  function test_update_offer_density_does_not_become_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1.0 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 99_999, ofr1);
    logOrderBook($(base), $(quote), 2);
    assertEq(pair.best(), ofr0, "Best offer should not have changed");
  }

  function test_update_offer_price_changes_prevnext() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOfferByVolume(1.2 ether, 1 ether, 100_000, 0);

    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Insertion error");
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr);
    assertEq(pair.prevOfferId(offer), ofr0, "Wrong prev offer");
    assertEq(pair.nextOfferId(offer), ofr1, "Wrong next offer");
    mkr.updateOfferByVolume(1.1 ether, 1.0 ether, 100_000, ofr);
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Insertion error");
    offer = mgv.offers($(base), $(quote), ofr);
    assertEq(pair.prevOfferId(offer), ofr2, "Wrong prev offer after update");
    assertEq(pair.nextOfferId(offer), ofr3, "Wrong next offer after update");
  }

  function test_update_offer_density_changes_prevnext() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_002, 0);

    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Insertion error");
    MgvStructs.OfferPacked offer = mgv.offers($(base), $(quote), ofr);
    assertEq(pair.prevOfferId(offer), ofr0, "Wrong prev offer");
    assertEq(pair.nextOfferId(offer), ofr1, "Wrong next offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 100_001, ofr);
    assertTrue(mgv.offers($(base), $(quote), ofr).isLive(), "Update error");
    offer = mgv.offers($(base), $(quote), ofr);
    assertEq(pair.prevOfferId(offer), ofr3, "Wrong prev offer after update");
    assertEq(pair.nextOfferId(offer), 0, "Wrong next offer after update");
  }

  function test_update_offer_after_higher_gasprice_change_fails() public {
    uint provision = reader.getProvision($(base), $(quote), 100_000);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    (MgvStructs.GlobalPacked cfg,) = mgv.config($(base), $(quote));
    mgv.setGasprice(cfg.gasprice() + 1); //gasprice goes up
    vm.expectRevert("mgv/insufficientProvision");
    mkr.updateOfferByVolume(1.0 ether + 2, 1.0 ether, 100_000, ofr0);
  }

  function test_update_offer_after_higher_gasprice_change_succeeds_when_over_provisioned() public {
    (MgvStructs.GlobalPacked cfg,) = mgv.config($(base), $(quote));
    uint gasprice = cfg.gasprice();
    uint provision = reader.getProvision($(base), $(quote), 100_000, gasprice);
    expectFrom($(mgv));
    emit Credit(address(mkr), provision * 2);
    mkr.provisionMgv(provision * 2); // provisionning twice the required amount
    expectFrom($(mgv));
    emit OfferWrite(
      $(base),
      $(quote),
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
    uint provision_ = reader.getProvision($(base), $(quote), 100_000, gasprice + 1); // new theoretical provision
    (cfg,) = mgv.config($(base), $(quote));
    expectFrom($(mgv));
    emit OfferWrite(
      $(base),
      $(quote),
      address(mkr),
      0, //tick
      1.0 ether,
      cfg.gasprice(), // offer gasprice should be the new gasprice
      100_000,
      ofr0
    );
    expectFrom($(mgv));
    emit Debit(address(mkr), provision_ - provision); // transfering missing provision into offer bounty
    mkr.updateOfferByVolume(1.0 ether + 2, 1.0 ether, 100_000, ofr0);
  }

  function test_update_offer_after_lower_gasprice_change_succeeds() public {
    uint provision = reader.getProvision($(base), $(quote), 100_000);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    (MgvStructs.GlobalPacked cfg,) = mgv.config($(base), $(quote));
    mgv.setGasprice(cfg.gasprice() - 1); //gasprice goes down
    uint _provision = reader.getProvision($(base), $(quote), 100_000);
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
    assertEq(pair.prevOfferId(pair.offers(center)), left, "wrong initial prev for center");
    assertEq(pair.nextOfferId(pair.offers(center)), right, "wrong initial next for center");
    mkr.updateOfferByVolume(1 ether + 0.02 ether, 1 ether, 100_000, center);
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), center);
    assertEq(pair.prevOfferId(ofr), left, "ofr.prev should be unchanged");
    assertEq(pair.nextOfferId(ofr), right, "ofr.next should be unchanged");
  }

  function test_update_on_retracted_offer() public {
    uint provision = reader.getProvision($(base), $(quote), 100_000);
    mkr.provisionMgv(provision);
    uint offerId = mkr.newOfferByVolume(1 ether, 1 ether, 100_000, 0);
    mkr.retractOfferWithDeprovision(offerId);
    mkr.withdrawMgv(provision);
    assertEq(mgv.balanceOf(address(mkr)), 0, "Maker should have no more provision on Mangrove");
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), offerId);
    MgvStructs.OfferDetailPacked dtl = mgv.offerDetails($(base), $(quote), offerId);
    assertEq(ofr.gives(), 0, "Retracted offer should have 0 gives");
    assertEq(dtl.gasprice(), 0, "Deprovisioned offer should have 0 gasprice");
    vm.expectRevert("mgv/insufficientProvision");
    mkr.updateOfferByVolume(1 ether + 2, 1 ether, 100_000, offerId);
    mkr.provisionMgv(provision);
    mkr.updateOfferByVolume(1 ether + 2, 1 ether, 100_000, offerId);
    ofr = mgv.offers($(base), $(quote), offerId);
    assertEq(ofr.gives(), 1 ether, "Offer not correctly updated");
  }

  function testOBBest(uint id) internal {
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), id);
    assertEq(mgv.best($(base), $(quote)), id, "testOBBest: not best");
    assertEq(pair.prevOfferId(ofr), 0, "testOBBest: prev not 0");
  }

  function testOBWorst(uint id) internal {
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), id);
    assertEq(pair.nextOfferId(ofr), 0, "testOBWorst fail");
  }

  function testOBLink(uint left, uint right) internal {
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), left);
    assertEq(pair.nextOfferId(ofr), right, "testOBLink: wrong ofr.next");
    ofr = mgv.offers($(base), $(quote), right);
    assertEq(pair.prevOfferId(ofr), left, "testOBLink: wrong ofr.prev");
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
    assertEq(pair.prevOfferId(pair.offers(center)), left, "wrong initial prev for center");
    assertEq(pair.nextOfferId(pair.offers(center)), right, "wrong initial next for center");
    mkr.updateOfferByVolume(1 ether + 0.01 ether, 1 ether, 100_000, center);
    MgvStructs.OfferPacked ofr = mgv.offers($(base), $(quote), center);
    assertEq(pair.prevOfferId(ofr), left, "ofr.prev should be unchanged");
    assertEq(pair.nextOfferId(ofr), right, "ofr.next should be unchanged");
  }

  function test_update_offer_price_stays_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOfferByVolume(1.0 ether + 0.02 ether, 1 ether, 100_000, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether + 0.01 ether, 1.0 ether, 100_000, ofr0);
    // csl.log(pair.offers(ofr0).tick().toString());
    assertEq(ofr0, pair.best(), "Best offer should not have changed");
  }

  // before ticks: worsening an offer's density keeps it in best position if it still has the best density
  // after ticks: even improving an offer's density makes it last of its tick
  function test_update_offer_density_becomes_last() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_002, 0);
    uint ofr2 = mkr.newOfferByVolume(1.0 ether, 1 ether, 100_003, 0);
    assertEq(ofr0, pair.best(), "Wrong best offer");
    mkr.updateOfferByVolume(1.0 ether, 1.0 ether, 99_000, ofr0);
    assertEq(pair.best(), ofr1, "Best offer should have changed");
    assertEq(reader.nextOfferIdById($(base), $(quote), ofr2), ofr0, "ofr0 should come after ofr2");
    assertEq(reader.nextOfferIdById($(base), $(quote), ofr0), 0, "ofr0 should be last");
  }

  function test_gasbase_is_deducted_1() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase($(base), $(quote), offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensityFixed($(base), $(quote), 0);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    assertEq(mgv.balanceOf(address(mkr)), 1 ether - offer_gasbase * 10 ** 9, "Wrong gasbase deducted");
  }

  function test_gasbase_is_deducted_2() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase($(base), $(quote), offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensityFixed($(base), $(quote), 0);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    assertEq(mgv.balanceOf(address(mkr)), 1 ether - offer_gasbase * 10 ** 9, "Wrong gasbase deducted");
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
    MgvStructs.LocalPacked local;
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
    MgvStructs.LocalUnpacked memory u_local;
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
    MgvStructs.OfferDetailPacked offerDetail;
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
    MgvStructs.OfferDetailUnpacked memory u_offerDetail;
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
    uint posInLeaf = pair.local().tickPosInLeaf();
    uint ofr = mkr.newOfferByVolume(wants, Tick.wrap(2).outboundFromInbound(wants), 100_000, 0);
    assertGt(
      posInLeaf, pair.local().tickPosInLeaf(), "test void if posInLeaf does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(posInLeaf, pair.local().tickPosInLeaf(), "posInLeaf should have been restored");
  }

  function test_update_branch_on_retract_level0() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level0 = pair.local().level0();
    int level0Index = pair.local().tick().level0Index();
    uint ofr = mkr.newOfferByVolume(1 ether, 10 ether, 100_000, 0);
    assertGt(
      level0Index, pair.local().tick().level0Index(), "test void if level0 does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(level0, pair.local().level0(), "level0 should have been restored");
  }

  function test_update_branch_on_retract_level1() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level1 = pair.local().level1();
    int level1Index = pair.local().tick().level1Index();
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    assertGt(
      level1Index, pair.local().tick().level1Index(), "test void if level1 does not change when second offer is created"
    );
    mkr.retractOffer(ofr);
    assertEq(level1, pair.local().level1(), "level1 should have been restored");
  }

  function test_update_branch_on_retract_level2() public {
    mkr.provisionMgv(10 ether);
    mkr.newOfferByVolume(1.0 ether, 1 ether, 100_000, 0);
    Field level2 = pair.local().level2();
    uint ofr = mkr.newOfferByVolume(1 ether, 100 ether, 100_000, 0);
    assertTrue(!level2.eq(pair.local().level2()), "test void if level2 does not change when second offer is created");
    mkr.retractOffer(ofr);
    assertEq(level2, pair.local().level2(), "level2 should have been restored");
  }

  function test_update_branch_on_insert_posInLeaf() public {
    mkr.provisionMgv(10 ether);
    Tick tick0 = Tick.wrap(0);
    mkr.newOfferByTick(Tick.unwrap(tick0), 1 ether, 100_000, 0);
    uint ofr = mkr.newOfferByTick(-46055, 100 ether, 100_000, 0);
    MgvStructs.OfferPacked offer = pair.offers(ofr);
    assertTrue(
      offer.tick().posInLeaf() != Tick.wrap(0).posInLeaf(), "test void if posInLeaf of second offer is not different"
    );
    assertEq(pair.local().tickPosInLeaf(), offer.tick().posInLeaf(), "posInLeaf should have changed");
  }

  function test_higher_tick() public {
    mgv.newOfferByTick($(base), $(quote), 2, 1 ether, 100_000, 0);
    (, MgvStructs.LocalPacked local) = mgv.config($(base), $(quote));
    console.log("pos in leaf", toString(local));
    console.log(local.tick().priceFromTick_e18());

    mgv.newOfferByTick($(base), $(quote), 3, 1 ether, 100_000, 0);
    (, local) = mgv.config($(base), $(quote));
    assertEq(local.tickPosInLeaf(), 2);
  }
}
