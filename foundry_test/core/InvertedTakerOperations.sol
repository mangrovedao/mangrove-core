// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract InvertedTakerOperationsTest is ITaker, MangroveTest {
  TestMaker mkr;
  bytes4 takerTrade_bytes;
  uint baseBalance;
  uint quoteBalance;

  function setUp() public override {
    options.invertedMangrove = true;
    super.setUp();

    mkr = setupMaker($base, $quote, "maker");

    deal($base, address(mkr), 5 ether);
    mkr.provisionMgv(1 ether);
    mkr.approveMgv(base, 10 ether);

    baseBalance = base.balanceOf($this);
    quoteBalance = quote.balanceOf($this);
  }

  uint toPay;

  function checkPay(
    address,
    address,
    uint totalGives
  ) external {
    assertEq(
      toPay,
      totalGives,
      "totalGives should be the sum of taker flashborrows"
    );
  }

  bool skipCheck;

  function takerTrade(
    address _$base,
    address _quote,
    uint totalGot,
    uint totalGives
  ) public override {
    require(msg.sender == $mgv);
    if (!skipCheck) {
      assertEq(
        baseBalance + totalGot,
        base.balanceOf($this),
        "totalGot should be sum of maker flashloans"
      );
    }
    (bool success, ) = $this.call(
      abi.encodeWithSelector(takerTrade_bytes, _$base, _quote, totalGives)
    );
    require(success, "TradeFail");
  }

  function test_taker_gets_sum_of_borrows_in_execute() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.checkPay.selector;
    toPay = 0.2 ether;
    (, uint gave, , ) = mgv.marketOrder(
      $base,
      $quote,
      0.2 ether,
      0.2 ether,
      true
    );
    assertEq(
      quoteBalance - gave,
      quote.balanceOf($this),
      "totalGave should be sum of taker flashborrows"
    );
  }

  function revertTrade(
    address,
    address,
    uint
  ) external pure {
    require(false);
  }

  function test_taker_reverts_during_trade() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint _ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.revertTrade.selector;
    skipCheck = true;
    try mgv.marketOrder($base, $quote, 0.2 ether, 0.2 ether, true) {
      fail("Market order should have reverted");
    } catch Error(string memory reason) {
      assertEq("TradeFail", reason, "Unexpected throw");
      assertTrue(hasOffer($base, $quote, ofr), "Offer 1 should be present");
      assertTrue(hasOffer($base, $quote, _ofr), "Offer 2 should be present");
    }
  }

  function refuseFeeTrade(
    address _base,
    address,
    uint
  ) external {
    IERC20(_base).approve($mgv, 0);
  }

  function refusePayTrade(
    address,
    address _quote,
    uint
  ) external {
    IERC20(_quote).approve($mgv, 0);
  }

  function test_taker_refuses_to_deliver_during_trade() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.refusePayTrade.selector;
    try mgv.marketOrder($base, $quote, 0.2 ether, 0.2 ether, true) {
      fail("Market order should have reverted");
    } catch Error(string memory reason) {
      assertEq(reason, "mgv/takerFailToPayTotal", "Unexpected throw message");
    }
  }

  function test_vault_receives_quote_tokens_if_maker_is_blacklisted_for_quote()
    public
  {
    takerTrade_bytes = this.noop.selector;
    quote.blacklists(address(mkr));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    address vault = address(1);
    mgv.setVault(vault);
    uint vaultBal = quote.balanceOf(vault);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];

    (uint successes, , , , ) = mgv.snipes($base, $quote, targets, true);
    assertTrue(successes == 1, "Trade should succeed");
    assertEq(
      quote.balanceOf(vault) - vaultBal,
      1 ether,
      "Vault balance should have increased"
    );
  }

  function noop(
    address,
    address,
    uint
  ) external {}

  function reenter(
    address _base,
    address _quote,
    uint
  ) external {
    takerTrade_bytes = this.noop.selector;
    skipCheck = true;
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [uint(2), 0.1 ether, 0.1 ether, 100_000];
    (uint successes, uint totalGot, uint totalGave, , ) = mgv.snipes(
      _base,
      _quote,
      targets,
      true
    );
    assertTrue(successes == 1, "Snipe on reentrancy should succeed");
    assertEq(totalGot, 0.1 ether, "Incorrect totalGot");
    assertEq(totalGave, 0.1 ether, "Incorrect totalGave");
  }

  function test_taker_snipe_mgv_during_trade() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.reenter.selector;
    expectFrom($mgv);
    emit OfferSuccess($base, $quote, 1, $this, 0.1 ether, 0.1 ether);
    expectFrom($mgv);
    emit OfferSuccess($base, $quote, 2, $this, 0.1 ether, 0.1 ether);
    (uint got, uint gave, , ) = mgv.marketOrder(
      $base,
      $quote,
      0.1 ether,
      0.1 ether,
      true
    );
    assertEq(
      quoteBalance - gave - 0.1 ether,
      quote.balanceOf($this),
      "Incorrect transfer (gave) during reentrancy"
    );
    assertEq(
      baseBalance + got + 0.1 ether,
      base.balanceOf($this),
      "Incorrect transfer (got) during reentrancy"
    );
  }

  function test_taker_pays_back_correct_amount_1() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quote.balanceOf($this);
    takerTrade_bytes = this.noop.selector;
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.05 ether, 0.05 ether, 100_000];
    mgv.snipes($base, $quote, targets, true);
    assertEq(quote.balanceOf($this), bal - 0.05 ether, "wrong taker balance");
  }

  function test_taker_pays_back_correct_amount_2() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quote.balanceOf($this);
    takerTrade_bytes = this.noop.selector;
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.02 ether, 0.02 ether, 100_000];
    mgv.snipes($base, $quote, targets, true);
    assertEq(quote.balanceOf($this), bal - 0.02 ether, "wrong taker balance");
  }
}
