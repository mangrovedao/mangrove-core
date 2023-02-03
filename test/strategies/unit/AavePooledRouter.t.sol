// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./OfferLogic.t.sol";
import {AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AavePooledRouterTest is OfferLogicTest {
  AavePooledRouter pooledRouter;

  uint constant GASREQ = 474 * 1000; // fail for GASREQ < 474K

  event SetAaveManager(address);

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

  function setupLiquidityRouting() internal override {
    vm.startPrank(deployer);
    AavePooledRouter router = new AavePooledRouter({
      _addressesProvider: fork.get("Aave"),
      overhead: 218_000 // fails < 218K
    });
    router.bind(address(makerContract));
    makerContract.setRouter(router);
    vm.stopPrank();
    // although reserve is set to deployer the source remains makerContract since pooledRouter is always the source of funds
    // having reserve pointing to deployed allows deployer to have multiple strats with the same shares on the router
    owner = deployer;
  }

  function fundStrat() internal virtual override {
    //at the end of super.setUp reserve has 1 ether and 2000 USDC
    //one needs to tell router to deposit them on AAVE

    pooledRouter = AavePooledRouter(address(makerContract.router()));

    deal($(weth), address(makerContract), 1 ether);
    deal($(usdc), address(makerContract), 2000 * 10 ** 6);

    vm.prank(address(makerContract));
    pooledRouter.pushAndSupply(dynamic([IERC20(weth), usdc]), dynamic([uint(1 ether), 2000 * 10 ** 6]), owner);

    assertEq(pooledRouter.balanceOfId(weth, owner), 1 ether, "Incorrect weth balance");
    assertEq(pooledRouter.balanceOfId(usdc, owner), 2000 * 10 ** 6, "Incorrect usdc balance");
  }

  function test_only_makerContract_can_push() public {
    // so that push does not supply to the pool
    deal($(usdc), address(this), 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.push(usdc, address(this), 10 ** 6);

    deal($(usdc), deployer, 10 ** 6);
    vm.expectRevert("AccessControlled/Invalid");
    vm.prank(deployer);
    pooledRouter.push(usdc, deployer, 10 ** 6);
  }

  function test_rewards_manager_is_deployer() public {
    assertEq(pooledRouter.aaveManager(), deployer, "unexpected rewards manager");
  }

  function test_admin_can_set_aave_manager() public {
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.setAaveManager($(this));

    expectFrom($(pooledRouter));
    emit SetAaveManager($(this));
    vm.prank(deployer);
    pooledRouter.setAaveManager($(this));
    assertEq(pooledRouter.aaveManager(), $(this), "unexpected rewards manager");
  }

  function test_deposit_on_aave_maintains_reserve_and_total_balance() public {
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, address(makerContract), 10 ** 6);

    uint reserveBalance = pooledRouter.balanceOfId(usdc, address(makerContract));
    uint totalBalance = pooledRouter.totalBalance(usdc);

    vm.prank(deployer);
    pooledRouter.flushBuffer(usdc);

    assertEq(reserveBalance, pooledRouter.balanceOfId(usdc, address(makerContract)), "Incorrect reserve balance");
    assertEq(totalBalance, pooledRouter.totalBalance(usdc), "Incorrect total balance");
  }

  function test_makerContract_has_initially_zero_shares() public {
    assertEq(pooledRouter.sharesOf(dai, address(makerContract)), 0, "Incorrect initial shares");
  }

  function test_push_token_increases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, maker1, 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, maker2, 2 * 10 ** 18);

    assertEq(pooledRouter.sharesOf(dai, maker2), 2 * pooledRouter.sharesOf(dai, maker1), "Incorrect shares");
  }

  function test_pull_token_decreases_user_shares() public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, maker1, 1 * 10 ** 18);
    deal($(dai), maker2, 2 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, maker2, 2 * 10 ** 18);

    vm.prank(maker1);
    pooledRouter.pull(dai, maker1, 1 * 10 ** 18, true);

    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_mockup_marketOrder_gas_cost() public {
    deal($(dai), maker1, 10 ** 18);

    vm.startPrank(maker1);
    uint gas = gasleft();
    pooledRouter.push(dai, maker1, 10 ** 18);
    vm.stopPrank();

    uint shallow_push_cost = gas - gasleft();

    vm.prank(deployer);
    pooledRouter.flushBuffer(dai);

    vm.startPrank(maker1);
    gas = gasleft();
    /// this emulates a `get` from the offer logic
    pooledRouter.pull(dai, maker1, 0.5 ether, false);
    vm.stopPrank();

    uint deep_pull_cost = gas - gasleft();

    deal($(usdc), maker1, 10 ** 6);

    vm.startPrank(maker1);
    gas = gasleft();
    pooledRouter.pushAndSupply(dynamic([IERC20(usdc), dai]), dynamic([uint(10 ** 6), 1 ether]), maker1);
    vm.stopPrank();

    uint finalize_cost = gas - gasleft();
    console.log("deep pull: %d, finalize: %d", deep_pull_cost, finalize_cost);
    console.log("shallow push: %d", shallow_push_cost);
    console.log("Strat gasreq (%d), mockup (%d)", GASREQ, deep_pull_cost + finalize_cost);
    assertTrue(deep_pull_cost + finalize_cost <= GASREQ, "Strat is spending more gas");
  }

  function test_push_token_increases_first_minter_shares() public {
    deal($(dai), maker1, 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, maker1, 10 ** 18);
    assertEq(pooledRouter.sharesOf(dai, maker1), 10 ** 29, "Incorrect first shares");
  }

  function test_pull_token_decreases_last_minter_shares_to_zero() public {
    deal($(dai), maker1, 10 ** 18);
    vm.startPrank(maker1);
    pooledRouter.push(dai, maker1, 10 ** 18);
    pooledRouter.pull(dai, maker1, 10 ** 18, true);
    vm.stopPrank();
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_donation_in_underlying_increases_user_shares(uint96 donation) public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, maker1, 1 * 10 ** 18);

    deal($(dai), maker2, 4 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, maker2, 4 * 10 ** 18);

    deal($(dai), maker1, donation);
    vm.prank(maker1);
    dai.transfer($(pooledRouter), donation);

    uint expectedBalance = (uint(5) * 10 ** 18 + uint(donation)) / 5;
    uint reserveBalance = pooledRouter.balanceOfId(dai, maker1);
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker1");

    expectedBalance = uint(4) * (5 * 10 ** 18 + uint(donation)) / 5;
    vm.prank(maker2);
    reserveBalance = pooledRouter.balanceOfId(dai, maker2);
    assertEq(expectedBalance, reserveBalance, "Incorrect reserve for maker2");
  }

  function test_strict_pull_with_insufficient_funds_throws_as_expected() public {
    vm.expectRevert("AavePooledRouter/insufficientFunds");
    vm.prank(maker1);
    pooledRouter.pull(dai, maker1, 1, true);
  }

  function test_non_strict_pull_with_insufficient_funds_throws_as_expected() public {
    vm.expectRevert("AavePooledRouter/insufficientFunds");
    vm.prank(maker1);
    pooledRouter.pull(dai, maker1, 1, false);
  }

  function test_strict_pull_transfers_only_amount() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, true);
    vm.stopPrank();
    assertEq(weth.balanceOf(maker1), pulled, "Incorrect balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth - pulled, "Incorrect balance");
  }

  function test_non_strict_pull_transfers_whole_balance() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, true);
    vm.stopPrank();
    assertEq(weth.balanceOf(maker1), pulled, "Incorrect balance");
  }

  function test_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    vm.stopPrank();
    deal($(weth), $(pooledRouter), 10);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth - pulled + 10, "Incorrect aWeth balance");
  }

  function test_non_strict_pull_with_small_buffer_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    vm.stopPrank();
    // donation
    deal($(weth), $(pooledRouter), 10);

    pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, false);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), 0, "Incorrect aWeth balance");
  }

  function test_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    vm.stopPrank();
    deal($(weth), $(pooledRouter), 1 ether);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth, "Incorrect aWeth balance");
  }

  function test_non_strict_pull_with_large_buffer_does_not_triggers_aave_withdraw() public {
    deal($(weth), maker1, 1 ether);
    vm.startPrank(maker1);
    pooledRouter.pushAndSupply(dynamic([IERC20(weth)]), dynamic([uint(1 ether)]), maker1);
    vm.stopPrank();
    deal($(weth), $(pooledRouter), 1 ether);

    uint oldAWeth = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    vm.prank(maker1);
    uint pulled = pooledRouter.pull(weth, maker1, 0.5 ether, true);

    assertEq(weth.balanceOf(maker1), pulled, "Incorrect weth balance");
    assertEq(pooledRouter.overlying(weth).balanceOf($(pooledRouter)), oldAWeth, "Incorrect aWeth balance");
  }

  function test_claim_rewards() public {
    //// rewards not active on polygon, so we test only here call to INCENTIVE_CONTROLLER is OK
    // deal($(dai), maker1, 10_000 * 10 ** 18);
    // vm.prank(maker1);
    // pooledRouter.push(dai, maker1, 10_000 * 10 ** 18);

    // deal($(weth), maker1, 10 * 10 ** 18);
    // vm.prank(maker1);
    // pooledRouter.push(weth, maker1, 10 * 10 ** 18);

    // deal($(usdc), maker1, 10_000 * 10 ** 6);
    // vm.prank(maker1);
    // pooledRouter.push(usdc, maker1, 10_000 * 10 ** 6);

    // vm.startPrank(maker1);
    // pooledRouter.flushBuffer(usdc);
    // pooledRouter.flushBuffer(dai);
    // pooledRouter.flushBuffer(weth);
    // vm.stopPrank();

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
      dynamic([IERC20(weth), usdc, dai]), dynamic([uint(10 * 10 ** 18), 10_000 * 10 ** 6, 10_000 * 10 ** 18]), maker1
    );
    vm.stopPrank();

    uint old_reserve_weth = pooledRouter.balanceOfId(weth, maker1);
    uint old_reserve_usdc = pooledRouter.balanceOfId(usdc, maker1);
    uint old_reserve_dai = pooledRouter.balanceOfId(dai, maker1);
    // // fast forwarding a year
    vm.warp(block.timestamp + 31536000);
    uint new_reserve_weth = pooledRouter.balanceOfId(weth, maker1);
    uint new_reserve_usdc = pooledRouter.balanceOfId(usdc, maker1);
    uint new_reserve_dai = pooledRouter.balanceOfId(dai, maker1);
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

  function test_checkList_throws_for_tokens_that_are_not_listed_on_aave() public {
    TestToken tkn = new TestToken(
      $(this),
      "wen token",
      "WEN",
      42
    );
    vm.prank(maker1);
    tkn.approve({spender: $(pooledRouter), amount: type(uint).max});

    vm.expectRevert("AavePooledRouter/tokenNotLendableOnAave");
    vm.prank(maker1);
    pooledRouter.checkList(IERC20($(tkn)), maker1);
  }
}
