// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";

contract SimpleRouterTest is OfferLogicTest {
  function setupRouter() internal override {
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.bind(address(makerContract));
    makerContract.set_reserve(address(router));
    makerContract.set_router(router);
    vm.stopPrank();
  }
}
