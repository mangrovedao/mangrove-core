// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract SimpleEOARouterTest is OfferLogicTest {
  function setupRouter() internal override {
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.bind(address(makerContract));
    makerContract.set_reserve(maker);
    makerContract.set_router(router);
    // maker must approve router
    weth.approve(address(router), type(uint).max);
    usdc.approve(address(router), type(uint).max);
    vm.stopPrank();
  }
}
