// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma abicoder v2;

import "../AbstractMangrove.sol";
import {IMaker as IM, MgvLib} from "../MgvLib.sol";
import "hardhat/console.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";

/* The following constructs an ERC20 with a transferFrom callback method,
   and a TestTaker which throws away any funds received upon getting
   a callback.
*/
contract InvertedTakerOperations_Test is ITaker, HasMgvEvents {
  TestToken baseT;
  TestToken quoteT;
  address base;
  address quote;
  AbstractMangrove mgv;
  TestMaker mkr;
  bytes4 takerTrade_bytes;
  uint baseBalance;
  uint quoteBalance;

  receive() external payable {}

  function a_beforeAll() public {
    baseT = TokenSetup.setup("A", "$A");
    quoteT = TokenSetup.setup("B", "$B");
    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT, true);

    mkr = MakerSetup.setup(mgv, base, quote);

    address(mkr).transfer(10 ether);
    mkr.provisionMgv(1 ether);
    mkr.approveMgv(baseT, 10 ether);

    baseT.mint(address(mkr), 5 ether);
    quoteT.mint(address(this), 5 ether);
    quoteT.approve(address(mgv), 5 ether);
    baseBalance = baseT.balanceOf(address(this));
    quoteBalance = quoteT.balanceOf(address(this));

    Display.register(msg.sender, "Test Runner");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(mkr), "maker");
    Display.register(mgv.vault(), "vault");
  }

  uint toPay;

  function checkPay(
    address,
    address,
    uint totalGives
  ) external {
    TestEvents.eq(
      toPay,
      totalGives,
      "totalGives should be the sum of taker flashborrows"
    );
  }

  bool skipCheck;

  function takerTrade(
    address _base,
    address _quote,
    uint totalGot,
    uint totalGives
  ) public override {
    require(msg.sender == address(mgv));
    if (!skipCheck) {
      TestEvents.eq(
        baseBalance + totalGot,
        baseT.balanceOf(address(this)),
        "totalGot should be sum of maker flashloans"
      );
    }
    (bool success, ) = address(this).call(
      abi.encodeWithSelector(takerTrade_bytes, _base, _quote, totalGives)
    );
    require(success, "TradeFail");
  }

  function taker_gets_sum_of_borrows_in_execute_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.checkPay.selector;
    toPay = 0.2 ether;
    (, uint gave) = mgv.marketOrder(base, quote, 0.2 ether, 0.2 ether, true);
    TestEvents.eq(
      quoteBalance - gave,
      quoteT.balanceOf(address(this)),
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

  function taker_reverts_during_trade_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint _ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.revertTrade.selector;
    skipCheck = true;
    try mgv.marketOrder(base, quote, 0.2 ether, 0.2 ether, true) {
      TestEvents.fail("Market order should have reverted");
    } catch Error(string memory reason) {
      TestEvents.eq("TradeFail", reason, "Unexpected throw");
      TestEvents.check(
        TestUtils.hasOffer(mgv, address(base), address(quote), ofr),
        "Offer 1 should be present"
      );
      TestEvents.check(
        TestUtils.hasOffer(mgv, address(base), address(quote), _ofr),
        "Offer 2 should be present"
      );
    }
  }

  function refuseFeeTrade(
    address _base,
    address,
    uint
  ) external {
    IERC20(_base).approve(address(mgv), 0);
  }

  function refusePayTrade(
    address,
    address _quote,
    uint
  ) external {
    IERC20(_quote).approve(address(mgv), 0);
  }

  function taker_refuses_to_deliver_during_trade_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.refusePayTrade.selector;
    try mgv.marketOrder(base, quote, 0.2 ether, 0.2 ether, true) {
      TestEvents.fail("Market order should have reverted");
    } catch Error(string memory reason) {
      TestEvents.eq(
        reason,
        "mgv/takerFailToPayTotal",
        "Unexpected throw message"
      );
    }
  }

  function vault_receives_quote_tokens_if_maker_is_blacklisted_for_quote_test()
    public
  {
    takerTrade_bytes = this.noop.selector;
    quoteT.blacklists(address(mkr));
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    address vault = address(1);
    mgv.setVault(vault);
    uint vaultBal = quoteT.balanceOf(vault);

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, 50_000];

    (uint successes, , ) = mgv.snipes(base, quote, targets, true);
    TestEvents.check(successes == 1, "Trade should succeed");
    TestEvents.eq(
      quoteT.balanceOf(vault) - vaultBal,
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
    (uint successes, uint totalGot, uint totalGave) = mgv.snipes(
      _base,
      _quote,
      targets,
      true
    );
    TestEvents.check(successes == 1, "Snipe on reentrancy should succeed");
    TestEvents.eq(totalGot, 0.1 ether, "Incorrect totalGot");
    TestEvents.eq(totalGave, 0.1 ether, "Incorrect totalGave");
  }

  function taker_snipe_mgv_during_trade_test() public {
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    takerTrade_bytes = this.reenter.selector;
    (uint got, uint gave) = mgv.marketOrder(
      base,
      quote,
      0.1 ether,
      0.1 ether,
      true
    );
    TestEvents.eq(
      quoteBalance - gave - 0.1 ether,
      quoteT.balanceOf(address(this)),
      "Incorrect transfer (gave) during reentrancy"
    );
    TestEvents.eq(
      baseBalance + got + 0.1 ether,
      baseT.balanceOf(address(this)),
      "Incorrect transfer (got) during reentrancy"
    );
    TestEvents.expectFrom(address(mgv));
    emit OfferSuccess(base, quote, 1, address(this), 0.1 ether, 0.1 ether);
    emit OfferSuccess(base, quote, 2, address(this), 0.1 ether, 0.1 ether);
  }

  function taker_pays_back_correct_amount_1_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quoteT.balanceOf(address(this));
    takerTrade_bytes = this.noop.selector;
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.05 ether, 0.05 ether, 100_000];
    mgv.snipes(base, quote, targets, true);
    TestEvents.eq(
      quoteT.balanceOf(address(this)),
      bal - 0.05 ether,
      "wrong taker balance"
    );
  }

  function taker_pays_back_correct_amount_2_test() public {
    uint ofr = mkr.newOffer(0.1 ether, 0.1 ether, 100_000, 0);
    uint bal = quoteT.balanceOf(address(this));
    takerTrade_bytes = this.noop.selector;
    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 0.02 ether, 0.02 ether, 100_000];
    mgv.snipes(base, quote, targets, true);
    TestEvents.eq(
      quoteT.balanceOf(address(this)),
      bal - 0.02 ether,
      "wrong taker balance"
    );
  }
}
