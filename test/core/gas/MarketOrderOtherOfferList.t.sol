// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  MIDDLE_LOG_PRICE,
  LEAF_LOWER_LOG_PRICE,
  LEAF_HIGHER_LOG_PRICE,
  LEVEL0_LOWER_LOG_PRICE,
  LEVEL0_HIGHER_LOG_PRICE,
  LEVEL1_LOWER_LOG_PRICE,
  LEVEL1_HIGHER_LOG_PRICE,
  LEVEL2_LOWER_LOG_PRICE,
  LEVEL2_HIGHER_LOG_PRICE
} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";
import {TickLib, Tick, LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE} from "mgv_lib/TickLib.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

contract ExternalMarketOrderOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal logPrice;

  function setUp() public virtual override {
    super.setUp();
    logPrice = MIDDLE_LOG_PRICE;
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    description = "Worst case scenario of taking the last offer from an offer list which now becomes empty";
  }

  function setUpLogPrice(int _logPrice) public virtual {
    logPrice = _logPrice;
    _offerId = mgv.newOfferByLogPrice(olKey, _logPrice, 1 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order partial");
    printDescription();
  }

  function test_market_order_partial_fillwants() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1, true);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order partial with fillwants=true");
    printDescription();
  }

  function test_market_order_by_log_price_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by log price full fill");
    printDescription();
  }

  function test_market_order_by_volume_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    uint takerGives = 1 ether;
    uint takerWants = LogPriceLib.outboundFromInbound(MIDDLE_LOG_PRICE, takerGives);
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByVolume(_olKey, takerWants, takerGives, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by volume full fill");
    printDescription();
  }

  function test_market_order_by_price_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by price full fill");
    printDescription();
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest is GasTestBase {
  int internal logPrice;

  function setUp() public virtual override {
    super.setUp();
    // The offer to take
    logPrice = MIDDLE_LOG_PRICE;
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    description = "Market order taking an offer which moves the price up various tick-distances";
  }

  function setUpLogPrice(int _logPrice) public virtual {
    // The offer price ends up at
    logPrice = _logPrice;
    _offerId = mgv.newOfferByLogPrice(olKey, _logPrice, 1 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    assertEq(logPrice, LogPriceLib.fromTick(local.bestTick(), _olKey.tickScale));
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_MIDDLE_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameTick is SingleGasTestBase {
  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    }
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE + 1, 1 ether, 100_000, 0);
    description = string.concat(string.concat("Market order taking ", vm.toString(count), " offers at same tick"));
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 2 ** 96, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    assertEq(MIDDLE_LOG_PRICE + 1, LogPriceLib.fromTick(local.bestTick(), _olKey.tickScale));
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
    this.newOfferOnAllTestPrices();
    description = "Market order taking offers up to a tick with offers on all test ticks";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int _logPrice) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByLogPrice(_olKey, _logPrice, 2 ** 96, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    // In some tests the market order takes all offers, in others not. `local.bestTick()` must only be called when the book is non-empty
    if (!local.level3().isEmpty()) {
      assertLt(_logPrice, LogPriceLib.fromTick(local.bestTick(), _olKey.tickScale));
    }
  }
}
