// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "src/strategies/routers/SimpleRouter.sol";

contract SimpleRouterTest is OfferLogicTest {
  function setupLiquidityRouting() internal override {
    vm.startPrank(maker);
    SimpleRouter router = new SimpleRouter();
    router.bind(address(makerContract));
    makerContract.setReserve(maker, address(router));
    makerContract.setRouter(router);
    vm.stopPrank();
  }
}
