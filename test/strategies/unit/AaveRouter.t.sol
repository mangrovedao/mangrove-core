// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "mgv_src/strategies/routers/AaveRouter.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AaveRouterForkedTest is OfferLogicTest {
  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    fork = new PinnedPolygonFork();
    super.setUp();

    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE
    vm.startPrank(maker);
    AaveRouter(address(makerContract.router())).supply(
      weth,
      makerContract.reserve(),
      1 ether,
      makerContract.reserve()
    );
    AaveRouter(address(makerContract.router())).supply(
      usdc,
      makerContract.reserve(),
      cash(usdc, 2000),
      makerContract.reserve()
    );
    vm.stopPrank();
  }

  function setupRouter() internal override {
    vm.startPrank(maker);
    AaveRouter router = new AaveRouter({
      _addressesProvider: fork.get("Aave"),
      _referralCode: 0,
      _interestRateMode: 1 // stable rate
    });
    router.bind(address(makerContract));
    makerContract.setReserve(address(router));
    makerContract.setRouter(router);
    vm.stopPrank();
  }
}
