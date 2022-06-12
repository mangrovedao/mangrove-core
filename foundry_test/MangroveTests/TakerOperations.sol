// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/Tools/MangroveTest.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract TakerOperations is MangroveTest {
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  AbstractMangrove mgv;
  TestMaker mkr;
  TestMaker refusemkr;
  TestMaker failmkr;

  bool refuseReceive = false;

  receive() external payable {
    if (refuseReceive) {
      revert("no");
    }
  }

  function setUp() public {
    baseT = setupToken("A", "$A");
    quoteT = setupToken("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = setupMangrove(baseT, quoteT);

    mkr = setupMaker(mgv, base, quote);
    refusemkr = setupMaker(mgv, base, quote, 1);
    failmkr = setupMaker(mgv, base, quote, 2);

    payable(mkr).transfer(10 ether);
    payable(refusemkr).transfer(10 ether);
    payable(failmkr).transfer(10 ether);

    mkr.provisionMgv(10 ether);
    mkr.approveMgv(baseT, 10 ether);

    refusemkr.provisionMgv(1 ether);
    refusemkr.approveMgv(baseT, 10 ether);
    failmkr.provisionMgv(1 ether);
    failmkr.approveMgv(baseT, 10 ether);

    baseT.mint(address(mkr), 5 ether);
    baseT.mint(address(failmkr), 5 ether);
    baseT.mint(address(refusemkr), 5 ether);

    quoteT.mint(address(this), 5 ether);
    quoteT.mint(address(this), 5 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "taker");
    vm.label(base, "$A");
    vm.label(quote, "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(mkr), "maker");
    vm.label(address(failmkr), "reverting maker");
    vm.label(address(refusemkr), "refusing maker");
  }

  function test_snipe_reverts_if_taker_is_blacklisted_for_quote() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    quoteT.blacklists(address(this));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      fail("Snipe should fail");
    } catch Error(string memory errorMsg) {
      assertEq(errorMsg, "mgv/takerTransferFail", "Unexpected revert reason");
      assertEq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
    }
  }

  function test_snipe_reverts_if_taker_is_blacklisted_for_base() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    baseT.blacklists(address(this));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      fail("Snipe should fail");
    } catch Error(string memory errorMsg) {
      assertEq(errorMsg, "mgv/MgvFailToPayTaker", "Unexpected revert reason");
      assertEq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
    }
  }

  function test_snipe_fails_if_price_has_changed() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 0.5 ether, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 0, "Snipe should fail");
      assertEq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
      assertTrue(
        (got == gave && gave == 0),
        "Taker should not give or take anything"
      );
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_taker_cannot_drain_maker() public {
    mgv.setDensity(base, quote, 0);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(9, 10, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1, 15 ether, 100_000];
    uint oldBal = quoteT.balanceOf(address(this));
    mgv.snipes(base, quote, targets, true);
    uint newBal = quoteT.balanceOf(address(this));
    assertGt(oldBal, newBal, "oldBal should be strictly higher");
  }

  function test_snipe_fillWants() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.5 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 0.5 ether, "Taker did not get enough");
      assertEq(gave, 0.5 ether, "Taker did not give enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_multiple_snipes_fillWants() public {
    uint i;
    uint[] memory ofrs = new uint[](3);
    ofrs[i++] = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    ofrs[i++] = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    ofrs[i++] = mkr.newOffer(1 ether, 1 ether, 100_000, 0);

    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 3 ether);
    uint[4][] memory targets = new uint[4][](3);
    uint j;
    targets[j] = [ofrs[j], 0.5 ether, 1 ether, 100_000];
    j++;
    targets[j] = [ofrs[j], 1 ether, 1 ether, 100_000];
    j++;
    targets[j] = [ofrs[j], 0.8 ether, 1 ether, 100_000];

    expectFrom(address(mgv));
    emit OrderStart();
    expectFrom(address(mgv));
    emit OrderComplete(
      address(base),
      address(quote),
      address(this),
      2.3 ether,
      2.3 ether,
      0,
      0
    );
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 3, "Snipes should not fail");
      assertEq(got, 2.3 ether, "Taker did not get enough");
      assertEq(gave, 2.3 ether, "Taker did not give enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  event Transfer(address indexed from, address indexed to, uint value);

  function test_snipe_fillWants_zero() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    assertTrue(hasOffer(mgv, base, quote, ofr), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    expectFrom(address(quote));
    emit Transfer(address(this), address(mgv), 0);
    expectFrom(address(quote));
    emit Transfer(address(mgv), address(mkr), 0);
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 0 ether, "Taker had too much");
      assertEq(gave, 0 ether, "Taker gave too much");
      assertTrue(
        !hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_snipe_free_offer_fillWants_respects_spec() public {
    uint ofr = mkr.newOffer(0, 1 ether, 100_000, 0);
    assertTrue(hasOffer(mgv, base, quote, ofr), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    /* Setting fillWants = true means we should not receive more than `wants`.
       Here we are asking for 0.1 eth to an offer that gives 1eth for nothing.
       We should still only receive 0.1 eth */

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.1 ether, 0, 100_000];
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 0.1 ether, "Wrong got value");
      assertEq(gave, 0 ether, "Wrong gave value");
      assertTrue(
        !hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_snipe_free_offer_fillGives_respects_spec() public {
    uint ofr = mkr.newOffer(0, 1 ether, 100_000, 0);
    assertTrue(hasOffer(mgv, base, quote, ofr), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    /* Setting fillWants = false means we should spend as little as possible to receive
       as much as possible.
       Here despite asking for .1eth the offer gives 1eth for 0 so we should receive 1eth. */

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.1 ether, 0, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 1 ether, "Wrong got value");
      assertEq(gave, 0 ether, "Wrong gave value");
      assertTrue(
        !hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_snipe_fillGives_zero() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    assertTrue(hasOffer(mgv, base, quote, ofr), "Offer should be in the book");
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 0 ether, "Taker had too much");
      assertEq(gave, 0 ether, "Taker gave too much");
      assertTrue(
        !hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_snipe_fillGives() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.5 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should not fail");
      assertEq(got, 1 ether, "Taker did not get enough");
      assertEq(gave, 1 ether, "Taker did not get enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_mo_fillWants() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 1.1 ether, 2 ether, true) returns (
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertEq(got, 1.1 ether, "Taker did not get enough");
      assertEq(gave, 1.1 ether, "Taker did not get enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_mo_fillGives() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 1.1 ether, 2 ether, false) returns (
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertEq(got, 2 ether, "Taker did not get enough");
      assertEq(gave, 2 ether, "Taker did not get enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_mo_fillGivesAll_no_approved_fails() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 0 ether, 3 ether, false) {} catch Error(
      string memory errorMsg
    ) {
      assertEq(errorMsg, "mgv/takerTransferFail", "Invalid revert message");
    }
  }

  function test_mo_fillGivesAll_succeeds() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 3 ether);
    try mgv.marketOrder(base, quote, 0 ether, 3 ether, false) returns (
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertEq(got, 3 ether, "Taker did not get enough");
      assertEq(gave, 3 ether, "Taker did not get enough");
    } catch {
      fail("Transaction should not revert");
    }
  }

  function test_taker_reimbursed_if_maker_doesnt_pay() public {
    uint mkr_provision = getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = refusemkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail"
    );
    (uint successes, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    assertTrue(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    emit Credit(address(refusemkr), mkr_provision - penalty);
  }

  function test_taker_reverts_on_penalty_triggers_revert() public {
    uint ofr = refusemkr.newOffer(1 ether, 1 ether, 50_000, 0);
    refuseReceive = true;
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      fail("Snipe should fail because taker has reverted on penalty send.");
    } catch Error(string memory r) {
      assertEq(r, "mgv/sendPenaltyReverted", "wrong revert reason");
    }
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_base() public {
    uint mkr_provision = getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook

    baseT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail"
    );
    (uint successes, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    assertTrue(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function test_taker_reimbursed_if_maker_is_blacklisted_for_quote() public {
    uint mkr_provision = getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerReceiveFail"); // status visible in the posthook

    quoteT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    expectFrom(address(mgv));

    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerReceiveFail"
    );
    (uint successes, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    assertTrue(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function test_taker_collects_failing_offer() public {
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    (uint successes, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(
      takerGot == takerGave && takerGave == 0,
      "Transaction data should be 0"
    );
    assertTrue(address(this).balance > beforeWei, "Taker was not compensated");
  }

  function test_taker_reimbursed_if_maker_reverts() public {
    uint mkr_provision = getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    (uint successes, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    assertTrue(penalty > 0, "Taker should have been compensated");
    assertTrue(successes == 0, "Snipe should fail");
    assertTrue(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    assertTrue(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    emit Credit(address(failmkr), mkr_provision - penalty);
  }

  function test_taker_hasnt_approved_base_succeeds_order_with_fee() public {
    mgv.setFee(base, quote, 3);
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      assertEq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch {
      fail("Snipe should succeed");
    }
  }

  function test_taker_hasnt_approved_base_succeeds_order_wo_fee() public {
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      assertEq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch {
      fail("Snipe should succeed");
    }
  }

  function test_taker_hasnt_approved_quote_fails_order() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      fail("Order should fail when base is not mgv approved");
    } catch Error(string memory r) {
      assertEq(r, "mgv/takerTransferFail", "wrong revert reason");
    }
  }

  function test_simple_snipe() public {
    uint ofr = mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1.1 ether, 50_000];
    expectFrom(address(mgv));
    emit OfferSuccess(base, quote, ofr, address(this), 1 ether, 1.1 ether);
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint takerGot,
      uint takerGave,
      uint,
      uint
    ) {
      assertTrue(successes == 1, "Snipe should succeed");
      assertEq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount (taker)"
      );
      assertEq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        1.1 ether,
        "Incorrect delivered amount (maker)"
      );
      assertEq(takerGot, 1 ether, "Incorrect transaction information");
      assertEq(takerGave, 1.1 ether, "Incorrect transaction information");
    } catch {
      fail("Snipe should succeed");
    }
  }

  function test_simple_marketOrder() public {
    mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    mkr.newOffer(1.2 ether, 1 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");

    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    try mgv.marketOrder(base, quote, 2 ether, 4 ether, true) returns (
      uint takerGot,
      uint takerGave,
      uint,
      uint
    ) {
      assertEq(
        takerGot,
        2 ether,
        "Incorrect declared delivered amount (taker)"
      );
      assertEq(
        takerGave,
        2.3 ether,
        "Incorrect declared delivered amount (maker)"
      );
      assertEq(
        baseT.balanceOf(address(this)) - balTaker,
        2 ether,
        "Incorrect delivered amount (taker)"
      );
      assertEq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        2.3 ether,
        "Incorrect delivered amount (maker)"
      );
    } catch {
      fail("Market order should succeed");
    }
  }

  function test_simple_fillWants() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave, , ) = mgv.marketOrder(
      base,
      quote,
      1 ether,
      2 ether,
      true
    );
    assertEq(takerGot, 1 ether, "Incorrect declared delivered amount (taker)");
    assertEq(takerGave, 1 ether, "Incorrect declared delivered amount (maker)");
  }

  function test_simple_fillGives() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave, , ) = mgv.marketOrder(
      base,
      quote,
      1 ether,
      2 ether,
      false
    );
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_fillGives_at_0_wants_works() public {
    uint ofr = mkr.newOffer(0 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 2 ether, 0 ether, 300_000];

    (, uint takerGot, uint takerGave, , ) = mgv.snipes(
      base,
      quote,
      targets,
      false
    );
    assertEq(takerGave, 0 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillGives() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave, , ) = mgv.marketOrder(
      base,
      quote,
      0 ether,
      2 ether,
      false
    );
    assertEq(takerGave, 2 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 2 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_empty_wants_fillWants() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave, , ) = mgv.marketOrder(
      base,
      quote,
      0 ether,
      2 ether,
      true
    );
    assertEq(takerGave, 0 ether, "Incorrect declared delivered amount (maker)");
    assertEq(takerGot, 0 ether, "Incorrect declared delivered amount (taker)");
  }

  function test_taker_has_no_quote_fails_order() public {
    uint ofr = mkr.newOffer(100 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");

    quoteT.approve(address(mgv), 100 ether);
    baseT.approve(address(mgv), 1 ether); // not necessary since no fee

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 2 ether, 100 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      fail("Taker does not have enough quote tokens, order should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/takerTransferFail", "wrong revert reason");
    }
  }

  function maker_has_not_enough_base_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 100 ether, 100_000, 0);
    mkr.expect("mgv/makerTransferFail");
    // getting rid of base tokens
    //mkr.transferToken(baseT,address(this),5 ether);
    quoteT.approve(address(mgv), 0.5 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 50 ether, 0.5 ether, 100_000];
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      50 ether,
      0.5 ether,
      "mgv/makerTransferFail"
    );
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(successes == 0, "order should fail");
  }

  function maker_revert_is_logged_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    mkr.expect("mgv/makerRevert");
    mkr.shouldRevert(true);
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    mgv.snipes(base, quote, targets, true);
  }

  function snipe_on_higher_price_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 0.5 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 0.5 ether, 100_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(
      successes == 0,
      "Order should fail when order price is higher than offer"
    );
  }

  function snipe_on_higher_gas_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(
      successes == 0,
      "Order should fail when order gas is higher than offer"
    );
  }

  function detect_lowgas_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 100 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    bytes memory cd = abi.encodeWithSelector(
      mgv.snipes.selector,
      base,
      quote,
      targets,
      true
    );

    (bool noRevert, bytes memory data) = address(mgv).call{gas: 130000}(cd);
    if (noRevert) {
      fail("take should fail due to low gas");
    } else {
      revertEq(getReason(data), "mgv/notEnoughGasForMakerTrade");
    }
  }

  function snipe_on_lower_price_succeeds_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 2 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 2 ether, 100_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(
      successes == 1,
      "Order should succeed when order price is lower than offer"
    );
    // checking order was executed at Maker's price
    assertEq(
      baseT.balanceOf(address(this)) - balTaker,
      1 ether,
      "Incorrect delivered amount (taker)"
    );
    assertEq(
      quoteT.balanceOf(address(mkr)) - balMaker,
      1 ether,
      "Incorrect delivered amount (maker)"
    );
  }

  /* Note as for jan 5 2020: by locally pushing the block gas limit to 38M, you can go up to 162 levels of recursion before hitting "revert for an unknown reason" -- I'm assuming that's the stack limit. */
  function recursion_depth_is_acceptable_test() public {
    for (uint i = 0; i < 50; i++) {
      mkr.newOffer(0.001 ether, 0.001 ether, 50_000, i);
    }
    quoteT.approve(address(mgv), 10 ether);
    // 6/1/20 : ~50k/offer with optims
    //uint g = gasleft();
    //console.log("gas used per offer: ",(g-gasleft())/50);
  }

  function partial_fill_test() public {
    quoteT.approve(address(mgv), 1 ether);
    mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 1);
    mkr.expect("mgv/tradeSuccess");
    (uint takerGot, , , ) = mgv.marketOrder(
      base,
      quote,
      0.15 ether,
      0.15 ether,
      true
    );
    assertEq(takerGot, 0.15 ether, "Incorrect declared partial fill amount");
    assertEq(
      baseT.balanceOf(address(this)),
      0.15 ether,
      "incorrect partial fill"
    );
  }

  // ! unreliable test, depends on gas use
  function market_order_stops_for_high_price_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer((i + 1) * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 2 * (0.1 ether + 0.1 ether);
    uint takerGives = 2 * (0.1 ether + 0.2 ether);
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives, true);
  }

  // ! unreliable test, depends on gas use
  function market_order_stops_for_filled_mid_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer(i * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.05 ether;
    uint takerGives = 0.1 ether + 0.1 ether;
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives, true);
  }

  function market_order_stops_for_filled_after_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    for (uint i = 0; i < 10; i++) {
      mkr.newOffer(i * (0.1 ether), 0.1 ether, 50_000, i);
    }
    mkr.expect("mgv/tradeSuccess");
    // first two offers are at right price
    uint takerWants = 0.1 ether + 0.1 ether;
    uint takerGives = 0.1 ether + 0.2 ether;
    mgv.marketOrder{gas: 350_000}(base, quote, takerWants, takerGives, true);
  }

  function takerWants_wider_than_160_bits_fails_marketOrder_test() public {
    try mgv.marketOrder(base, quote, 2**160, 1, true) {
      fail("TakerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function snipe_with_0_wants_ejects_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    uint mkrBal = baseT.balanceOf(address(mkr));
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 0);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 1 ether, 50_000];
    (uint successes, , , , ) = mgv.snipes(base, quote, targets, true);
    assertTrue(successes == 1, "snipe should succeed");
    assertEq(mgv.best(base, quote), 0, "offer should be gone");
    assertEq(
      baseT.balanceOf(address(mkr)),
      mkrBal,
      "mkr balance should not change"
    );
  }

  function unsafe_gas_left_fails_order_test() public {
    mgv.setGasbase(base, quote, 1);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 120_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 120_000];
    try mgv.snipes{gas: 120_000}(base, quote, targets, true) {
      fail("unsafe gas amount, order should fail");
    } catch Error(string memory r) {
      assertEq(r, "mgv/notEnoughGasForMakerTrade", "wrong revert reason");
    }
  }

  function marketOrder_on_empty_book_returns_test() public {
    try mgv.marketOrder(base, quote, 1 ether, 1 ether, true) {
      succeed();
    } catch Error(string memory) {
      fail("market order on empty book should not fail");
    }
  }

  function marketOrder_on_empty_book_does_not_leave_lock_on_test() public {
    mgv.marketOrder(base, quote, 1 ether, 1 ether, true);
    assertTrue(
      !mgv.locked(base, quote),
      "mgv should not be locked after marketOrder on empty OB"
    );
  }

  function takerWants_is_zero_succeeds_test() public {
    try mgv.marketOrder(base, quote, 0, 1 ether, true) returns (
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertEq(got, 0, "Taker got too much");
      assertEq(gave, 0 ether, "Taker gave too much");
    } catch {
      fail("Unexpected revert");
    }
  }

  function takerGives_is_zero_succeeds_test() public {
    try mgv.marketOrder(base, quote, 1 ether, 0, true) returns (
      uint got,
      uint gave,
      uint,
      uint
    ) {
      assertEq(got, 0, "Taker got too much");
      assertEq(gave, 0 ether, "Taker gave too much");
    } catch {
      fail("Unexpected revert");
    }
  }
}
