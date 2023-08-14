// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  MIDDLE_TICK,
  LEAF_LOWER_TICK,
  LEAF_HIGHER_TICK,
  LEVEL0_LOWER_TICK,
  LEVEL0_HIGHER_TICK,
  LEVEL1_LOWER_TICK,
  LEVEL1_HIGHER_TICK,
  LEVEL2_LOWER_TICK,
  LEVEL2_HIGHER_TICK
} from "./GasTestBase.t.sol";
import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";
import {TickLib, Tick, LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE} from "mgv_lib/TickLib.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

contract ExternalMarketOrderOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    tick = MIDDLE_TICK;
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Worst case scenario of taking the last offer from an offer list which now becomes empty";
  }

  function setUpTick(int tick_) public virtual {
    tick = tick_;
    _offerId = mgv.newOfferByTick($(base), $(quote), tick_, 1 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, MIDDLE_TICK, 1, false);
    gas_();
    assertEq(0, mgv.best(base, quote));
    description = string.concat(description, " - Case: market order partial");
    printDescription();
  }

  function test_market_order_partial_fillwants() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, MIDDLE_TICK, 1, true);
    gas_();
    assertEq(0, mgv.best(base, quote));
    description = string.concat(description, " - Case: market order partial with fillwants=true");
    printDescription();
  }

  function test_market_order_by_tick_full() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, MIDDLE_TICK, 1 ether, false);
    gas_();
    assertEq(0, mgv.best(base, quote));
    description = string.concat(description, " - Case: market order by tick full fill");
    printDescription();
  }

  function test_market_order_by_volume_full() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    uint takerGives = 1 ether;
    uint takerWants = TickLib.outboundFromInbound(Tick.wrap(MIDDLE_TICK), takerGives);
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByVolume(base, quote, takerWants, takerGives, false);
    gas_();
    assertEq(0, mgv.best(base, quote));
    description = string.concat(description, " - Case: market order by volume full fill");
    printDescription();
  }

  function test_market_order_by_price_full() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    uint price = TickLib.priceFromTick_e18(Tick.wrap(MIDDLE_TICK));
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByPrice(base, quote, price, 1 ether, false);
    gas_();
    assertEq(0, mgv.best(base, quote));
    description = string.concat(description, " - Case: market order by price full fill");
    printDescription();
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    // The offer to take
    tick = MIDDLE_TICK;
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Market order taking an offer which moves the price up various tick-distances";
  }

  function setUpTick(int tick_) public virtual {
    // The offer price ends up at
    tick = tick_;
    _offerId = mgv.newOfferByTick($(base), $(quote), tick_, 1 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, MIDDLE_TICK, 1, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(base, quote);
    assertEq(tick, Tick.unwrap(local.tick()));
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_MIDDLE_TICK is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_TICK is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_TICK is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_TICK");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_TICK is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_TICK is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick is SingleGasTestBase {
  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    }
    mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK + 1, 1 ether, 100_000, 0);
    description = string.concat(string.concat("Market order taking ", vm.toString(count), " offers at same tick"));
  }

  function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, MIDDLE_TICK, 2 ** 96, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(base, quote);
    assertEq(MIDDLE_TICK + 1, Tick.unwrap(local.tick()));
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick_1 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(1);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick_2 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(2);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick_4 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(4);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtManyTicks is TickBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestTicks();
    description = "Market order taking offers up to a tick with offers on all test ticks";
  }

  function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint, int tick)
    internal
    virtual
    override
  {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(base, quote, tick, 2 ** 96, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(base, quote);
    assertLt(tick, Tick.unwrap(local.tick()));
  }
}
