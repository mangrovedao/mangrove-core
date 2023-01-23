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

    vm.prank(address(makerContract));
    pooledRouter.push(weth, address(pooledRouter), 1 ether);

    deal($(usdc), address(makerContract), 2000 * 10 ** 6);
    vm.prank(address(makerContract));
    // call below will mint the weth on AAVE
    pooledRouter.push(usdc, address(pooledRouter), 2000 * 10 ** 6);

    // force mint on AAVE
    vm.prank(deployer);
    pooledRouter.flushAndsetBuffer(IERC20(address(0)));

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
      overhead: 480_000 // fails for 470K
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

  function test_only_makerContract_or_admin_can_flushAndsetBuffer() public {
    vm.expectRevert("AccessControlled/Invalid");
    pooledRouter.flushAndsetBuffer(IERC20(address(0)));

    vm.prank(deployer);
    pooledRouter.flushAndsetBuffer(IERC20(address(0)));

    vm.prank(address(makerContract));
    pooledRouter.flushAndsetBuffer(IERC20(address(0)));
  }

  function test_deposit_on_aave_maintains_reserve_and_total_balance() public {
    deal($(usdc), address(makerContract), 10 ** 6);
    vm.prank(address(makerContract));
    pooledRouter.push(usdc, $(pooledRouter), 10 ** 6);

    uint reserveBalance = pooledRouter.reserveBalance(usdc, address(makerContract), $(pooledRouter));
    uint totalBalance = pooledRouter.totalBalance(usdc);
    vm.prank(maker1);
    pooledRouter.flushAndsetBuffer(IERC20(address(0)));

    assertEq(
      reserveBalance,
      pooledRouter.reserveBalance(usdc, address(makerContract), address(pooledRouter)),
      "Incorrect reserve balance"
    );
    assertEq(totalBalance, pooledRouter.totalBalance(usdc), "Incorrect total balance");
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

  function test_pull_token_decreases_last_minter_shares_to_zero() public {
    deal($(dai), maker1, 10 ** 18);
    vm.startPrank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 10 ** 18);
    pooledRouter.pull(dai, $(pooledRouter), 10 ** 18, true);
    vm.stopPrank();
    assertEq(pooledRouter.sharesOf(dai, maker1), 0, "Incorrect shares");
  }

  function test_donation_increases_user_shares(uint96 donation) public {
    deal($(dai), maker1, 1 * 10 ** 18);
    vm.prank(maker1);
    pooledRouter.push(dai, $(pooledRouter), 1 * 10 ** 18);

    deal($(dai), maker2, 4 * 10 ** 18);
    vm.prank(maker2);
    pooledRouter.push(dai, $(pooledRouter), 4 * 10 ** 18);

    deal($(dai), $(this), donation);
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

  function test_at_most_3_calls_to_aave_per_market_order() public {
    uint old_aWeth_bal = pooledRouter.overlying(weth).balanceOf($(pooledRouter));
    uint old_aUsdc_bal = pooledRouter.overlying(usdc).balanceOf($(pooledRouter));

    console.log("Initial weth balance on aave", toUnit(old_aWeth_bal, 18));
    console.log("Initial weth balance on aave", toUnit(old_aUsdc_bal, 6));
    for (uint i; i < 5; i++) {
      vm.prank(maker);
      makerContract.newOffer{value: 0.1 ether}({
        outbound_tkn: weth,
        inbound_tkn: usdc,
        wants: 120 * 10 ** 6 + i,
        gives: 0.1 * 10 ** 18,
        pivotId: 0
      });
    }
    reader = new MgvReader($(mgv));
    (, uint[] memory ids, MgvStructs.OfferPacked[] memory offers,) = reader.packedOfferList($(weth), $(usdc), 0, 10);
    for (uint i = 0; i < offers.length; i++) {
      console.log(ids[i], toUnit(offers[i].wants(), 6), toUnit(offers[i].gives(), 18));
    }
    // at the end of this market order one must verify:
    // * all inbound_tkn are on router
    // * all outboun_tkn are on aave
    vm.prank(taker);
    (uint takerGot, uint takerGave, uint bounty, uint fee) = mgv.marketOrder({
      outbound_tkn: $(weth),
      inbound_tkn: $(usdc),
      takerWants: 0.5 ether,
      takerGives: 1_300 * 10 ** 6,
      fillWants: true
    });
    assertTrue(bounty == 0, "Some offer failed");
    assertEq(takerGot + fee, 0.5 ether, "unexpected partial fill");
    assertEq(takerGave, usdc.balanceOf($(pooledRouter)), "Incorrect usdc balance on router");
    assertEq(weth.balanceOf($(pooledRouter)), 0, "Incorrect weth balance on router");
    assertEq(
      pooledRouter.overlying(weth).balanceOf($(pooledRouter)),
      old_aWeth_bal - (takerGot + fee),
      "Incorrect aWeth balance on pool"
    );
    assertEq(pooledRouter.overlying(usdc).balanceOf($(pooledRouter)), old_aUsdc_bal, "Incorrect aUsdc balance on pool");
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
}
