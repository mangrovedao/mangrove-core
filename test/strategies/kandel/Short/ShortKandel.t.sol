// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MgvStructs, MgvLib} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {
  ShortKandel,
  GeometricKandel,
  OfferType,
  IERC20
} from "mgv_src/strategies/offer_maker/market_making/kandel/ShortKandel.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {KandelLib} from "lib/kandel/KandelLib.sol";
import {GeometricKandelTest} from "../abstract/GeometricKandel.t.sol";
import {console2 as console} from "forge-std/Test.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {AavePrivateRouter} from "mgv_src/strategies/routers/integrations/AavePrivateRouter.sol";

contract ShortKandelTest is GeometricKandelTest {
  TestToken internal collateral;
  PinnedPolygonFork internal fork;
  AavePrivateRouter internal router;
  uint internal interestRate = 2;
  uint internal constant INIT_COLLATERAL = 1_000_000 * 10 ** 18;

  function Short(GeometricKandel kdl) internal pure returns (ShortKandel) {
    return ShortKandel($(kdl));
  }

  function setUp() public override {
    super.setUp();
    collateral = TestToken(fork.get("DAI"));
    ShortKandel kdl_ = ShortKandel($(kdl));

    deal($(collateral), maker, INIT_COLLATERAL);
    vm.startPrank(maker);
    {
      collateral.approve($(kdl), type(uint).max);
      // initialize does not activates collateral
      kdl_.activate(dynamic([IERC20(collateral)]));
      expectFrom($(kdl));
      emit Credit(collateral, INIT_COLLATERAL);
      kdl_.depositFunds(collateral, INIT_COLLATERAL);
    }
    vm.stopPrank();
  }

  function logCollateralStatus() internal view {
    console.log(
      "base: %s, quote: %s, collateral: %s",
      toFixed(router.balanceOfReserve(base, address(0)), base.decimals()),
      toFixed(router.balanceOfReserve(quote, address(0)), quote.decimals()),
      toFixed(router.balanceOfReserve(collateral, address(0)), collateral.decimals())
    );
  }

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 68_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function __deployKandel__(address deployer, address reserveId)
    internal
    virtual
    override
    returns (GeometricKandel kdl_)
  {
    uint router_gasreq = 500 * 1000;
    uint kandel_gasreq = 160 * 1000;
    router =
      address(router) == address(0) ? new AavePrivateRouter(fork.get("Aave"), interestRate, router_gasreq) : router;
    ShortKandel lkdl = new ShortKandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: kandel_gasreq,
      gasprice: 0,
      reserveId: reserveId
    });
    router.bind($(lkdl));

    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20

    lkdl.initialize(router);
    lkdl.setAdmin(deployer);
    assertEq(lkdl.offerGasreq(), kandel_gasreq + router_gasreq, "Incorrect gasreq");

    return lkdl;
  }

  struct CreditLines {
    AavePrivateRouter.AssetBalances balBase;
    AavePrivateRouter.AssetBalances balQuote;
    AavePrivateRouter.AssetBalances balBase_;
    AavePrivateRouter.AssetBalances balQuote_;
  }

  function bid_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    override
    returns (uint takerGot, uint takerGave, uint fee)
  {
    CreditLines memory CL;
    AavePrivateRouter.AssetBalances memory bal;

    bal = router.assetBalances(quote);
    CL.balQuote.debt = bal.debt;
    CL.balQuote.liquid = bal.liquid;
    CL.balQuote.creditLine = bal.creditLine;

    bal = router.assetBalances(base);
    CL.balBase.debt = bal.debt;
    CL.balBase.liquid = bal.liquid;
    CL.balBase.creditLine = bal.creditLine;

    // sends (borrows) quote, receives (supplies) base
    (takerGot, takerGave, fee) = super.bid_complete_fill(compoundRateBase, compoundRateQuote, index);

    bal = router.assetBalances(quote);
    CL.balQuote_.debt = bal.debt;
    CL.balQuote_.liquid = bal.liquid;
    CL.balQuote_.creditLine = bal.creditLine;

    bal = router.assetBalances(base);
    CL.balBase_.debt = bal.debt;
    CL.balBase_.liquid = bal.liquid;
    CL.balBase_.creditLine = bal.creditLine;

    // new quote debt is old quote debt + takerGot - available quote
    assertApproxEqAbs(
      CL.balQuote_.debt,
      CL.balQuote.debt + takerGot + fee >= CL.balQuote.liquid
        ? CL.balQuote.debt + takerGot + fee - CL.balQuote.liquid
        : 0,
      1, // one wei precision
      "Unexpected quote debt, borrow failed?"
    );

    uint baseDebt = CL.balBase.debt <= takerGave ? 0 : CL.balBase.debt - takerGave;
    assertEq(CL.balBase_.debt, baseDebt, "Unexpected base debt, repay failed?");
  }

  function ask_complete_fill(uint24 compoundRateBase, uint24 compoundRateQuote, uint index)
    internal
    override
    returns (uint takerGot, uint takerGave, uint fee)
  {
    CreditLines memory CL;
    AavePrivateRouter.AssetBalances memory bal;

    bal = router.assetBalances(quote);
    CL.balQuote.debt = bal.debt;
    CL.balQuote.liquid = bal.liquid;
    CL.balQuote.creditLine = bal.creditLine;

    bal = router.assetBalances(base);
    CL.balBase.debt = bal.debt;
    CL.balBase.liquid = bal.liquid;
    CL.balBase.creditLine = bal.creditLine;

    // sends (borrows) quote, receives (supplies) base
    (takerGot, takerGave, fee) = super.ask_complete_fill(compoundRateBase, compoundRateQuote, index);

    bal = router.assetBalances(quote);
    CL.balQuote_.debt = bal.debt;
    CL.balQuote_.liquid = bal.liquid;
    CL.balQuote_.creditLine = bal.creditLine;

    bal = router.assetBalances(base);
    CL.balBase_.debt = bal.debt;
    CL.balBase_.liquid = bal.liquid;
    CL.balBase_.creditLine = bal.creditLine;

    // new base debt is old base debt + takerGot - available base
    assertApproxEqAbs(
      CL.balBase_.debt,
      CL.balBase.debt + takerGot + fee >= CL.balBase.liquid ? CL.balBase.debt + takerGot + fee - CL.balBase.liquid : 0,
      1, // one wei precision
      "Unexpected base debt, borrow failed?"
    );

    uint quoteDebt = CL.balQuote.debt <= takerGave ? 0 : CL.balQuote.debt - takerGave;
    assertEq(CL.balQuote_.debt, quoteDebt, "Unexpected quote debt, repay failed?");
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(base.balanceOf(address(router)), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(Ask) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(Bid) > 0, "Incorrect initial reserve balance of quote");
    assertEq(router.overlying(base).balanceOf(address(router)), 0, "Router should borrow all its base from AAVE");
    assertEq(router.overlying(quote).balanceOf(address(router)), 0, "Router should borrow all its quote from AAVE");
  }

  function test_first_offer_sends_first_puller_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(base);
    order.inbound_tkn = $(quote);
    order.wants = 0.1 ether;
    order.gives = 120 * 10 ** 6;
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }

  function test_not_first_offer_sends_proceed_to_posthook() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(base);
    order.inbound_tkn = $(quote);
    order.wants = 0.1 ether;
    order.gives = 120 * 10 ** 6;
    // faking buffer on the router
    deal($(base), $(router), 1 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "", "Unexpected returned data");
  }

  function test_not_first_offer_sends_first_puller_to_posthook_when_buffer_is_small() public {
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(base);
    order.inbound_tkn = $(quote);
    order.wants = 0.1 ether;
    order.gives = 120 * 10 ** 6;
    // faking small buffer on the router
    deal($(base), $(router), 0.09 ether);
    vm.prank($(mgv));
    bytes32 makerData = kdl.makerExecute(order);
    assertEq(makerData, "IS_FIRST_PULLER", "Unexpected returned data");
  }

  function test_first_puller_posthook_calls_pushAndSupply() public {
    MgvLib.SingleOrder memory order = mockBuyOrder({takerGives: 120 * 10 ** 6, takerWants: 0.1 ether});
    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: "IS_FIRST_PULLER", mgvData: "mgv/tradeSuccess"});

    //1. faking accumulated outbound on the router
    deal($(base), $(router), 1 ether);
    //2. faking accumulated inbound on kandel
    deal($(quote), $(kdl), 1000 * 10 ** 6);

    uint baseAave = router.overlying(base).balanceOf(address(router));
    uint quoteAave = router.overlying(quote).balanceOf(address(router));

    vm.prank($(mgv));
    kdl.makerPosthook(order, result);

    AavePrivateRouter.AssetBalances memory balBase = router.assetBalances(base);
    AavePrivateRouter.AssetBalances memory balQuote = router.assetBalances(quote);

    assertEq(balBase.local, 0, "Router did not flush base buffer");
    assertEq(balQuote.local, 0, "Router did not flush quote buffer");
    assertEq(balBase.onPool, baseAave + 1 ether, "Router should have supplied its base buffer on AAVE");
    assertApproxEqAbs(
      balQuote.onPool, quoteAave + 1000 * 10 ** 6, 1, "Router should have supplied maker's quote on AAVE"
    );
  }

  function test_sharing_collateral_between_strats(uint16 collateralAmount) public {
    deal($(collateral), maker, collateralAmount);
    ShortKandel kdl_ = Short(__deployKandel__(maker, maker));
    assertEq(kdl.reserveBalance(Ask), kdl_.reserveBalance(Ask), "funds are not shared");
    assertEq(kdl.reserveBalance(Bid), kdl_.reserveBalance(Bid), "funds are not shared");

    vm.startPrank(maker);
    {
      collateral.approve($(kdl_), type(uint).max);
      // initialize does not activates collateral
      kdl_.activate(dynamic([IERC20(collateral)]));
      expectFrom($(kdl_));
      emit Credit(collateral, collateralAmount);
      kdl_.depositFunds(collateral, collateralAmount);
    }
    vm.stopPrank();

    assertEq(kdl.reserveBalance(Ask), kdl_.reserveBalance(Ask), "added collateral should increase base credit");
    assertEq(kdl.reserveBalance(Bid), kdl_.reserveBalance(Bid), "added collateral should increase quote credit");
  }
}
