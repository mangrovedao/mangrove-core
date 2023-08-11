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

    mkr = setupMaker($(base), $(quote), "maker");

    deal($(base), address(mkr), 5 ether);
    mkr.provisionMgv(1 ether);
    mkr.approveMgv(base, 10 ether);

    baseBalance = base.balanceOf($(this));
    quoteBalance = quote.balanceOf($(this));
  }

  uint toPay;

  function checkPay(address, address, uint totalGives) internal {
    assertEq(toPay, totalGives, "totalGives should be the sum of taker flashborrows");
  }

  bool skipCheck;

  function(address, address, uint) internal _takerTrade; // stored function pointer

  function takerTrade(address _$base, address _$quote, uint totalGot, uint totalGives) public override {
    require(msg.sender == $(mgv));
    if (!skipCheck) {
      assertEq(baseBalance + totalGot, base.balanceOf($(this)), "totalGot should be sum of maker flashloans");
    }
    _takerTrade(_$base, _$quote, totalGives);
    // require(false);
  }

  function test_taker_gets_sum_of_borrows_in_execute() public {
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = checkPay;
    toPay = 0.2 ether;
    (, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), DEFAULT_TICKSCALE, 0.2 ether, 0.2 ether, true);
    assertEq(quoteBalance - gave, quote.balanceOf($(this)), "totalGave should be sum of taker flashborrows");
  }

  string constant REVERT_TRADE_REASON = "InvertedTakerOperationsTest/TradeFail";

  function revertTrade(address, address, uint) internal pure {
    revert(REVERT_TRADE_REASON);
  }

  function test_taker_reverts_during_trade() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    uint _ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = revertTrade;
    skipCheck = true;
    try mgv.marketOrderByVolume($(base), $(quote), DEFAULT_TICKSCALE, 0.2 ether, 0.2 ether, true) {
      fail("Market order should have reverted");
    } catch Error(string memory reason) {
      assertEq(REVERT_TRADE_REASON, reason, "Unexpected throw");
      assertTrue(mgv.offers($(base), $(quote), DEFAULT_TICKSCALE, ofr).isLive(), "Offer 1 should be present");
      assertTrue(mgv.offers($(base), $(quote), DEFAULT_TICKSCALE, _ofr).isLive(), "Offer 2 should be present");
    }
  }

  function refuseFeeTrade(address _base, address, uint) external {
    IERC20(_base).approve($(mgv), 0);
  }

  function refusePayTrade(address, address _quote, uint) internal {
    IERC20(_quote).approve($(mgv), 0);
  }

  function test_taker_refuses_to_deliver_during_trade() public {
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = refusePayTrade;
    try mgv.marketOrderByVolume($(base), $(quote), DEFAULT_TICKSCALE, 0.2 ether, 0.2 ether, true) {
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

    int logPrice = mgv.offers($(base), $(quote), DEFAULT_TICKSCALE, ofr).logPrice();
    (uint successes,,,,) =
      mgv.snipes($(base), $(quote), DEFAULT_TICKSCALE, wrap_dynamic([ofr, uint(logPrice), 1 ether, 50_000]), true);
    assertTrue(successes == 1, "Trade should succeed");
    assertEq(quote.balanceOf(address(mgv)) - mgvQuoteBal, 1 ether, "Mgv balance should have increased");
  }

  function noop(address, address, uint) internal {}

  function reenter(address _base, address _quote, uint) internal {
    _takerTrade = noop;
    skipCheck = true;
    uint ofr = 2;
    int logPrice = mgv.offers(_base, _quote, DEFAULT_TICKSCALE, ofr).logPrice();
    (uint successes, uint totalGot, uint totalGave,,) =
      mgv.snipes(_base, _quote, DEFAULT_TICKSCALE, wrap_dynamic([ofr, uint(logPrice), 0.1 ether, 100_000]), true);
    assertTrue(successes == 1, "Snipe on reentrancy should succeed");
    assertEq(totalGot, 0.1 ether, "Incorrect totalGot");
    assertEq(totalGave, 0.1 ether, "Incorrect totalGave");
  }

  function test_taker_snipe_mgv_during_trade() public {
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    _takerTrade = reenter;
    expectFrom($(mgv));
    emit OfferSuccess($(base), $(quote), DEFAULT_TICKSCALE, 1, $(this), 0.1 ether, 0.1 ether);
    expectFrom($(mgv));
    emit OfferSuccess($(base), $(quote), DEFAULT_TICKSCALE, 2, $(this), 0.1 ether, 0.1 ether);
    (uint got, uint gave,,) = mgv.marketOrderByVolume($(base), $(quote), DEFAULT_TICKSCALE, 0.1 ether, 0.1 ether, true);
    assertEq(quoteBalance - gave - 0.1 ether, quote.balanceOf($(this)), "Incorrect transfer (gave) during reentrancy");
    assertEq(baseBalance + got + 0.1 ether, base.balanceOf($(this)), "Incorrect transfer (got) during reentrancy");
  }

  function test_taker_pays_back_correct_amount_1() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    int logPrice = mgv.offers($(base), $(quote), DEFAULT_TICKSCALE, ofr).logPrice();
    uint bal = quote.balanceOf($(this));
    _takerTrade = noop;
    mgv.snipes($(base), $(quote), DEFAULT_TICKSCALE, wrap_dynamic([ofr, uint(logPrice), 0.05 ether, 100_000]), true);
    assertEq(quote.balanceOf($(this)), bal - 0.05 ether, "wrong taker balance");
  }

  function test_taker_pays_back_correct_amount_2() public {
    uint ofr = mkr.newOfferByVolume(0.1 ether, 0.1 ether, 100_000, 0);
    int logPrice = mgv.offers($(base), $(quote), DEFAULT_TICKSCALE, ofr).logPrice();
    uint bal = quote.balanceOf($(this));
    _takerTrade = noop;
    mgv.snipes($(base), $(quote), DEFAULT_TICKSCALE, wrap_dynamic([ofr, uint(logPrice), 0.02 ether, 100_000]), true);
    assertEq(quote.balanceOf($(this)), bal - 0.02 ether, "wrong taker balance");
  }
}
