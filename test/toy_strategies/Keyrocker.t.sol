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
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove(weth, usdc);
    reader = new MgvReader($(mgv));
    taker = freshAddress();

    // activates keyrocker on weth,usdc market
    keyrocker = new Keyrocker(IMangrove($(mgv)), address(this), 400_000, fork.get("Aave"));
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
    deal($(usdc), taker, 1000 * 10 ** 6);
    deal($(weth), taker, 1 * 10 ** 18);
  }

  function test_collateral() public {
    (uint local, uint onPool, uint debt) = keyrocker.tokenBalance(usdc);
    assertEq(local, 0, "Incorrect local balance");
    assertEq(onPool, 1_000_000 * 10 ** 6, "Incorrect local balance");
    assertEq(debt, 0, "Incorrect local balance");
  }
}
