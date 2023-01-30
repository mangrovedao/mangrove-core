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
    vm.prank(deployer);
    makerContract.setRouter(router);

    vm.startPrank(owner);
    weth.approve(address(router), type(uint).max);
    usdc.approve(address(router), type(uint).max);
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    deal($(weth), owner, 1 ether);
    deal($(usdc), owner, cash(usdc, 2000));
  }
}
