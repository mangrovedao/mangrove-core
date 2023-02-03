// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {CoreKandelTest, CoreKandel, GeometricKandel, IMangrove, HasIndexedOffers, MgvLib} from "./CoreKandel.t.sol";
import {AaveKandel, AavePooledRouter} from "mgv_src/strategies/offer_maker/market_making/kandel/AaveKandel.sol";
import {PinnedPolygonFork} from "mgv_test/lib/forks/Polygon.sol";

contract AaveKandelTest is CoreKandelTest {
  PinnedPolygonFork fork;
  AavePooledRouter router;
  AaveKandel aaveKandel;

  function __setForkEnvironment__() internal override {
    fork = new PinnedPolygonFork();
    fork.setUp();
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));
    base = TestToken(fork.get("WETH"));
    quote = TestToken(fork.get("USDC"));
    setupMarket(base, quote);
  }

  function __deployKandel__(address deployer) internal virtual override returns (GeometricKandel) {
    // 474_000 theoretical in mock up of router
    // 218_000 observed in tests of router
    uint router_gasreq = 318 * 1000;
    uint kandel_gasreq = 128 * 1000;
    router = new AavePooledRouter(fork.get("Aave"), router_gasreq);
    aaveKandel = new AaveKandel({
      mgv: IMangrove($(mgv)),
      base: base,
      quote: quote,
      gasreq: kandel_gasreq,
      gasprice: 0,
      owner: deployer
    });

    router.bind(address(aaveKandel));
    // Setting AaveRouter as Kandel's router and activating router on BASE and QUOTE ERC20
    aaveKandel.initialize(router);
    aaveKandel.setAdmin(deployer);
    assertEq(aaveKandel.offerGasreq(), kandel_gasreq + router_gasreq, "Incorrect gasreq");
    return aaveKandel;
  }

  function test_initialize() public {
    assertEq(address(kdl.router()), address(router), "Incorrect router address");
    assertEq(kdl.admin(), maker, "Incorrect admin");
    assertEq(kdl.owner(), maker, "Incorrect owner");
    assertEq(base.balanceOf(address(router)), 0, "Router should start with no base buffer");
    assertEq(quote.balanceOf(address(router)), 0, "Router should start with no quote buffer");
    assertTrue(kdl.reserveBalance(base) > 0, "Incorrect initial reserve balance of base");
    assertTrue(kdl.reserveBalance(quote) > 0, "Incorrect initial reserve balance of quote");
    assertEq(
      router.overlying(base).balanceOf(address(router)),
      kdl.reserveBalance(base),
      "Router should have all its base on AAVE"
    );
    assertEq(
      router.overlying(quote).balanceOf(address(router)),
      kdl.reserveBalance(quote),
      "Router should have all its quote on AAVE"
    );
  }

  struct SingleOrder {
    address outbound_tkn;
    address inbound_tkn;
    uint offerId;
    MgvStructs.OfferPacked offer;
    /* `wants`/`gives` mutate over execution. Initially the `wants`/`gives` from the taker's pov, then actual `wants`/`gives` adjusted by offer's price and volume. */
    uint wants;
    uint gives;
    /* `offerDetail` is only populated when necessary. */
    MgvStructs.OfferDetailPacked offerDetail;
    MgvStructs.GlobalPacked global;
    MgvStructs.LocalPacked local;
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
    assertEq(makerData, "mgvOffer/proceed", "Unexpected returned data");
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
    MgvLib.SingleOrder memory order;
    order.outbound_tkn = $(base);
    order.inbound_tkn = $(quote);
    order.wants = 0.1 ether;
    order.gives = 120 * 10 ** 6;
    // complete fill (prev and next don't matter)
    order.offer = MgvStructs.Offer.pack({__prev: 0, __next: 0, __wants: order.gives, __gives: order.wants});

    MgvLib.OrderResult memory result = MgvLib.OrderResult({makerData: "IS_FIRST_PULLER", mgvData: "mgv/tradeSuccess"});

    //1. faking accumulated outbound on the router
    deal($(base), $(router), 1 ether);
    //2. faking accumulated inbound on kandel
    deal($(quote), $(kdl), 1000 * 10 ** 6);

    uint makerBalance = kdl.reserveBalance(quote);
    uint baseAave = router.overlying(base).balanceOf(address(router));
    uint quoteAave = router.overlying(quote).balanceOf(address(router));
    vm.prank($(mgv));
    kdl.makerPosthook(order, result);
    assertEq(kdl.reserveBalance(quote), makerBalance + 1000 * 10 ** 6, "Incorrect updated balance");
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
}
