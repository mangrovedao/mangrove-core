// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import "src/strategies/routers/AaveRouter.sol";
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
      weth, makerContract.reserve(maker), 1 ether, makerContract.reserve(maker)
    );
    AaveRouter(address(makerContract.router())).supply(
      usdc, makerContract.reserve(maker), cash(usdc, 2000), makerContract.reserve(maker)
    );
    vm.stopPrank();
  }

  function setupLiquidityRouting() internal override {
    vm.startPrank(maker);
    AaveRouter router = new AaveRouter({
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

  function test_push_fail_is_recoverable() public {
    uint old_bal = usdc.balanceOf(address(makerContract));
    AaveRouter router_ = AaveRouter(address(makerContract.router()));
    // router will fail to get liquidity
    vm.prank(deployer);
    // making push of usdc fail so usdc will stay on `makerContract` (and won't be turned into aUSDC)
    router_.approveLender(usdc, 0);
    (, uint takerGave,,) = performTrade(true);
    assertEq(usdc.balanceOf(address(makerContract)) - old_bal, takerGave, "Inccorect usdc balance");
    vm.startPrank(deployer);
    // Stop using AAVE router
    makerContract.setRouter(AbstractRouter(address(0)));
    // Pointing admin reserve to `makerContract`
    makerContract.setReserve(deployer, address(makerContract));
    assertTrue(makerContract.withdrawToken(usdc, deployer, takerGave), "could not recover funds");
    vm.stopPrank();
  }
}
