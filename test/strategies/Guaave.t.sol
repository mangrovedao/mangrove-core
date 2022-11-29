// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_src/strategies/offer_maker/market_making/mango/Mango.sol";
import "mgv_src/strategies/routers/AavePoolManager.sol";
import "mgv_test/lib/forks/Polygon.sol";

/* This test works as an example of how to run the same test on multiple forks. 

  1) There is GuaaveAbstractTest where all tests are defined and which sets fork = new GenericFork().
  2) At the bottom of the file, there is GuaavePolygonTest, which sets fork = PolygonFork.

  Creating a PolygonFork and then calling fork.setUp() will set the rpc endpoint, block number, and contract addresses.

  If you want to test on e.g. Mumbai, and you have a MumbaiFork contract, add the following contract:

    contract GuaaveMumbaiTest is GuaaveAbstractTest {
      constructor() {
        fork = new MumbaiFork();
      }
    }*/

abstract contract GuaaveAbstractTest is MangroveTest {
  uint constant BASE0 = 0.34 ether;
  uint constant BASE1 = 1000 * 10 ** 6; //because usdc decimals?
  uint constant NSLOTS = 20;
  // price increase is delta/BASE_0
  uint constant DELTA = 34 * 10 ** 6; // because usdc decimals?

  IERC20 weth;
  IERC20 usdc;
  address payable maker;
  address payable taker;
  Mango mgo;
  AavePoolManager router;
  GenericFork fork = new GenericFork();

  function setUp() public override {
    fork.setUp();
    mgv = setupMangrove();

    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));
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
    router = new AavePoolManager({
      _addressesProvider: fork.get("Aave"),
      _referralCode: 0,
      _interestRateMode: 1, // stable rate
      overhead: 700_000
    });
    // adding makerContract to allowed pullers of router's liquidity
    router.bind($(mgo));

    // liquidity router will pull funds from AAVE
    mgo.setRouter(router);
    mgo.setReserve($(router));

    // computing necessary provision (which has changed because of new router GAS_OVERHEAD)
    uint prov = mgo.getMissingProvision({
      outbound_tkn: weth,
      inbound_tkn: usdc,
      gasreq: mgo.offerGasreq(),
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

    vm.expectRevert("mgvOffer/LogicMustApproveRouter");
    mgo.checkList(tokens);

    // no need to approve for overlying transfer because router is the reserve
    mgo.activate(tokens);
    try mgo.checkList(tokens) {}
    catch Error(string memory reason) {
      fail(reason);
    }

    // putting ETH as collateral on AAVE
    router.supply(weth, mgo.reserve(maker), 17 ether, $(mgo) /* maker contract was funded above */ );
    router.borrow(usdc, mgo.reserve(maker), 2000 * 10 ** 6, $(mgo) /* maker contract is buffer */ );
    vm.stopPrank();

    // TODO-foundry-merge: implement logLenderStatus in solidity
  }

  function part_initialize() public {
    vm.startPrank(maker);
    init(1000 * 10 ** 6, 0.3 ether);
    vm.stopPrank();
    // note: js tests would log the usdc/weth and weth/usdc OBs at this point
  }

  function part_market_order_with_buffer() public {
    IERC20 aweth = IERC20(fork.get("AWETH"));
    uint takerWants = 3 ether;
    vm.startPrank(taker);
    weth.approve($(mgv), type(uint).max);
    usdc.approve($(mgv), type(uint).max);
    uint awETHBalance = aweth.balanceOf($(router));
    // if we don't move timestamp forward, final balance is 6 times lower than it should, not sure exactly why. theories: interest rate? aave borrow/repay blocker?
    vm.warp(block.timestamp + 1);
    mgv.marketOrder($(weth), $(usdc), takerWants, 100_000 * 10 ** 6, true);
    // note: js tests would logLenderStatus at this point
    vm.stopPrank();
    uint expected = awETHBalance - takerWants; //maker pays before Mangrove fees
    uint actual = aweth.balanceOf($(router));
    assertApproxEqAbs(expected, actual, 10 ** 9, "wrong final balance");
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
      // console.log("Offers %s,%s initialized",slice * i, slice * (i + 1));
    }
  }
}

contract GuaavePolygonTest is GuaaveAbstractTest {
  constructor() {
    fork = new PinnedPolygonFork();
  }
}
