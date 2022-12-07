// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract SimpleRouterTest is OfferLogicTest {
  SimpleRouter router;

  function setupLiquidityRouting() internal override {
    vm.startPrank(deployer);
    router = new SimpleRouter();
    router.bind(address(makerContract));
    makerContract.setRouter(router);
    makerContract.setReserve(maker, address(router));
    vm.stopPrank();
  }

  function test_admin_can_unbind_makerContract() public {
    vm.prank(deployer);
    router.unbind(address(makerContract));
    assertTrue(!router.makers(address(makerContract)), "unbind failed");
  }

  function test_makerContract_can_unbind_makerContract() public {
    vm.prank(address(makerContract));
    router.unbind();
    assertTrue(!router.makers(address(makerContract)), "unbind failed");
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
