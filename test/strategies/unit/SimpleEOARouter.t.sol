// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract SimpleEOARouterTest is OfferLogicTest {
  function setupLiquidityRouting() internal override {
    // OfferMaker has no router, replacing 0x router by a SimpleRouter
    SimpleRouter router = new SimpleRouter();
    router.bind(address(makerContract));
    // maker must approve router
    vm.startPrank(maker);
    makerContract.setRouter(router);
    weth.approve(address(router), type(uint).max);
    usdc.approve(address(router), type(uint).max);
    vm.stopPrank();
  }

  function test_trade_succeeds_with_new_reserve() public {
    address new_reserve = freshAddress("new_reserve");

    vm.prank(maker);
    makerContract.setReserve(maker, new_reserve);

    deal($(weth), new_reserve, 0.5 ether);
    deal($(weth), address(makerContract), 0);
    deal($(usdc), address(makerContract), 0);

    address toApprove = address(makerContract.router());
    toApprove = toApprove == address(0) ? address(makerContract) : toApprove;
    vm.startPrank(new_reserve);
    usdc.approve(toApprove, type(uint).max); // to push
    weth.approve(toApprove, type(uint).max); // to pull
    vm.stopPrank();
    (, uint takerGave,,) = performTrade(true);
    vm.startPrank(maker);
    assertEq(takerGave, makerContract.tokenBalance(usdc, maker), "Incorrect reserve usdc balance");
    assertEq(makerContract.tokenBalance(weth, maker), 0, "Incorrect reserve weth balance");
    vm.stopPrank();
  }
}
