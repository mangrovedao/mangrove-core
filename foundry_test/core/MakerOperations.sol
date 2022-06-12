// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;
pragma abicoder v2;

import "mgv_test/tools/MangroveTest.sol";

contract MakerOperationsTest is MangroveTest, IMaker {
  AbstractMangrove mgv;
  TestMaker mkr;
  TestMaker mkr2;
  TestTaker tkr;
  TestToken base;
  TestToken quote;
  address _base;
  address _quote;

  function setUp() public {
    base = setupToken("A", "$A");
    _base = address(base);
    quote = setupToken("B", "$B");
    _quote = address(quote);

    mgv = setupMangrove(base, quote);
    mkr = setupMaker(mgv, _base, _quote);
    mkr2 = setupMaker(mgv, _base, _quote);
    tkr = setupTaker(mgv, _base, _quote);

    payable(mkr).transfer(10 ether);
    mkr.approveMgv(base, 10 ether);
    payable(mkr2).transfer(10 ether);
    mkr2.approveMgv(base, 10 ether);

    payable(tkr).transfer(10 ether);

    quote.mint(address(tkr), 1 ether);
    tkr.approveMgv(quote, 1 ether);

    base.approve(address(mgv), 10 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "MakerOperations_Test");
    vm.label(_base, "$A");
    vm.label(_quote, "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(mkr), "maker");
    vm.label(address(mkr2), "maker2");
    vm.label(address(tkr), "taker");
  }

  function test_provision_adds_freeWei_and_ethers() public {
    uint mgv_bal = address(mgv).balance;
    uint amt1 = 235;
    uint amt2 = 1.3 ether;

    mkr.provisionMgv(amt1);

    assertEq(mkr.freeWei(), amt1, "incorrect mkr freeWei amount (1)");
    assertEq(
      address(mgv).balance,
      mgv_bal + amt1,
      "incorrect mgv ETH balance (1)"
    );

    mkr.provisionMgv(amt2);

    assertEq(mkr.freeWei(), amt1 + amt2, "incorrect mkr freeWei amount (2)");
    assertEq(
      address(mgv).balance,
      mgv_bal + amt1 + amt2,
      "incorrect mgv ETH balance (2)"
    );
  }

  // since we check calldata, execute must be internal
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    returns (bytes32 ret)
  {
    ret; // silence unused function parameter warning
    uint num_args = 9;
    uint selector_bytes = 4;
    uint length = selector_bytes + num_args * 32;
    assertEq(
      msg.data.length,
      length,
      "calldata length in execute is incorrect"
    );

    assertEq(order.outbound_tkn, _base, "wrong base");
    assertEq(order.inbound_tkn, _quote, "wrong quote");
    assertEq(order.wants, 0.05 ether, "wrong takerWants");
    assertEq(order.gives, 0.05 ether, "wrong takerGives");
    assertEq(order.offerDetail.gasreq(), 200_000, "wrong gasreq");
    assertEq(order.offerId, 1, "wrong offerId");
    assertEq(order.offer.wants(), 0.05 ether, "wrong offerWants");
    assertEq(order.offer.gives(), 0.05 ether, "wrong offerGives");
    // test flashloan
    assertEq(quote.balanceOf(address(this)), 0.05 ether, "wrong quote balance");
    return "";
  }

  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external {}

  function test_calldata_and_balance_in_makerExecute_are_correct() public {
    bool funded;
    (funded, ) = address(mgv).call{value: 1 ether}("");
    base.mint(address(this), 1 ether);
    uint ofr = mgv.newOffer(
      _base,
      _quote,
      0.05 ether,
      0.05 ether,
      200_000,
      0,
      0
    );
    require(tkr.take(ofr, 0.05 ether), "take must work or test is void");
  }

  function test_withdraw_removes_freeWei_and_ethers() public {
    uint mgv_bal = address(mgv).balance;
    uint amt1 = 0.86 ether;
    uint amt2 = 0.12 ether;

    mkr.provisionMgv(amt1);
    bool success = mkr.withdrawMgv(amt2);
    assertTrue(success, "mkr was not able to withdraw from mgv");
    assertEq(mkr.freeWei(), amt1 - amt2, "incorrect mkr freeWei amount");
    assertEq(
      address(mgv).balance,
      mgv_bal + amt1 - amt2,
      "incorrect mgv ETH balance"
    );
  }

  function test_withdraw_too_much_fails() public {
    uint amt1 = 6.003 ether;
    mkr.provisionMgv(amt1);
    try mkr.withdrawMgv(amt1 + 1) {
      fail("mkr cannot withdraw more than it has");
    } catch Error(string memory r) {
      assertEq(r, "mgv/insufficientProvision", "wrong revert reason");
    }
  }

  function test_newOffer_without_freeWei_fails() public {
    try mkr.newOffer(1 ether, 1 ether, 0, 0) {
      fail("mkr cannot create offer without provision");
    } catch Error(string memory r) {
      assertEq(
        r,
        "mgv/insufficientProvision",
        "new offer failed for wrong reason"
      );
    }
  }

  function test_fund_newOffer() public {
    uint oldBal = mgv.balanceOf(address(mkr));
    expectFrom(address(mgv));
    emit Credit(address(mkr), 1 ether);
    mkr.newOfferWithFunding(1 ether, 1 ether, 50000, 0, 1 ether);
    assertGt(
      mgv.balanceOf(address(mkr)),
      oldBal,
      "balance should have increased"
    );
  }

  function test_fund_updateOffer() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50000, 0);
    expectFrom(address(mgv));
    emit Credit(address(mkr), 0.9 ether);
    mkr.updateOfferWithFunding(1 ether, 1 ether, 50000, 0, ofr, 0.9 ether);
  }

  function test_posthook_fail_message() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50000, 0);

    mkr.setShouldFailHook(true);
    expectFrom(address(mgv));
    emit PosthookFail(_base, _quote, ofr, "posthookFail");
    tkr.take(ofr, 0.1 ether); // fails but we don't care
  }

  function test_badReturn_fails() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50000, 0);

    mkr.shouldAbort(true);
    bool success = tkr.take(ofr, 0.1 ether);
    assertTrue(!success, "take should fail");
    mkr.expect("abort");
  }

  function test_delete_restores_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.freeWei(); // should be 1 ether
    uint offerId = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    uint bal_ = mkr.freeWei(); // 1 ether minus provision
    uint collected = mkr.retractOfferWithDeprovision(offerId); // provision
    assertEq(bal - bal_, collected, "retract does not return a correct amount");
    assertEq(mkr.freeWei(), bal, "delete has not restored balance");
  }

  function test_delete_offer_log() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    expectFrom(address(mgv));
    emit OfferRetract(_base, _quote, ofr);
    mkr.retractOfferWithDeprovision(ofr);
  }

  function test_retract_retracted_does_not_drain() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);

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
    base.mint(address(mkr), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);

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
    uint ofr = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    expectFrom(address(mgv));
    emit OfferRetract(_base, _quote, ofr);
    mkr.retractOffer(ofr);
  }

  function test_retract_offer_maintains_balance() public {
    mkr.provisionMgv(1 ether);
    uint bal = mkr.freeWei();
    uint prov = getProvision(mgv, _base, _quote, 2300);
    mkr.retractOffer(mkr.newOffer(1 ether, 1 ether, 2300, 0));
    assertEq(mkr.freeWei(), bal - prov, "unexpected maker balance");
  }

  function test_retract_middle_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    uint ofr = mkr.newOffer({
      wants: 1 ether,
      gives: 1 ether,
      gasreq: 2300,
      gasprice: 100,
      pivotId: 0
    });
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 2300, 100);

    mkr.retractOffer(ofr);
    assertTrue(
      !mgv.isLive(mgv.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    (P.OfferStruct memory offer, P.OfferDetailStruct memory offerDetail) = mgv
      .offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Invalid prev");
    assertEq(offer.next, ofr1, "Invalid next");
    assertEq(offer.gives, 0, "offer gives was not set to 0");
    assertEq(offerDetail.gasprice, 100, "offer gasprice is incorrect");

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, offer.prev)), "Invalid OB");
    assertTrue(mgv.isLive(mgv.offers(_base, _quote, offer.next)), "Invalid OB");
    (P.OfferStruct memory offer0, ) = mgv.offerInfo(_base, _quote, offer.prev);
    (P.OfferStruct memory offer1, ) = mgv.offerInfo(_base, _quote, offer.next);
    assertEq(offer1.prev, ofr0, "Invalid snitching for ofr1");
    assertEq(offer0.next, ofr1, "Invalid snitching for ofr0");
  }

  function test_retract_best_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOffer({
      wants: 1 ether,
      gives: 1 ether,
      gasreq: 2300,
      gasprice: 100,
      pivotId: 0
    });
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 2300, 100);
    mkr.retractOffer(ofr);
    assertTrue(
      !mgv.isLive(mgv.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    (P.OfferStruct memory offer, P.OfferDetailStruct memory offerDetail) = mgv
      .offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, 0, "Invalid prev");
    assertEq(offer.next, ofr1, "Invalid next");
    assertEq(offer.gives, 0, "offer gives was not set to 0");
    assertEq(offerDetail.gasprice, 100, "offer gasprice is incorrect");

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, offer.next)), "Invalid OB");
    (P.OfferStruct memory offer1, ) = mgv.offerInfo(_base, _quote, offer.next);
    assertEq(offer1.prev, 0, "Invalid snitching for ofr1");
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(cfg.best(), ofr1, "Invalid best after retract");
  }

  function test_retract_worst_offer_leaves_a_valid_book() public {
    mkr.provisionMgv(10 ether);
    uint ofr = mkr.newOffer({
      wants: 1 ether,
      gives: 1 ether,
      gasreq: 2300,
      gasprice: 100,
      pivotId: 0
    });
    uint ofr0 = mkr.newOffer(0.9 ether, 1 ether, 2300, 100);
    assertTrue(
      mgv.isLive(mgv.offers(_base, _quote, ofr)),
      "Offer was not removed from OB"
    );
    mkr.retractOffer(ofr);
    (P.OfferStruct memory offer, P.OfferDetailStruct memory offerDetail) = mgv
      .offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Invalid prev");
    assertEq(offer.next, 0, "Invalid next");
    assertEq(offer.gives, 0, "offer gives was not set to 0");
    assertEq(offerDetail.gasprice, 100, "offer gasprice is incorrect");

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, offer.prev)), "Invalid OB");
    (P.OfferStruct memory offer0, ) = mgv.offerInfo(_base, _quote, offer.prev);
    assertEq(offer0.next, 0, "Invalid snitching for ofr0");
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(cfg.best(), ofr0, "Invalid best after retract");
  }

  function test_delete_wrong_offer_fails() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.retractOfferWithDeprovision(ofr) {
      fail("mkr2 should not be able to delete mkr's offer");
    } catch Error(string memory r) {
      assertEq(r, "mgv/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function test_retract_wrong_offer_fails() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 2300, 0);
    try mkr2.retractOffer(ofr) {
      fail("mkr2 should not be able to retract mkr's offer");
    } catch Error(string memory r) {
      assertEq(r, "mgv/retractOffer/unauthorized", "wrong revert reason");
    }
  }

  function test_gasreq_max_with_newOffer_ok() public {
    mkr.provisionMgv(1 ether);
    uint gasmax = 750000;
    mgv.setGasmax(gasmax);
    mkr.newOffer(1 ether, 1 ether, gasmax, 0);
  }

  function test_gasreq_too_high_fails_newOffer() public {
    uint gasmax = 12;
    mgv.setGasmax(gasmax);
    try mkr.newOffer(1 ether, 1 ether, gasmax + 1, 0) {
      fail("gasreq above gasmax, newOffer should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/gasreq/tooHigh", "wrong revert reason");
    }
  }

  function test_min_density_with_newOffer_ok() public {
    mkr.provisionMgv(1 ether);
    uint density = 10**7;
    mgv.setGasbase(_base, _quote, 1);
    mgv.setDensity(_base, _quote, density);
    mkr.newOffer(1 ether, density, 0, 0);
  }

  function test_low_density_fails_newOffer() public {
    uint density = 10**7;
    mgv.setGasbase(_base, _quote, 1);
    mgv.setDensity(_base, _quote, density);
    try mkr.newOffer(1 ether, density - 1, 0, 0) {
      fail("density too low, newOffer should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/writeOffer/density/tooLow", "wrong revert reason");
    }
  }

  function test_maker_gets_no_freeWei_on_partial_fill() public {
    mkr.provisionMgv(1 ether);
    base.mint(address(mkr), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 0.1 ether);
    assertTrue(success, "take must succeed");
    assertEq(
      mgv.balanceOf(address(mkr)),
      oldBalance,
      "mkr balance must not change"
    );
  }

  function test_maker_gets_no_freeWei_on_full_fill() public {
    mkr.provisionMgv(1 ether);
    base.mint(address(mkr), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldBalance = mgv.balanceOf(address(mkr));
    bool success = tkr.take(ofr, 1 ether);
    assertTrue(success, "take must succeed");
    assertEq(
      mgv.balanceOf(address(mkr)),
      oldBalance,
      "mkr balance must not change"
    );
  }

  function test_insertions_are_correctly_ordered() public {
    mkr.provisionMgv(10 ether);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    uint ofr01 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t loc_cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, loc_cfg.best(), "Wrong best offer");
    assertTrue(
      mgv.isLive(mgv.offers(_base, _quote, ofr0)),
      "Oldest equivalent offer should be first"
    );
    (P.OfferStruct memory offer, ) = mgv.offerInfo(_base, _quote, ofr0);
    uint _ofr01 = offer.next;
    assertEq(_ofr01, ofr01, "Wrong 2nd offer");
    assertTrue(
      mgv.isLive(mgv.offers(_base, _quote, _ofr01)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = mgv.offerInfo(_base, _quote, _ofr01);
    uint _ofr1 = offer.next;
    assertEq(_ofr1, ofr1, "Wrong 3rd offer");
    assertTrue(
      mgv.isLive(mgv.offers(_base, _quote, _ofr1)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = mgv.offerInfo(_base, _quote, _ofr1);
    uint _ofr2 = offer.next;
    assertEq(_ofr2, ofr2, "Wrong 4th offer");
    assertTrue(
      mgv.isLive(mgv.offers(_base, _quote, _ofr2)),
      "Oldest equivalent offer should be first"
    );
    (offer, ) = mgv.offerInfo(_base, _quote, _ofr2);
    assertEq(offer.next, 0, "Invalid OB");
  }

  // insertTest price, density (gives/gasreq) vs (gives'/gasreq'), age
  // nolongerBest
  // idemPrice
  // idemBest
  // A.BCD --> ABC.D

  function test_update_offer_resets_age_and_updates_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_000, ofr0, ofr0);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr1, cfg.best(), "Best offer should have changed");
  }

  function test_update_offer_price_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr1, cfg.best(), "Best offer should have changed");
  }

  function test_update_offer_density_nolonger_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr1, cfg.best(), "Best offer should have changed");
  }

  function test_update_offer_price_with_self_as_pivot_becomes_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr1, ofr1);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr1, cfg.best(), "Best offer should have changed");
  }

  function test_update_offer_density_with_self_as_pivot_becomes_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr1, ofr1);
    (, cfg) = mgv.config(_base, _quote);
    logOfferBook(mgv, _base, _quote, 2);
    assertEq(cfg.best(), ofr1, "Best offer should have changed");
  }

  function test_update_offer_price_with_best_as_pivot_becomes_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether + 1, 100_000, ofr0, ofr1);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr1, cfg.best(), "Best offer should have changed");
  }

  function test_update_offer_density_with_best_as_pivot_becomes_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1.0 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 99_999, ofr0, ofr1);
    (, cfg) = mgv.config(_base, _quote);
    logOfferBook(mgv, _base, _quote, 2);
    assertEq(cfg.best(), ofr1, "Best offer should have changed");
  }

  function test_update_offer_price_with_best_as_pivot_changes_prevnext()
    public
  {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOffer(1.2 ether, 1 ether, 100_000, 0);

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (P.OfferStruct memory offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Wrong prev offer");
    assertEq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr0, ofr);
    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr2, "Wrong prev offer after update");
    assertEq(offer.next, ofr3, "Wrong next offer after update");
  }

  function test_update_offer_price_with_self_as_pivot_changes_prevnext()
    public
  {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.1 ether, 1 ether, 100_000, 0);
    uint ofr3 = mkr.newOffer(1.2 ether, 1 ether, 100_000, 0);

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (P.OfferStruct memory offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Wrong prev offer");
    assertEq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.1 ether, 1.0 ether, 100_000, ofr, ofr);
    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr2, "Wrong prev offer after update");
    assertEq(offer.next, ofr3, "Wrong next offer after update");
  }

  function test_update_offer_density_with_best_as_pivot_changes_prevnext()
    public
  {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (P.OfferStruct memory offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Wrong prev offer");
    assertEq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr);
    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Update error");
    (offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr2, "Wrong prev offer after update");
    assertEq(offer.next, ofr3, "Wrong next offer after update");
  }

  function test_update_offer_density_with_self_as_pivot_changes_prevnext()
    public
  {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr1 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    uint ofr2 = mkr.newOffer(1.0 ether, 1 ether, 100_001, 0);
    uint ofr3 = mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);

    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (P.OfferStruct memory offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr0, "Wrong prev offer");
    assertEq(offer.next, ofr1, "Wrong next offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr, ofr);
    assertTrue(mgv.isLive(mgv.offers(_base, _quote, ofr)), "Insertion error");
    (offer, ) = mgv.offerInfo(_base, _quote, ofr);
    assertEq(offer.prev, ofr2, "Wrong prev offer after update");
    assertEq(offer.next, ofr3, "Wrong next offer after update");
  }

  function test_update_offer_after_higher_gasprice_change_fails() public {
    uint provision = getProvision(mgv, _base, _quote, 100_000);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (P.Global.t cfg, ) = mgv.config(_base, _quote);
    mgv.setGasprice(cfg.gasprice() + 1); //gasprice goes up
    try mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0) {
      fail("Update offer should have failed");
    } catch Error(string memory r) {
      assertEq(r, "mgv/insufficientProvision", "wrong revert reason");
    }
  }

  function test_update_offer_after_higher_gasprice_change_succeeds_when_over_provisioned()
    public
  {
    (P.Global.t cfg, ) = mgv.config(_base, _quote);
    uint gasprice = cfg.gasprice();
    uint provision = getProvision(mgv, _base, _quote, 100_000, gasprice);
    expectFrom(address(mgv));
    emit Credit(address(mkr), provision * 2);
    mkr.provisionMgv(provision * 2); // provisionning twice the required amount
    expectFrom(address(mgv));
    emit OfferWrite(
      _base,
      _quote,
      address(mkr),
      1.0 ether,
      1.0 ether,
      gasprice, // offer at old gasprice
      100_000,
      1,
      0
    );
    expectFrom(address(mgv));
    emit Debit(address(mkr), provision); // transfering missing provision into offer bounty
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0); // locking exact bounty
    mgv.setGasprice(gasprice + 1); //gasprice goes up
    uint provision_ = getProvision(mgv, _base, _quote, 100_000, gasprice + 1); // new theoretical provision
    (cfg, ) = mgv.config(_base, _quote);
    expectFrom(address(mgv));
    emit OfferWrite(
      _base,
      _quote,
      address(mkr),
      1.0 ether + 2,
      1.0 ether,
      cfg.gasprice(), // offer gasprice should be the new gasprice
      100_000,
      ofr0,
      0
    );
    expectFrom(address(mgv));
    emit Debit(address(mkr), provision_ - provision); // transfering missing provision into offer bounty
    try
      mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0)
    {} catch {
      fail("Update offer should have succeeded");
    }
  }

  function test_update_offer_after_lower_gasprice_change_succeeds() public {
    uint provision = getProvision(mgv, _base, _quote, 100_000);
    mkr.provisionMgv(provision);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    (P.Global.t cfg, ) = mgv.config(_base, _quote);
    mgv.setGasprice(cfg.gasprice() - 1); //gasprice goes down
    uint _provision = getProvision(mgv, _base, _quote, 100_000);
    expectFrom(address(mgv));
    emit Credit(address(mkr), provision - _provision);
    try mkr.updateOffer(1.0 ether + 2, 1.0 ether, 100_000, ofr0, ofr0) {
      assertEq(
        mgv.balanceOf(address(mkr)),
        provision - _provision,
        "Maker balance is incorrect"
      );
    } catch {
      fail("Update offer should have succeeded");
    }
  }

  function test_update_offer_next_to_itself_does_not_break_ob() public {
    mkr.provisionMgv(1 ether);
    uint left = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOffer(1 ether + 3, 1 ether, 100_000, 0);
    uint center = mkr.newOffer(1 ether + 1, 1 ether, 100_000, 0);
    mkr.updateOffer(1 ether + 2, 1 ether, 100_000, center, center);
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(_base, _quote, center);
    assertEq(ofr.prev, left, "ofr.prev should be unchanged");
    assertEq(ofr.next, right, "ofr.next should be unchanged");
  }

  function test_update_on_retracted_offer() public {
    uint provision = getProvision(mgv, _base, _quote, 100_000);
    mkr.provisionMgv(provision);
    uint offerId = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.retractOfferWithDeprovision(offerId);
    mkr.withdrawMgv(provision);
    assertEq(
      mgv.balanceOf(address(mkr)),
      0,
      "Maker should have no more provision on Mangrove"
    );
    (P.OfferStruct memory ofr, P.OfferDetailStruct memory dtl) = mgv.offerInfo(
      _base,
      _quote,
      offerId
    );
    assertEq(ofr.gives, 0, "Retracted offer should have 0 gives");
    assertEq(dtl.gasprice, 0, "Deprovisioned offer should have 0 gasprice");
    try mkr.updateOffer(1 ether + 2, 1 ether, 100_000, offerId, offerId) {
      fail("Deprovisioned offer cannot be updated unless reprovisioned");
    } catch Error(string memory message) {
      assertEq(message, "mgv/insufficientProvision", "");
      mkr.provisionMgv(provision);
      try mkr.updateOffer(1 ether + 2, 1 ether, 100_000, offerId, offerId) {
        (ofr, ) = mgv.offerInfo(_base, _quote, offerId);
        assertEq(ofr.gives, 1 ether, "Offer not correctly updated");
      } catch {
        fail("Updating offer should succeed");
      }
    }
  }

  function testOBBest(uint id) internal {
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(_base, _quote, id);
    assertEq(mgv.best(_base, _quote), id, "testOBBest: not best");
    assertEq(ofr.prev, 0, "testOBBest: prev not 0");
  }

  function testOBWorst(uint id) internal {
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(_base, _quote, id);
    assertEq(ofr.next, 0, "testOBWorst fail");
  }

  function testOBLink(uint left, uint right) internal {
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(_base, _quote, left);
    assertEq(ofr.next, right, "testOBLink: wrong ofr.next");
    (ofr, ) = mgv.offerInfo(_base, _quote, right);
    assertEq(ofr.prev, left, "testOBLink: wrong ofr.prev");
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

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 1, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_1() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 1, x, g, two, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_left_1_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 5, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_1_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.updateOffer(x + 5, x, g, two, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_left_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    uint three = mkr.newOffer(x + 5, x, g, 0);
    mkr.updateOffer(x + 1, x, g, 0, three);

    testOBOrder([one, three, two]);
  }

  function test_complex_offer_update_right_2() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    uint three = mkr.newOffer(x + 5, x, g, 0);
    mkr.updateOffer(x + 4, x, g, three, one);

    testOBOrder([two, one, three]);
  }

  function test_complex_offer_update_left_3() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.retractOffer(two);
    mkr.updateOffer(x + 3, x, g, 0, two);

    testOBOrder([one, two]);
  }

  function test_complex_offer_update_right_3() public {
    mkr.provisionMgv(1 ether);
    uint x = 1 ether;
    uint g = 100_000;

    uint one = mkr.newOffer(x, x, g, 0);
    uint two = mkr.newOffer(x + 3, x, g, 0);
    mkr.retractOffer(one);
    mkr.updateOffer(x, x, g, 0, one);

    testOBOrder([one, two]);
  }

  function test_update_offer_prev_to_itself_does_not_break_ob() public {
    mkr.provisionMgv(1 ether);
    uint left = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint right = mkr.newOffer(1 ether + 3, 1 ether, 100_000, 0);
    uint center = mkr.newOffer(1 ether + 2, 1 ether, 100_000, 0);
    mkr.updateOffer(1 ether + 1, 1 ether, 100_000, center, center);
    (P.OfferStruct memory ofr, ) = mgv.offerInfo(_base, _quote, center);
    assertEq(ofr.prev, left, "ofr.prev should be unchanged");
    assertEq(ofr.next, right, "ofr.next should be unchanged");
  }

  function test_update_offer_price_stays_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether + 2, 1 ether, 100_000, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether + 1, 1.0 ether, 100_000, ofr0, ofr0);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Best offer should not have changed");
  }

  function test_update_offer_density_stays_best() public {
    mkr.provisionMgv(10 ether);
    uint ofr0 = mkr.newOffer(1.0 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1.0 ether, 1 ether, 100_002, 0);
    (, P.Local.t cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Wrong best offer");
    mkr.updateOffer(1.0 ether, 1.0 ether, 100_001, ofr0, ofr0);
    (, cfg) = mgv.config(_base, _quote);
    assertEq(ofr0, cfg.best(), "Best offer should not have changed");
  }

  function test_gasbase_is_deducted_1() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase(_base, _quote, offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensity(_base, _quote, 0);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    assertEq(
      mgv.balanceOf(address(mkr)),
      1 ether - offer_gasbase * 10**9,
      "Wrong gasbase deducted"
    );
  }

  function test_gasbase_is_deducted_2() public {
    uint offer_gasbase = 20_000;
    mkr.provisionMgv(1 ether);
    mgv.setGasbase(_base, _quote, offer_gasbase);
    mgv.setGasprice(1);
    mgv.setDensity(_base, _quote, 0);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 0, 0);
    tkr.take(ofr, 0.1 ether);
    assertEq(
      mgv.balanceOf(address(mkr)),
      1 ether - offer_gasbase * 10**9,
      "Wrong gasbase deducted"
    );
  }

  function test_penalty_gasprice_is_mgv_gasprice() public {
    mgv.setGasprice(10);
    mkr.shouldFail(true);
    mkr.provisionMgv(1 ether);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    uint oldProvision = mgv.balanceOf(address(mkr));
    mgv.setGasprice(10000);
    (uint gave, uint got) = tkr.marketOrder(1 ether, 1 ether);
    assertTrue(gave == got && got == 0, "market Order should be noop");
    uint gotBack = mgv.balanceOf(address(mkr)) - oldProvision;
    assertEq(gotBack, 0, "Should not have gotten any provision back");
  }
}
