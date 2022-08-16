// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/single_user/market_making/mango/Mango.sol";
import "mgv_src/strategies/routers/AaveRouter.sol";
import "mgv_test/lib/Fork.sol";

// note: this is a forking test
contract GuaaveForkedTest is MangroveTest {
  uint constant BASE0 = 0.34 ether;
  uint constant BASE1 = 1000 * 10**6; //because usdc decimals?
  uint constant NSLOTS = 20;
  // price increase is delta/BASE_0
  uint constant DELTA = 34 * 10**6; // because usdc decimals?

  IERC20 weth;
  IERC20 usdc;
  address payable maker;
  address payable taker;
  Mango mgo;
  AaveRouter router;

  function setUp() public override {
    Fork.setUp();

    mgv = setupMangrove();
    mgv.setVault($(mgv));

    weth = IERC20(Fork.WETH);
    usdc = IERC20(Fork.USDC);
    options.defaultFee = 30;
    setupMarket(weth, usdc);

    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);

    maker = freshAddress("maker");
    taker = freshAddress("taker");
    deal($(weth), taker, cash(weth, 50) + weth.balanceOf(taker), true);
    deal($(usdc), taker, cash(usdc, 100_000) + usdc.balanceOf(taker), true);

    vm.startPrank(maker);
    mgo = new Mango({
      mgv: IMangrove($(mgv)), // TODO: remove IMangrove dependency?
      base: weth,
      quote: usdc,
      base_0: 0.34 ether,
      quote_0: 1000 * 10**6,
      nslots: NSLOTS,
      price_incr: DELTA,
      deployer: maker // reserve address is maker's wallet
    });
    vm.stopPrank();
  }

  /* combine all tests wince they rely on non-zero state */
  function test_all() public {
    part_deploy_strat();
    part_deploy_buffered_router();
    part_initialize();
    part_market_order_with_buffer();
  }

  function part_deploy_strat() public {}

  function part_deploy_buffered_router() public {
    // default router for Mango is `SimpleRouter` that uses `reserve` to pull and push liquidity
    // here we want to use aave for (il)liquidity and store liquid overlying at reserve
    // router will redeem and deposit funds that are mobilized during trade execution
    vm.startPrank(maker);
    router = new AaveRouter({
      _addressesProvider: Fork.AAVE,
      _referralCode: 0,
      _interestRateMode: 1 // stable rate
    });
    // adding makerContract to allowed pullers of router's liquidity
    router.bind($(mgo));

    // liquidity router will pull funds from AAVE
    mgo.set_router(router);
    mgo.set_reserve($(router));

    // computing necessary provision (which has changed because of new router GAS_OVERHEAD)
    uint prov = mgo.getMissingProvision({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      gasreq: mgo.ofr_gasreq(),
      gasprice: 0,
      offerId: 0
    });

    vm.stopPrank();
    mgv.fund{value: prov * (NSLOTS * 2)}($(mgo));
    vm.startPrank(maker);
    deal($(weth), $(mgo), cash(weth, 17) + weth.balanceOf($(mgo)), true);

    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = weth;
    tokens[1] = usdc;

    vm.expectRevert("Router/NotApprovedByMakerContract");
    mgo.checkList(tokens);

    // no need to approve for overlying transfer because router is the reserve
    mgo.activate(tokens);
    try mgo.checkList(tokens) {} catch Error(string memory reason) {
      fail(reason);
    }

    // putting ETH as collateral on AAVE
    router.supply(
      weth,
      mgo.reserve(),
      17 ether,
      $(mgo) /* maker contract was funded above */
    );
    router.borrow(
      usdc,
      mgo.reserve(),
      2000 * 10**6,
      $(mgo) /* maker contract is buffer */
    );
    vm.stopPrank();

    // TODO-foundry-merge: implement logLenderStatus in solidity
  }

  function part_initialize() public {
    vm.startPrank(maker);
    init(1000 * 10**6, 0.3 ether);
    vm.stopPrank();
    // note: js tests would log the usdc/weth and weth/usdc OBs at this point
  }

  function part_market_order_with_buffer() public {
    IERC20 aweth = IERC20(Fork.AWETH);
    uint takerWants = 3 ether;
    vm.startPrank(taker);
    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    uint awETHBalance = aweth.balanceOf($(router));
    // if we don't move timestamp forward, final balance is 6 times lower than it should, not sure exactly why. theories: interest rate? aave borrow/repay blocker?
    vm.warp(block.timestamp + 1);
    mgv.marketOrder($(weth), $(usdc), takerWants, 100_000 * 10**6, true);
    // note: js tests would logLenderStatus at this point
    vm.stopPrank();
    uint expected = awETHBalance - takerWants; //maker pays before Mangrove fees
    uint actual = aweth.balanceOf($(router));
    assertApproxEqAbs(expected, actual, 10**9, "wrong final balance");
  }

  // init procedure
  // TODO explain
  function init(uint bidAmount, uint askAmount) internal {
    uint slice = 5;
    uint[] memory pivotIds = new uint[](NSLOTS);
    uint[] memory amounts = new uint[](NSLOTS);
    for (uint i = 0; i < NSLOTS; i++) {
      amounts[i] = i < NSLOTS / 2 ? bidAmount : askAmount;
    }

    for (uint i = 0; i < NSLOTS / slice; i++) {
      mgo.initialize({
        reset: true,
        lastBidPosition: NSLOTS / 2 - 1, // stats asking at NSLOTS/2
        from: slice * i,
        to: slice * (i + 1),
        pivotIds: [pivotIds, pivotIds],
        tokenAmounts: amounts
      });
      // enable for more info
      // console.log(string.concat("Offers ",uint2str(slice * i),",",uint2str(slice * (i + 1))," initialized"));
    }
  }
}
