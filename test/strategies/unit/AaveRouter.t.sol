// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import {AavePoolManager} from "mgv_src/strategies/routers/AavePoolManager.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AaveRouterTest is OfferLogicTest {
  AavePoolManager poolManager;

  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    fork = new PinnedPolygonFork();
    super.setUp();

    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE
    vm.startPrank(maker);
    poolManager = AavePoolManager(address(makerContract.router()));
    poolManager.supply(weth, makerContract.reserve(maker), 1 ether, makerContract.reserve(maker));
    poolManager.supply(usdc, makerContract.reserve(maker), cash(usdc, 2000), makerContract.reserve(maker));
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal override {
    vm.startPrank(maker);
    AavePoolManager router = new AavePoolManager({
      _addressesProvider: fork.get("Aave"),
      _referralCode: 0,
      _interestRateMode: 1, // stable rate
      overhead: 700_000
    });
    router.bind(address(makerContract));
    makerContract.setReserve(maker, address(router));
    makerContract.setRouter(router);
    vm.stopPrank();
  }

  function test_admin_can_withdrawTokens_from_router() public {
    // note in order to be routing strategy agnostic one cannot easily mockup a trade
    // for aave routers reserve will hold overlying while for simple router reserve will hold the asset
    uint balusdc = usdc.balanceOf(maker);

    (, uint takergave,,) = performTrade(true);
    vm.startPrank(maker);
    // this will be a noop when maker == reserve
    poolManager.redeem(usdc, makerContract.reserve(maker), takergave, maker);
    vm.stopPrank();
    assertEq(usdc.balanceOf(maker), balusdc + takergave, "withdraw failed");
  }

  function test_withdraw_0_token_skips_transfer() public {
    vm.startPrank(maker);
    poolManager.redeem(usdc, makerContract.reserve(maker), 0, maker);
    vm.stopPrank();
  }
}
