// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {CoreKandelTest, IERC20} from "./CoreKandel.t.sol";
import {console} from "forge-std/Test.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {AaveKandel, AavePooledRouter} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {console2} from "forge-std/Test.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {AaveCaller} from "mgv_test/lib/agents/AaveCaller.sol";

contract AaveKandelTest is CoreKandelTest {
  PinnedPolygonFork fork;
  AavePooledRouter router;
  AaveKandel aaveKandel;
  address THIS = address(this);

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function __deployKandel__(address deployer, address id) internal virtual override returns (GeometricKandel) {
    // 474_000 theoretical in mock up of router
    // 218_000 observed in tests of router
    uint router_gasreq = 318 * 1000;
    uint kandel_gasreq = 338 * 1000;
    router = address(router) == address(0) ? new AavePooledRouter(fork.get("Aave"), router_gasreq) : router;
    aaveKandel = new AaveKandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: kandel_gasreq,
      gasprice: 0,
      reserveId: id
    });

    router.bind(address(aaveKandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKandel.initialize(router);
    aaveKandel.setAdmin(deployer);
    assertEq(aaveKandel.offerGasreq(), kandel_gasreq + router_gasreq, "Incorrect gasreq");
    return aaveKandel;
  }

  function precisionForAssert() internal pure override returns (uint) {
    return 1;
  }

  function getAbiPath() internal pure override returns (string memory) {
    return "/out/AaveKandel.sol/AaveKandel.json";
  }

  function test_allExternalFunctions_differentCallers_correctAuth() public override {
    super.test_allExternalFunctions_differentCallers_correctAuth();
    CheckAuthArgs memory args;
    args.callee = $(kdl);
    args.callers = dynamic([address($(mgv)), maker, $(this)]);
    args.allowed = dynamic([address(maker)]);
    args.revertMessage = "AccessControlled/Invalid";

    checkAuth(args, abi.encodeCall(AaveKandel($(kdl)).initialize, AavePooledRouter($(kdl.router()))));
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.RESERVE_ID(), maker, "Incorrect owner");
    assertEq(base.balanceOf(address(router)), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(Ask) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(Bid) > 0, "Incorrect initial reserve balance of quote");
    assertEq(
      router.overlying(base).balanceOf(address(router)),
      kdl.reserveBalance(Ask),
      "Router should have all its base on AAVE"
    );
    assertEq(
      router.overlying(quote).balanceOf(address(router)),
      kdl.reserveBalance(Bid),
      "Router should have all its quote on AAVE"
    );
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

    uint makerBalance = kdl.reserveBalance(Bid);
    uint baseAave = router.overlying(base).balanceOf(address(router));
    uint quoteAave = router.overlying(quote).balanceOf(address(router));
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    assertEq(kdl.reserveBalance(Bid), makerBalance + 1000 * 10 ** 6, "Incorrect updated balance");
    assertEq(base.balanceOf(address(router)), 0, "Router did not flush base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router did not flush quote buffer");
    assertEq(
      router.overlying(base).balanceOf(address(router)),
      baseAave + 1 ether,
      "Router should have supplied its base buffer on AAVE"
    );
    assertEq(
      router.overlying(quote).balanceOf(address(router)),
      quoteAave + 1000 * 10 ** 6,
      "Router should have supplied maker's quote on AAVE"
    );
  }

  function test_sharing_liquidity_between_strats(uint16 baseAmount, uint16 quoteAmount) public {
    deal($(base), maker, baseAmount);
    deal($(quote), maker, quoteAmount);
    GeometricKandel kdl_ = __deployKandel__(maker, maker);
    assertEq(kdl_.RESERVE_ID(), kdl.RESERVE_ID(), "Strats should have the same reserveId");

    uint baseBalance = kdl.reserveBalance(Ask);
    uint quoteBalance = kdl.reserveBalance(Bid);

    vm.prank(maker);
    kdl.depositFunds(dynamic([IERC20(base), quote]), dynamic([uint(baseAmount), quoteAmount]));

    assertEq(kdl.reserveBalance(Ask), kdl_.reserveBalance(Ask), "funds are not shared");
    assertEq(kdl.reserveBalance(Bid), kdl_.reserveBalance(Bid), "funds are not shared");
    assertApproxEqAbs(kdl.reserveBalance(Bid), quoteBalance + quoteAmount, 1, "Incorrect quote amount");
    assertApproxEqAbs(kdl.reserveBalance(Ask), baseBalance + baseAmount, 1, "Incorrect base amount");
  }

  function test_offerLogic_sharingLiquidityBetweenStratsNoDonation_offersSucceedAndFundsPushedToAave() public {
    test_offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 0,
      allBaseOnAave: true,
      allQuoteOnAave: true
    });
  }

  function test_offerLogic_sharingLiquidityBetweenStratsFirstOfferDonated_offersSucceedAndPushesBaseToAave() public {
    test_offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 1,
      allBaseOnAave: true,
      allQuoteOnAave: false
    });
  }

  function test_offerLogic_sharingLiquidityBetweenStratsBothOffersDonated_offersSucceedAndNoFundsPushedToAave() public {
    test_offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave({
      donationMultiplier: 3,
      allBaseOnAave: false,
      allQuoteOnAave: false
    });
  }

  function test_offerLogic_sharingLiquidityBetweenStrats_offersSucceedAndFundsPushedToAave(
    uint donationMultiplier,
    bool allBaseOnAave,
    bool allQuoteOnAave
  ) internal {
    GeometricKandel kdl_ = __deployKandel__(maker, maker);
    assertEq(kdl_.RESERVE_ID(), kdl.RESERVE_ID(), "Strats should have the same reserveId");

    (, MgvStructs.OfferPacked bestAsk) = getBestOffers();
    populateSingle({
      kandel: kdl_,
      index: 4,
      base: bestAsk.gives(),
      quote: bestAsk.wants(),
      pivotId: 0,
      firstAskIndex: 0,
      expectRevert: ""
    });

    deal($(base), $(router), donationMultiplier * bestAsk.gives());

    vm.prank(taker);
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), bestAsk.gives() * 2, bestAsk.wants() * 2, true);

    assertEq(takerGot, bestAsk.gives() * 2, "both asks should be taken");

    if (allBaseOnAave) {
      assertEq(
        router.overlying(base).balanceOf(address(router)),
        kdl.reserveBalance(Ask),
        "Router should have all its base on AAVE unless donation made it unnecessary to pull from AAVE"
      );
    }
    if (allQuoteOnAave) {
      assertEq(
        router.overlying(quote).balanceOf(address(router)),
        kdl.reserveBalance(Bid),
        "Router should have all its quote on AAVE unless donation made it unnecessary to pull from AAVE for first offer"
      );
    }
  }

  function test_strats_wih_same_admin_but_different_id_do_not_share_liquidity(uint16 baseAmount, uint16 quoteAmount)
    public
  {
    deal($(base), maker, baseAmount);
    deal($(quote), maker, quoteAmount);
    GeometricKandel kdl_ = __deployKandel__(maker, address(0));
    assertTrue(kdl_.RESERVE_ID() != kdl.RESERVE_ID(), "Strats should not have the same reserveId");
    vm.prank(maker);
    kdl.depositFunds(dynamic([IERC20(base), quote]), dynamic([uint(baseAmount), quoteAmount]));

    assertEq(kdl_.reserveBalance(Ask), 0, "funds should not be shared");
    assertEq(kdl_.reserveBalance(Bid), 0, "funds should not be shared");
  }

  function test_liquidity_attack() public {
    AaveCaller attacker = new AaveCaller(fork.get("Aave"), 2);
    attacker.setCallbackAddress(address(this));
    bytes memory cd = abi.encodeWithSelector(this.executeAttack.selector, address(attacker));
    uint assetSupply = attacker.get_supply(base);
    try attacker.flashloan(base, assetSupply - 1, cd) {
      assertTrue(true, "Flashloan attack succeeded");
    } catch {
      assertTrue(false, "Flashloan attack failed");
    }
  }

  function executeAttack(address attacker) external {
    deal($(quote), attacker, 1 ether);
    vm.prank(attacker);
    quote.approve({spender: address(mgv), amount: type(uint).max});
    // context base should not be available to redeem for the router, for this attack to succeed
    uint bestAsk = mgv.best($(base), $(quote));
    vm.prank(attacker);
    (,, uint takerGave, uint bounty,) =
      mgv.snipes($(base), $(quote), wrap_dynamic([bestAsk, 0.1 ether, type(uint96).max, type(uint).max]), true);
    require(takerGave == 0 && bounty > 0, "attack failed");
  }
}
