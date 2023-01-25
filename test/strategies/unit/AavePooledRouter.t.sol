// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import {AavePooledRouter} from "mgv_src/strategies/routers/AavePooledRouter.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AavePooledRouterTest is OfferLogicTest {
  AavePooledRouter pooledRouter;

  uint constant GASREQ = 367_000; // fails for 366K [7d99f7ede1f]

  event SetRewardsManager(address);

  IERC20 dai;
  address maker1;
  address maker2;

  /// sets storage variable _firstPuller to mock up a market order with a particular `maker` as first offer
  function getRewardsManager() internal view returns (address) {
    /// firstPuller and offerId are packed in slot(0)
    bytes32 slot = vm.load(address(pooledRouter), bytes32(uint(0)));
    return address(uint160(uint(slot)));
  }

  function setUp() public override {
    // deploying mangrove and opening WETH/USDC market.
    fork = new PinnedPolygonFork();
    super.setUp();
    dai = TestToken(fork.get("DAI"));
    vm.prank(deployer);
    makerContract.activate(dynamic([dai]));
    maker1 = freshAddress("maker1");
    maker2 = freshAddress("maker2");

    vm.deal(maker1, 10 ether);
    vm.deal(maker2, 10 ether);

    vm.startPrank(deployer);
    pooledRouter.bind(maker1);
    pooledRouter.bind(maker2);
    vm.stopPrank();

    vm.startPrank(maker1);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
    weth.approve({spender: $(pooledRouter), amount: type(uint).max});
    usdc.approve({spender: $(pooledRouter), amount: type(uint).max});
    vm.stopPrank();

    vm.startPrank(maker2);
    dai.approve({spender: $(pooledRouter), amount: type(uint).max});
    weth.approve({spender: $(pooledRouter), amount: type(uint).max});
    usdc.approve({spender: $(pooledRouter), amount: type(uint).max});
    vm.stopPrank();
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE
    vm.startPrank(maker);
    pooledRouter = AavePooledRouter(address(makerContract.router()));
    vm.stopPrank();

    deal($(weth), address(makerContract), 1 ether);
    deal($(usdc), address(makerContract), 2000 * 10 ** 6);

    vm.prank(address(makerContract));
    pooledRouter.pushAndSupply(dynamic([IERC20(weth), usdc]), dynamic([uint(1 ether), 2000 * 10 ** 6]));

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
      _interestRateMode: 2, // 1 stable rate, 2 variable
      overhead: GASREQ
    });
    router.bind(address(makerContract));
    makerContract.setReserve(maker, address(router));
    makerContract.setRouter(router);
    vm.stopPrank();
  }

  function test_only_makerContract_can_push() public {
    // so that push does not supply to the pool
    deal($(usdc), address(this), 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.push(usdc, address(pooledRouter), 10 ** 6);

    deal($(usdc), deployer, 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(deployer);
    pooledRouter.push(usdc, address(pooledRouter), 10 ** 6);
  }

  function test_rewards_manager_is_deployer() public {
    assertEq(getRewardsManager(), deployer, "unexpected rewards manager");
  }

  function test_admin_can_set_rewards_manager() public {
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.setRewardsManager($(this));

    expectFrom($(pooledRouter));
    emit SetRewardsManager($(this));
    vm.prank(deployer);
    pooledRouter.setRewardsManager($(this));
    assertEq(getRewardsManager(), $(this), "unexpected rewards manager");
  }

  function test_deposit_on_aave_maintains_reserve_and_total_balance() public {
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);

    uint reserveBalance = pooledRouter.reserveBalance(usdc, address(makerContract), $(pooledRouter));
    uint totalBalance = pooledRouter.totalBalance(usdc);

    vm.prank(deployer);
    pooledRouter.flushBuffer(usdc);

    assertEq(
      reserveBalance,
      pooledRouter.reserveBalance(usdc, address(makerContract), address(pooledRouter)),
      "Incorrect reserve balance"
    );
    assertEq(totalBalance, pooledRouter.totalBalance(usdc), "Incorrect total balance");
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
    assertEq(pooledRouter.sharesOf(dai, maker1), 10 ** 29, "Incorrect first shares");
  }

  function test_pull_token_decreases_last_minter_shares_to_zero() public {
    deal($(dai), maker1, 10 ** 18);
    vm.startPrank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 10 ** 18);
    pooledRouter.pull(dai, $(pooledRouter), 10 ** 18, true);
    vm.stopPrank();
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_donation_in_underlying_increases_user_shares(uint96 donation) public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 1 * 10 ** 18);

    deal($(dai), maker2, 4 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, $(pooledRouter), 4 * 10 ** 18);

    deal($(dai), maker1, donation);
    vm.prank(maker1);
    dai.transfer($(pooledRouter), donation);

    uint expectedBalance = (uint(5) * 10 ** 18 + uint(donation)) / 5;
    vm.prank(maker1);
    uint reserveBalance = pooledRouter.reserveBalance(dai, $(pooledRouter));
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker1");

    expectedBalance = uint(4) * (5 * 10 ** 18 + uint(donation)) / 5;
    vm.prank(maker2);
    reserveBalance = pooledRouter.reserveBalance(dai, $(pooledRouter));
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker2");
  }

  function test_claim_rewards() public {
    //// rewards not active on polygon, so we test only here call to INCENTIVE_CONTROLLER is OK
    // deal($(dai), maker1, 10_000 * 10 ** 18);
    // vm.prank(maker1);
    // pooledRouter.push(dai, $(pooledRouter), 10_000 * 10 ** 18);

    // deal($(weth), maker1, 10 * 10 ** 18);
    // vm.prank(maker1);
    // pooledRouter.push(weth, $(pooledRouter), 10 * 10 ** 18);

    // deal($(usdc), maker1, 10_000 * 10 ** 6);
    // vm.prank(maker1);
    // pooledRouter.push(usdc, $(pooledRouter), 10_000 * 10 ** 6);

    // vm.prank(maker1);
    // pooledRouter.flushAndsetBuffer(IERC20(address(0)));

    // // fast forwarding
    // vm.warp(block.timestamp + 10**4);
    address[] memory assets = new address[](3);
    assets[0] = address(pooledRouter.overlying(usdc));
    assets[1] = address(pooledRouter.overlying(weth));
    assets[2] = address(pooledRouter.overlying(dai));
    vm.prank(deployer);
    (address[] memory rewardsList, uint[] memory claimedAmounts) = pooledRouter.claimRewards(assets);
    for (uint i; i < rewardsList.length; i++) {
      console.logAddress(rewardsList[i]);
      console.log(claimedAmounts[i]);
    }
  }

  function test_aave_generates_yield() public {
    deal($(weth), maker1, 10 * 10 ** 18);
    deal($(usdc), maker1, 10_000 * 10 ** 6);
    deal($(dai), maker1, 10_000 * 10 ** 18);

    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(
      dynamic([IERC20(weth), usdc, dai]), dynamic([uint(10 * 10 ** 18), 10_000 * 10 ** 6, 10_000 * 10 ** 18])
    );
    vm.stopPrank();

    uint old_reserve_weth = pooledRouter.reserveBalance(weth, maker1, $(pooledRouter));
    uint old_reserve_usdc = pooledRouter.reserveBalance(usdc, maker1, $(pooledRouter));
    uint old_reserve_dai = pooledRouter.reserveBalance(dai, maker1, $(pooledRouter));
    // // fast forwarding a year
    vm.warp(block.timestamp + 31536000);
    uint new_reserve_weth = pooledRouter.reserveBalance(weth, maker1, $(pooledRouter));
    uint new_reserve_usdc = pooledRouter.reserveBalance(usdc, maker1, $(pooledRouter));
    uint new_reserve_dai = pooledRouter.reserveBalance(dai, maker1, $(pooledRouter));
    assertTrue(
      old_reserve_weth < new_reserve_weth && old_reserve_usdc < new_reserve_usdc && old_reserve_dai < new_reserve_dai,
      "No yield from AAVE"
    );
    console.log(
      "WETH (+%s), USDC (+%s), DAI(+%s)",
      toUnit(new_reserve_weth - old_reserve_weth, 18),
      toUnit(new_reserve_usdc - old_reserve_usdc, 6),
      toUnit(new_reserve_dai - old_reserve_dai, 18)
    );
  }
}
