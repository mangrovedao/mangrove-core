// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "./KandelTest.t.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Kandel} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

abstract contract CoreKandelGasTest is KandelTest {
  uint internal completeFill_;
  uint internal partialFill_;

  function setUp() public virtual override {
    super.setUp();
    vm.prank(maker);
    kdl.setCompoundRates(10 ** PRECISION, 10 ** PRECISION);
  }

  function densifyBids(uint fold) internal {
    densify(address(base), address(quote), 1, 5, fold, address(this));
  }

  function densifyAsks(uint fold) internal {
    densify(address(quote), address(base), 5, 5, fold, address(this));
  }

  // function test_densify() public {
  //   printOrderBook(address(base), address(quote));
  //   printOrderBook(address(quote), address(base));

  //   densifyBids(2);
  //   printOrderBook(address(base), address(quote));
  //   printOrderBook(address(quote), address(base));

  //   densifyAsks(2);
  //   printOrderBook(address(base), address(quote));
  //   printOrderBook(address(quote), address(base));
  // }

  function test_log_mgv_config() public view {
    (, MgvStructs.LocalPacked local) = mgv.config($(base), $(quote));
    console.log("offer_gasbase", local.offer_gasbase());
    console.log("kandel gasreq", kdl.offerGasreq());
  }

  function test_complete_fill_bid_order() public {
    uint completeFill = completeFill_;
    _gas();
    vm.prank(taker);
    // taking partial fill to have gas cost of reposting
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), completeFill, type(uint160).max, true);
    gas_();
    require(takerGot > 0);
  }

  function test_bid_order_length_1() public {
    uint partialFill = partialFill_;
    _gas();
    vm.prank(taker);
    // taking partial fill to have gas cost of reposting (all offers give 0.108 ethers)
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), partialFill, type(uint160).max, true);
    uint g = gas_(true);
    assertEq(reader.minusFee($(base), $(quote), partialFill), takerGot, "Incorrect got");
    console.log(1, ",", g);
    assertStatus(4, OfferStatus.Bid);
  }

  function test_bid_order_length_2() public {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    _gas();
    vm.prank(taker);
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), completeFill + partialFill, type(uint160).max, true);
    uint g = gas_(true);
    require(takerGot > 0);
    console.log(2, ",", g);
    assertStatus(3, OfferStatus.Bid);
  }

  function test_bid_order_length_3() public {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    _gas();
    vm.prank(taker);
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), completeFill * 2 + partialFill, type(uint160).max, true);
    uint g = gas_(true);
    require(takerGot > 0);
    console.log(3, ",", g);
    assertStatus(2, OfferStatus.Bid);
  }

  function test_bid_order_length_4() public {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    _gas();
    vm.prank(taker);
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), completeFill * 3 + partialFill, type(uint160).max, true);
    uint g = gas_(true);
    require(takerGot > 0);
    console.log(4, ",", g);
    assertStatus(1, OfferStatus.Bid);
  }

  function test_bid_order_length_5() public {
    uint completeFill = completeFill_;
    uint partialFill = partialFill_;
    _gas();
    vm.prank(taker);
    (uint takerGot,,,) = mgv.marketOrder($(base), $(quote), completeFill * 4 + partialFill, type(uint160).max, true);
    uint g = gas_(true);
    require(takerGot > 0);
    console.log(5, ",", g);
    assertStatus(0, OfferStatus.Bid);
  }

  function test_offerLogic_partialFill_cost() public {
    // take Ask #5
    MgvStructs.OfferPacked ask = kdl.getOffer(Ask, 6);

    (MgvLib.SingleOrder memory order, MgvLib.OrderResult memory result) = mockBuyOrder({
      takerGives: ask.wants() / 2,
      takerWants: ask.gives() / 2,
      partialFill: 1,
      base_: base,
      quote_: quote,
      makerData: ""
    });
    order.offerId = kdl.offerIdOfIndex(Ask, 6);
    order.offer = ask;
    vm.prank($(mgv));
    _gas();
    kdl.makerExecute(order);
    uint g = gas_(true);
    console.log("makerExecute", g);
    vm.prank($(mgv));
    _gas();
    kdl.makerPosthook(order, result);
    g = gas_(true);
    console.log("makerPosthook", g);
    assertStatus(6, OfferStatus.Ask);
    assertStatus(5, OfferStatus.Crossed);
  }
}
