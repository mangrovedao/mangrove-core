// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract TakerOperations_Test is HasMgvEvents {
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

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);

    mkr = MakerSetup.setup(mgv, base, quote);
    refusemkr = MakerSetup.setup(mgv, base, quote, 1);
    failmkr = MakerSetup.setup(mgv, base, quote, 2);

    address(mkr).transfer(10 ether);
    address(refusemkr).transfer(10 ether);
    address(failmkr).transfer(10 ether);

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

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "taker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");

    Display.register(address(mkr), "maker");
    Display.register(address(failmkr), "reverting maker");
    Display.register(address(refusemkr), "refusing maker");
  }

  function snipe_reverts_if_taker_is_blacklisted_for_quote_test() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    quoteT.blacklists(address(this));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("Snipe should fail");
    } catch Error(string memory errorMsg) {
      TestEvents.eq(
        errorMsg,
        "mgv/takerTransferFail",
        "Unexpected revert reason"
      );
      TestEvents.eq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
    }
  }

  function snipe_reverts_if_taker_is_blacklisted_for_base_test() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    baseT.blacklists(address(this));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("Snipe should fail");
    } catch Error(string memory errorMsg) {
      TestEvents.eq(
        errorMsg,
        "mgv/MgvFailToPayTaker",
        "Unexpected revert reason"
      );
      TestEvents.eq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
    }
  }

  function snipe_fails_if_price_has_changed_test() public {
    uint weiBalanceBefore = mgv.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 0.5 ether, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave
    ) {
      TestEvents.check(successes == 0, "Snipe should fail");
      TestEvents.eq(
        weiBalanceBefore,
        mgv.balanceOf(address(this)),
        "Taker should not take bounty"
      );
      TestEvents.check(
        (got == gave && gave == 0),
        "Taker should not give or take anything"
      );
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function taker_cannot_drain_maker_test() public {
    mgv.setDensity(base, quote, 0);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(9, 10, 100_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1, 15 ether, 100_000];
    uint oldBal = quoteT.balanceOf(address(this));
    mgv.snipes(base, quote, targets, true);
    uint newBal = quoteT.balanceOf(address(this));
    TestEvents.more(oldBal, newBal, "oldBal should be strictly higher");
  }

  function snipe_fillWants_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.5 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 0.5 ether, "Taker did not get enough");
      TestEvents.eq(gave, 0.5 ether, "Taker did not give enough");
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  event Transfer(address indexed from, address indexed to, uint value);

  function snipe_fillWants_zero_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    TestEvents.check(
      TestUtils.hasOffer(mgv, base, quote, ofr),
      "Offer should be in the book"
    );
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint got,
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 0 ether, "Taker had too much");
      TestEvents.eq(gave, 0 ether, "Taker gave too much");
      TestEvents.check(
        !TestUtils.hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
      TestEvents.expectFrom(address(quote));
      emit Transfer(address(this), address(mgv), 0);
      emit Transfer(address(mgv), address(mkr), 0);
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function snipe_free_offer_fillWants_respects_spec_test() public {
    uint ofr = mkr.newOffer(0, 1 ether, 100_000, 0);
    TestEvents.check(
      TestUtils.hasOffer(mgv, base, quote, ofr),
      "Offer should be in the book"
    );
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
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 0.1 ether, "Wrong got value");
      TestEvents.eq(gave, 0 ether, "Wrong gave value");
      TestEvents.check(
        !TestUtils.hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function snipe_free_offer_fillGives_respects_spec_test() public {
    uint ofr = mkr.newOffer(0, 1 ether, 100_000, 0);
    TestEvents.check(
      TestUtils.hasOffer(mgv, base, quote, ofr),
      "Offer should be in the book"
    );
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
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 1 ether, "Wrong got value");
      TestEvents.eq(gave, 0 ether, "Wrong gave value");
      TestEvents.check(
        !TestUtils.hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function snipe_fillGives_zero_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    TestEvents.check(
      TestUtils.hasOffer(mgv, base, quote, ofr),
      "Offer should be in the book"
    );
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 0 ether, "Taker had too much");
      TestEvents.eq(gave, 0 ether, "Taker gave too much");
      TestEvents.check(
        !TestUtils.hasOffer(mgv, base, quote, ofr),
        "Offer should not be in the book"
      );
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function snipe_fillGives_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.5 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, false) returns (
      uint successes,
      uint got,
      uint gave
    ) {
      TestEvents.check(successes == 1, "Snipe should not fail");
      TestEvents.eq(got, 1 ether, "Taker did not get enough");
      TestEvents.eq(gave, 1 ether, "Taker did not get enough");
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function mo_fillWants_test() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 1.1 ether, 2 ether, true) returns (
      uint got,
      uint gave
    ) {
      TestEvents.eq(got, 1.1 ether, "Taker did not get enough");
      TestEvents.eq(gave, 1.1 ether, "Taker did not get enough");
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function mo_fillGives_test() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 1.1 ether, 2 ether, false) returns (
      uint got,
      uint gave
    ) {
      TestEvents.eq(got, 2 ether, "Taker did not get enough");
      TestEvents.eq(gave, 2 ether, "Taker did not get enough");
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function mo_fillGivesAll_no_approved_fails_test() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 2 ether);
    try mgv.marketOrder(base, quote, 0 ether, 3 ether, false) {} catch Error(
      string memory errorMsg
    ) {
      TestEvents.eq(
        errorMsg,
        "mgv/takerTransferFail",
        "Invalid revert message"
      );
    }
  }

  function mo_fillGivesAll_succeeds_test() public {
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/tradeSuccess"); // trade should be OK on the maker side
    quoteT.approve(address(mgv), 3 ether);
    try mgv.marketOrder(base, quote, 0 ether, 3 ether, false) returns (
      uint got,
      uint gave
    ) {
      TestEvents.eq(got, 3 ether, "Taker did not get enough");
      TestEvents.eq(gave, 3 ether, "Taker did not get enough");
    } catch {
      TestEvents.fail("Transaction should not revert");
    }
  }

  function taker_reimbursed_if_maker_doesnt_pay_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = refusemkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(successes == 0, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail"
    );
    emit Credit(address(refusemkr), mkr_provision - penalty);
  }

  function taker_reverts_on_penalty_triggers_revert_test() public {
    uint ofr = refusemkr.newOffer(1 ether, 1 ether, 50_000, 0);
    refuseReceive = true;
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail(
        "Snipe should fail because taker has reverted on penalty send."
      );
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/sendPenaltyReverted", "wrong revert reason");
    }
  }

  function taker_reimbursed_if_maker_is_blacklisted_for_base_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerTransferFail"); // status visible in the posthook

    baseT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(successes == 0, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerTransferFail"
    );
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function taker_reimbursed_if_maker_is_blacklisted_for_quote_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 100_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    mkr.expect("mgv/makerReceiveFail"); // status visible in the posthook

    quoteT.blacklists(address(mkr));
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(successes == 0, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));

    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerReceiveFail"
    );
    emit Credit(address(mkr), mkr_provision - penalty);
  }

  function taker_collects_failing_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 0, 100_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    TestEvents.check(successes == 0, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Transaction data should be 0"
    );
    TestEvents.check(
      address(this).balance > beforeWei,
      "Taker was not compensated"
    );
  }

  function taker_reimbursed_if_maker_reverts_test() public {
    uint mkr_provision = TestUtils.getProvision(mgv, base, quote, 50_000);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = failmkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint beforeQuote = quoteT.balanceOf(address(this));
    uint beforeWei = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 100_000];
    (uint successes, uint takerGot, uint takerGave) = mgv.snipes(
      base,
      quote,
      targets,
      true
    );
    uint penalty = address(this).balance - beforeWei;
    TestEvents.check(penalty > 0, "Taker should have been compensated");
    TestEvents.check(successes == 0, "Snipe should fail");
    TestEvents.check(
      takerGot == takerGave && takerGave == 0,
      "Incorrect transaction information"
    );
    TestEvents.check(
      beforeQuote == quoteT.balanceOf(address(this)),
      "taker balance should not be lower if maker doesn't pay back"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
    emit Credit(address(failmkr), mkr_provision - penalty);
  }

  function taker_hasnt_approved_base_succeeds_order_with_fee_test() public {
    mgv.setFee(base, quote, 3);
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function taker_hasnt_approved_base_succeeds_order_wo_fee_test() public {
    uint balTaker = baseT.balanceOf(address(this));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount"
      );
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function taker_hasnt_approved_quote_fails_order_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail("Order should fail when base is not mgv approved");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/takerTransferFail", "wrong revert reason");
    }
  }

  function simple_snipe_test() public {
    uint ofr = mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1.1 ether, 50_000];
    try mgv.snipes(base, quote, targets, true) returns (
      uint successes,
      uint takerGot,
      uint takerGave
    ) {
      TestEvents.check(successes == 1, "Snipe should succeed");
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        1 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        1.1 ether,
        "Incorrect delivered amount (maker)"
      );
      TestEvents.eq(takerGot, 1 ether, "Incorrect transaction information");
      TestEvents.eq(takerGave, 1.1 ether, "Incorrect transaction information");
      TestEvents.expectFrom(address(mgv));
      emit OfferSuccess(base, quote, ofr, address(this), 1 ether, 1.1 ether);
    } catch {
      TestEvents.fail("Snipe should succeed");
    }
  }

  function simple_marketOrder_test() public {
    mkr.newOffer(1.1 ether, 1 ether, 50_000, 0);
    mkr.newOffer(1.2 ether, 1 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");

    baseT.approve(address(mgv), 10 ether);
    quoteT.approve(address(mgv), 10 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    try mgv.marketOrder(base, quote, 2 ether, 4 ether, true) returns (
      uint takerGot,
      uint takerGave
    ) {
      TestEvents.eq(
        takerGot,
        2 ether,
        "Incorrect declared delivered amount (taker)"
      );
      TestEvents.eq(
        takerGave,
        2.3 ether,
        "Incorrect declared delivered amount (maker)"
      );
      TestEvents.eq(
        baseT.balanceOf(address(this)) - balTaker,
        2 ether,
        "Incorrect delivered amount (taker)"
      );
      TestEvents.eq(
        quoteT.balanceOf(address(mkr)) - balMaker,
        2.3 ether,
        "Incorrect delivered amount (maker)"
      );
    } catch {
      TestEvents.fail("Market order should succeed");
    }
  }

  function simple_fillWants_test() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave) = mgv.marketOrder(
      base,
      quote,
      1 ether,
      2 ether,
      true
    );
    TestEvents.eq(
      takerGot,
      1 ether,
      "Incorrect declared delivered amount (taker)"
    );
    TestEvents.eq(
      takerGave,
      1 ether,
      "Incorrect declared delivered amount (maker)"
    );
  }

  function simple_fillGives_test() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave) = mgv.marketOrder(
      base,
      quote,
      1 ether,
      2 ether,
      false
    );
    TestEvents.eq(
      takerGave,
      2 ether,
      "Incorrect declared delivered amount (maker)"
    );
    TestEvents.eq(
      takerGot,
      2 ether,
      "Incorrect declared delivered amount (taker)"
    );
  }

  function fillGives_at_0_wants_works_test() public {
    uint ofr = mkr.newOffer(0 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 2 ether, 0 ether, 300_000];

    (, uint takerGot, uint takerGave) = mgv.snipes(base, quote, targets, false);
    TestEvents.eq(
      takerGave,
      0 ether,
      "Incorrect declared delivered amount (maker)"
    );
    TestEvents.eq(
      takerGot,
      2 ether,
      "Incorrect declared delivered amount (taker)"
    );
  }

  function empty_wants_fillGives_test() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave) = mgv.marketOrder(
      base,
      quote,
      0 ether,
      2 ether,
      false
    );
    TestEvents.eq(
      takerGave,
      2 ether,
      "Incorrect declared delivered amount (maker)"
    );
    TestEvents.eq(
      takerGot,
      2 ether,
      "Incorrect declared delivered amount (taker)"
    );
  }

  function empty_wants_fillWants_test() public {
    mkr.newOffer(2 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");
    quoteT.approve(address(mgv), 10 ether);

    (uint takerGot, uint takerGave) = mgv.marketOrder(
      base,
      quote,
      0 ether,
      2 ether,
      true
    );
    TestEvents.eq(
      takerGave,
      0 ether,
      "Incorrect declared delivered amount (maker)"
    );
    TestEvents.eq(
      takerGot,
      0 ether,
      "Incorrect declared delivered amount (taker)"
    );
  }

  function taker_has_no_quote_fails_order_test() public {
    uint ofr = mkr.newOffer(100 ether, 2 ether, 50_000, 0);
    mkr.expect("mgv/tradeSuccess");

    quoteT.approve(address(mgv), 100 ether);
    baseT.approve(address(mgv), 1 ether); // not necessary since no fee

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 2 ether, 100 ether, 100_000];
    try mgv.snipes(base, quote, targets, true) {
      TestEvents.fail(
        "Taker does not have enough quote tokens, order should fail"
      );
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/takerTransferFail", "wrong revert reason");
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
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 0, "order should fail");
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      50 ether,
      0.5 ether,
      "mgv/makerTransferFail"
    );
  }

  function maker_revert_is_logged_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    mkr.expect("mgv/makerRevert");
    mkr.shouldRevert(true);
    quoteT.approve(address(mgv), 1 ether);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    mgv.snipes(base, quote, targets, true);
    TestEvents.expectFrom(address(mgv));
    emit OfferFail(
      base,
      quote,
      ofr,
      address(this),
      1 ether,
      1 ether,
      "mgv/makerRevert"
    );
  }

  function snipe_on_higher_price_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 0.5 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 0.5 ether, 100_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(
      successes == 0,
      "Order should fail when order price is higher than offer"
    );
  }

  function snipe_on_higher_gas_fails_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 1 ether);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(
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
      TestEvents.fail("take should fail due to low gas");
    } else {
      TestUtils.revertEq(
        TestUtils.getReason(data),
        "mgv/notEnoughGasForMakerTrade"
      );
    }
  }

  function snipe_on_lower_price_succeeds_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 100_000, 0);
    quoteT.approve(address(mgv), 2 ether);
    uint balTaker = baseT.balanceOf(address(this));
    uint balMaker = quoteT.balanceOf(address(mkr));

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 2 ether, 100_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(
      successes == 1,
      "Order should succeed when order price is lower than offer"
    );
    // checking order was executed at Maker's price
    TestEvents.eq(
      baseT.balanceOf(address(this)) - balTaker,
      1 ether,
      "Incorrect delivered amount (taker)"
    );
    TestEvents.eq(
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
    (uint takerGot, ) = mgv.marketOrder(
      base,
      quote,
      0.15 ether,
      0.15 ether,
      true
    );
    TestEvents.eq(
      takerGot,
      0.15 ether,
      "Incorrect declared partial fill amount"
    );
    TestEvents.eq(
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
      TestEvents.fail("TakerWants > 160bits, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/mOrder/takerWants/160bits", "wrong revert reason");
    }
  }

  function snipe_with_0_wants_ejects_offer_test() public {
    quoteT.approve(address(mgv), 1 ether);
    uint mkrBal = baseT.balanceOf(address(mkr));
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 50_000, 0);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0, 1 ether, 50_000];
    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 1, "snipe should succeed");
    TestEvents.eq(mgv.best(base, quote), 0, "offer should be gone");
    TestEvents.eq(
      baseT.balanceOf(address(mkr)),
      mkrBal,
      "mkr balance should not change"
    );
  }

  function unsafe_gas_left_fails_order_test() public {
    mgv.setGasbase(base, quote, 1, 1);
    quoteT.approve(address(mgv), 1 ether);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 120_000, 0);
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 120_000];
    try mgv.snipes{gas: 120_000}(base, quote, targets, true) {
      TestEvents.fail("unsafe gas amount, order should fail");
    } catch Error(string memory r) {
      TestEvents.eq(r, "mgv/notEnoughGasForMakerTrade", "wrong revert reason");
    }
  }

  function marketOrder_on_empty_book_returns_test() public {
    try mgv.marketOrder(base, quote, 1 ether, 1 ether, true) {
      TestEvents.succeed();
    } catch Error(string memory) {
      TestEvents.fail("market order on empty book should not fail");
    }
  }

  function marketOrder_on_empty_book_does_not_leave_lock_on_test() public {
    mgv.marketOrder(base, quote, 1 ether, 1 ether, true);
    TestEvents.check(
      !mgv.locked(base, quote),
      "mgv should not be locked after marketOrder on empty OB"
    );
  }

  function takerWants_is_zero_succeeds_test() public {
    try mgv.marketOrder(base, quote, 0, 1 ether, true) returns (
      uint got,
      uint gave
    ) {
      TestEvents.eq(got, 0, "Taker got too much");
      TestEvents.eq(gave, 0 ether, "Taker gave too much");
    } catch {
      TestEvents.fail("Unexpected revert");
    }
  }

  function takerGives_is_zero_succeeds_test() public {
    try mgv.marketOrder(base, quote, 1 ether, 0, true) returns (
      uint got,
      uint gave
    ) {
      TestEvents.eq(got, 0, "Taker got too much");
      TestEvents.eq(gave, 0 ether, "Taker gave too much");
    } catch {
      TestEvents.fail("Unexpected revert");
    }
  }
}
