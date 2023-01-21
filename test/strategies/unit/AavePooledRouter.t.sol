// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import {AavePooledRouter} from "mgv_src/strategies/routers/AavePooledRouter.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AavePooledRouterTest is OfferLogicTest {
  AavePooledRouter pooledRouter;

  event SetRewardsManager(address);

  IERC20 dai;
  address maker1;
  address maker2;

  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    fork = new PinnedPolygonFork();
    super.setUp();
    dai = TestToken(fork.get("DAI"));
    vm.prank(deployer);
    makerContract.activate(dynamic([dai]));
    maker1 = freshAddress("maker1");
    maker2 = freshAddress("maker2");

    vm.startPrank(deployer);
    pooledRouter.bind(maker1);
    pooledRouter.bind(maker2);
    vm.stopPrank();

    vm.prank(maker1);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
    vm.prank(maker2);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE
    vm.startPrank(maker);
    pooledRouter = AavePooledRouter(address(makerContract.router()));
    vm.stopPrank();

    deal($(weth), address(makerContract), 1 ether);

    vm.prank(address(makerContract));
    pooledRouter.push(weth, address(pooledRouter), 1 ether);

    deal($(usdc), address(makerContract), 2000 * 10 ** 6);
    vm.prank(address(makerContract));
    // call below will mint the weth on AAVE
    pooledRouter.push(usdc, address(pooledRouter), 2000 * 10 ** 6);

    // force mint on AAVE
    vm.prank(deployer);
    pooledRouter.depositBuffer(IERC20(address(0)));

    vm.prank(address(makerContract));
    assertEq(pooledRouter.reserveBalance(weth, address(pooledRouter)), 1 ether, "Incorrect weth balance");

    vm.prank(address(makerContract));
    assertEq(pooledRouter.reserveBalance(usdc, address(pooledRouter)), 2000 * 10 ** 6, "Incorrect usdc balance");
  }

  function setupLiquidityRouting() internal override {
    vm.startPrank(maker);
    AavePooledRouter router = new AavePooledRouter({
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

  function test_only_makerContract_can_push() public {
    deal($(usdc), address(this), 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.push(usdc, address(pooledRouter), 10 ** 6);

    deal($(usdc), deployer, 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(deployer);
    pooledRouter.push(usdc, address(pooledRouter), 10 ** 6);
  }

  function test_rewards_manager_is_deployer() public {
    assertEq(pooledRouter._rewardsManager(), deployer, "unexpected rewards manager");
  }

  function test_admin_can_set_rewards_manager() public {
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.setRewardsManager($(this));

    expectFrom($(pooledRouter));
    emit SetRewardsManager($(this));
    vm.prank(deployer);
    pooledRouter.setRewardsManager($(this));
    assertEq(pooledRouter._rewardsManager(), $(this), "unexpected rewards manager");
  }

  function test_push_of_same_token_is_not_deposited_on_lender() public {
    assertEq($(pooledRouter._buffer()), address(0), "buffer should be 0x");
    deal($(usdc), address(makerContract), 2 * 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);
    assertEq(usdc.balanceOf($(pooledRouter)), 10 ** 6, "incorrect usdc balance after push #1");

    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);
    assertEq(usdc.balanceOf($(pooledRouter)), 2 * 10 ** 6, "incorrect usdc balance after push #2");
  }

  function test_only_makerContract_or_admin_can_depositBuffer() public {
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.depositBuffer(IERC20(address(0)));

    vm.prank(deployer);
    pooledRouter.depositBuffer(IERC20(address(0)));

    vm.prank(address(makerContract));
    pooledRouter.depositBuffer(IERC20(address(0)));
  }

  function test_push_token_when_buffer_has_another_token_triggers_deposit() public {
    uint oldOverlyingBalance = pooledRouter.overlying(usdc).balanceOf($(pooledRouter));
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);

    deal($(weth), address(makerContract), 1 ether);
    vm.prank(address(makerContract));
    pooledRouter.push(weth, $(pooledRouter), 1 ether);

    assertEq(usdc.balanceOf($(pooledRouter)), 0, "usdc were not deposited on AAVE");
    assertEq(
      pooledRouter.overlying(usdc).balanceOf($(pooledRouter)),
      10 ** 6 + oldOverlyingBalance,
      "incorrect overlying balance"
    );
  }

  function test_pull_token_when_buffer_has_another_token_triggers_deposit() public {
    uint oldOverlyingBalance = pooledRouter.overlying(usdc).balanceOf($(pooledRouter));
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);

    vm.prank(address(makerContract));
    pooledRouter.pull(weth, $(pooledRouter), 0, true);

    assertEq(usdc.balanceOf($(pooledRouter)), 0, "usdc were not deposited on AAVE");
    assertEq(
      pooledRouter.overlying(usdc).balanceOf($(pooledRouter)),
      10 ** 6 + oldOverlyingBalance,
      "incorrect overlying balance"
    );
  }

  function test_makerContract_has_initially_zero_shares() public {
    assertEq(pooledRouter.sharesOf(dai, address(makerContract)), 0, "Incorrect initial shares");
  }

  function test_push_token_increases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, $(pooledRouter), 2 * 10 ** 18);

    assertEq(pooledRouter.sharesOf(dai, maker2), 2 * pooledRouter.sharesOf(dai, maker1), "Incorrect shares");
  }

  function test_pull_token_decreases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, $(pooledRouter), 2 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.pull(dai, $(pooledRouter), 1 * 10 ** 18, true);

    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_push_token_increases_first_minter_shares() public {
    deal($(dai), maker1, 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 10 ** 18);
    assertEq(pooledRouter.sharesOf(dai, maker1), pooledRouter.INIT_SHARES(), "Incorrect first shares");
  }

  function test_pull_token_decreases_sets_last_minter_shares_to_zero() public {
    deal($(dai), maker1, 10 ** 18);
    vm.startPrank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 10 ** 18);
    pooledRouter.pull(dai, $(pooledRouter), 10 ** 18, true);
    vm.stopPrank();
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }
}
