// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {Keyrocker, IMangrove} from "mgv_src/toy_strategies/offer_maker/Keyrocker.sol";

contract KeyrockerTest is MangroveTest {
  IERC20 internal weth;
  IERC20 internal usdc;

  PolygonFork internal fork;

  address payable internal taker;
  Keyrocker internal keyrocker;
  uint internal askId;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use AAVE compatible usdc and weth addresses
    fork.setUp();
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove(weth, usdc);
    reader = new MgvReader($(mgv));
    taker = freshAddress();

    // activates keyrocker on weth,usdc market
    keyrocker = new Keyrocker(IMangrove($(mgv)), address(this), 600_000, fork.get("Aave"));
    keyrocker.activate(dynamic([IERC20(weth), usdc]));

    deal($(usdc), $(keyrocker), 1_000_000 * 10 ** 6);
    keyrocker.supply(usdc, 1_000_000 * 10 ** 6);
    //posting 1 ask
    askId = keyrocker.newOffer{value: 1 ether}({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      wants: 2000 * 10 ** 6,
      gives: 1 ether,
      pivotId: 0
    });
    require(askId != 0, "New offer failed");

    vm.prank(taker);
    weth.approve($(mgv), type(uint).max);
    vm.prank(taker);
    usdc.approve($(mgv), type(uint).max);
    deal($(usdc), taker, 10000 * 10 ** 6);
    deal($(weth), taker, 1 ether);
  }

  function test_collateral() public {
    (uint local, uint onPool, uint debt) = keyrocker.tokenBalance(usdc);
    assertEq(local, 0, "Incorrect local balance");
    assertEq(onPool, 1_000_000 * 10 ** 6, "Incorrect pool balance");
    assertEq(debt, 0, "Incorrect debt balance");
  }

  function test_pure_deposit_base() public {
    deal($(weth), $(keyrocker), 1 ether);
    keyrocker.repayThenDeposit(weth, 1 ether);
    (, uint onPool,) = keyrocker.tokenBalance(weth);
    assertEq(onPool, 1 ether, "Incorrect pool balance");
  }

  function test_pure_deposit_quote() public {
    uint amount = 1000 * 10 ** 6;
    (, uint onPool,) = keyrocker.tokenBalance(usdc);
    deal($(usdc), $(keyrocker), amount);
    keyrocker.repayThenDeposit(usdc, amount);
    (, uint onPool_,) = keyrocker.tokenBalance(usdc);
    assertEq(onPool_, onPool + amount, "Incorrect pool balance");
  }

  function test_repay_then_deposit() public {
    uint amount = 1 ether;
    keyrocker.borrow(weth, amount);
    (,, uint debt) = keyrocker.tokenBalance(weth);
    assertEq(debt, amount, "Incorrect debt");
    deal($(weth), $(keyrocker), amount * 2);
    keyrocker.repayThenDeposit(weth, amount * 2);
    (, uint onPool, uint debt_) = keyrocker.tokenBalance(weth);
    assertEq(onPool, 1 ether, "Incorrect supplied amount");
    assertEq(debt_, 0, "Incorrect debt");
  }

  function test_repay_wo_deposit() public {
    uint amount = 1 ether;
    keyrocker.borrow(weth, amount);
    (,, uint debt) = keyrocker.tokenBalance(weth);
    assertEq(debt, amount, "Incorrect debt");
    deal($(weth), $(keyrocker), amount / 2);
    keyrocker.repayThenDeposit(weth, amount / 2);
    (, uint onPool, uint debt_) = keyrocker.tokenBalance(weth);
    assertEq(onPool, 0, "Incorrect supplied amount");
    assertEq(debt_, debt / 2, "Incorrect debt");
  }

  function test_pure_borrow() public {
    keyrocker.redeemThenBorrow(weth, 1 ether);
    (,, uint debt) = keyrocker.tokenBalance(weth);
    assertEq(debt, 1 ether, "Incorrect debt");
  }

  function test_redeem_then_borrow() public {
    deal($(weth), $(keyrocker), 0.5 ether);
    keyrocker.supply(weth, 0.5 ether);

    uint got = keyrocker.redeemThenBorrow(weth, 1 ether);
    (uint local, uint onPool, uint debt) = keyrocker.tokenBalance(weth);
    assertEq(debt, 0.5 ether, "Incorrect debt");
    assertEq(onPool, 0, "Incorrect onpool balance");
    assertEq(local, 1 ether, "Incorrect local balance");
    assertEq(got, local, "Incorrect got");
  }

  function test_offerLogic() public {
    (, uint initOnPoolQuote,) = keyrocker.tokenBalance(usdc);
    // buying 1 ether
    vm.prank(taker);
    (uint received, uint spent, uint penalty,) = mgv.marketOrder($(weth), $(usdc), 1 ether, 2000 * 10 ** 6, true);
    assertEq(received, 1 ether, "Incorrect received");
    assertEq(spent, 2000 * 10 ** 6, "Incorrect spent");
    assertEq(penalty, 0, "Offer failed");
    (uint localBase, uint onPoolBase, uint debtBase) = keyrocker.tokenBalance(weth);
    (uint localQuote, uint onPoolQuote, uint debtQuote) = keyrocker.tokenBalance(usdc);

    assertEq(localBase, 0, "Contract should have no base buffer");
    assertEq(onPoolBase, 0, "Contract should not have supplied base");
    assertEq(debtBase, 1 ether, "Incorrect contract debt");

    assertEq(localQuote, 0, "Contract should have no quote buffer");
    assertEq(onPoolQuote, initOnPoolQuote + 2000 * 10 ** 6, "Contract's on pool collateral should have taker's payment");
    assertEq(debtQuote, 0, "Contract should have no debt for quote");
  }
}
