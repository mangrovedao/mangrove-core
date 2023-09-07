// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.*/
contract InvertedTakerOperationsTest is ITaker, MangroveTest {
  TestMaker mkr;
  uint baseBalance;
  uint quoteBalance;

  function setUp() public override {
    options.invertedMangrove = true;
    super.setUp();

    deal($(quote), $(this), 10 ether);

    mkr = setupMaker(olKey, "maker");

    deal($(base), address(mkr), 5 ether);
    mkr.provisionMgv(1 ether);
    mkr.approveMgv(base, 10 ether);

    baseBalance = base.balanceOf($(this));
    quoteBalance = quote.balanceOf($(this));
  }

  uint toPay;

  function checkPay(OLKey calldata, uint totalGives) internal {
    assertEq(toPay, totalGives, "totalGives should be the sum of taker flashborrows");
  }

  bool skipCheck;

  function(OLKey calldata, uint) internal _takerTrade; // stored function pointer

  function takerTrade(OLKey calldata olKey, uint totalGot, uint totalGives) public override {
    require(msg.sender == $(mgv));
    if (!skipCheck) {
      assertEq(baseBalance + totalGot, base.balanceOf($(this)), "totalGot should be sum of maker flashloans");
    }
    _takerTrade(olKey, totalGives);
    // require(false);
  }

  function test_taker_gets_sum_of_borrows_in_execute() public {
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = checkPay;
    toPay = 0.2 ether;
    (, uint gave,,) = mgv.marketOrderByVolume(olKey, 0.2 ether, 0.2 ether, true);
    assertEq(quoteBalance - gave, quote.balanceOf($(this)), "totalGave should be sum of taker flashborrows");
  }

  string constant REVERT_TRADE_REASON = "InvertedTakerOperationsTest/TradeFail";

  function revertTrade(OLKey calldata, uint) internal pure {
    revert(REVERT_TRADE_REASON);
  }

  function test_taker_reverts_during_trade() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    uint _ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = revertTrade;
    skipCheck = true;
    try mgv.marketOrderByVolume(olKey, 0.2 ether, 0.2 ether, true) {
      fail("Market order should have reverted");
    } catch Error(string memory reason) {
      assertEq(REVERT_TRADE_REASON, reason, "Unexpected throw");
      assertTrue(mgv.offers(olKey, ofr).isLive(), "Offer 1 should be present");
      assertTrue(mgv.offers(olKey, _ofr).isLive(), "Offer 2 should be present");
    }
  }

  function refusePayTrade(OLKey calldata, uint) internal {
    IERC20(olKey.inbound).approve($(mgv), 0);
  }

  function test_taker_refuses_to_deliver_during_trade() public {
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = refusePayTrade;
    try mgv.marketOrderByVolume(olKey, 0.2 ether, 0.2 ether, true) {
      fail("Market order should have reverted");
    } catch Error(string memory reason) {
      assertEq(reason, "mgv/takerFailToPayTotal", "Unexpected throw message");
    }
  }

  function test_mgv_keeps_quote_tokens_if_maker_is_blacklisted_for_quote() public {
    _takerTrade = noop;
    quote.blacklists(address(mkr));
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    uint mgvQuoteBal = quote.balanceOf(address(mgv));

    int logPrice = mgv.offers(olKey, ofr).logPrice();
    mgv.marketOrderByLogPrice(olKey, logPrice, 1 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(quote.balanceOf(address(mgv)) - mgvQuoteBal, 1 ether, "Mgv balance should have increased");
  }

  function noop(OLKey calldata, uint) internal {}

  function reenter(OLKey calldata olKey, uint) internal {
    _takerTrade = noop;
    skipCheck = true;
    uint ofr = 2;
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    (uint totalGot, uint totalGave,,) = mgv.marketOrderByLogPrice(olKey, logPrice, 0.1 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(totalGot, 0.1 ether, "Incorrect totalGot");
    assertEq(totalGave, 0.1 ether, "Incorrect totalGave");
  }

  function test_taker_mo_mgv_during_trade() public {
    uint ofr1 = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    uint ofr2 = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = reenter;
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), $(this), ofr2, 0.1 ether, 0.1 ether);
    expectFrom($(mgv));
    emit OfferSuccess(olKey.hash(), $(this), ofr1, 0.1 ether, 0.1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume(olKey, 0.1 ether, 0.1 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr1), "ofr1 must be executed or test is void");
    assertTrue(mkr.makerExecuteWasCalled(ofr2), "ofr2 must be executed or test is void");
    assertEq(quoteBalance - gave - 0.1 ether, quote.balanceOf($(this)), "Incorrect transfer (gave) during reentrancy");
    assertEq(baseBalance + got + 0.1 ether, base.balanceOf($(this)), "Incorrect transfer (got) during reentrancy");
  }

  function test_taker_pays_back_correct_amount_1() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    uint bal = quote.balanceOf($(this));
    _takerTrade = noop;
    mgv.marketOrderByLogPrice(olKey, logPrice, 0.05 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(quote.balanceOf($(this)), bal - 0.05 ether, "wrong taker balance");
  }

  function test_taker_pays_back_correct_amount_2() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    int logPrice = mgv.offers(olKey, ofr).logPrice();
    uint bal = quote.balanceOf($(this));
    _takerTrade = noop;
    mgv.marketOrderByLogPrice(olKey, logPrice, 0.02 ether, true);
    assertTrue(mkr.makerExecuteWasCalled(ofr), "ofr must be executed or test is void");
    assertEq(quote.balanceOf($(this)), bal - 0.02 ether, "wrong taker balance");
  }
}
