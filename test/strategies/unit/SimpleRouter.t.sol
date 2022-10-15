// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "src/strategies/routers/SimpleRouter.sol";

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
}
