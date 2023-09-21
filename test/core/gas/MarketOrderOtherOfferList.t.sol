// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  MIDDLE_LOG_PRICE,
  LEAF_LOWER_LOG_PRICE,
  LEAF_HIGHER_LOG_PRICE,
  LEVEL2_LOWER_LOG_PRICE,
  LEVEL2_HIGHER_LOG_PRICE,
  LEVEL1_LOWER_LOG_PRICE,
  LEVEL1_HIGHER_LOG_PRICE,
  LEVEL0_LOWER_LOG_PRICE,
  LEVEL0_HIGHER_LOG_PRICE,
  ROOT_LOWER_LOG_PRICE,
  ROOT_HIGHER_LOG_PRICE
} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import {BinLib, Bin, LEAF_SIZE, LEVEL_SIZE, ROOT_SIZE} from "mgv_lib/BinLib.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

contract ExternalMarketOrderOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    tick = MIDDLE_LOG_PRICE;
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description = "Worst case scenario of taking the last offer from an offer list which now becomes empty";
  }

  function setUpTick(int _tick) public virtual {
    tick = _tick;
    _offerId = mgv.newOfferByTick(olKey, _tick, 0.00001 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 1, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order partial");
    printDescription();
  }

  function test_market_order_partial_fillwants() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 1, true);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order partial with fillwants=true");
    printDescription();
  }

  function test_market_order_by_log_price_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by log price full fill");
    printDescription();
  }

  function test_market_order_by_volume_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    uint takerGives = 0.00001 ether;
    uint takerWants = TickLib.outboundFromInbound(MIDDLE_LOG_PRICE, takerGives);
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByVolume(_olKey, takerWants, takerGives, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by volume full fill");
    printDescription();
  }

  function test_market_order_by_ratio_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    description = string.concat(description, " - Case: market order by ratio full fill");
    printDescription();
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    // The offer to take
    tick = MIDDLE_LOG_PRICE;
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description = "Market order taking an offer which moves the ratio up various tick-distances";
  }

  function setUpTick(int _tick) public virtual {
    // The offer ratio ends up at
    tick = _tick;
    _offerId = mgv.newOfferByTick(olKey, _tick, 0.00001 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 1, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    assertEq(tick, TickLib.fromBin(local.bestBin(), _olKey.tickSpacing));
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_MIDDLE_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_LOG_PRICE is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(ROOT_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: ROOT_HIGHER_LOG_PRICE");
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin is SingleGasTestBase {
  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      _offerId = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    }
    mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE + 1, 0.00001 ether, 100_000, 0);
    description = string.concat(string.concat("Market order taking ", vm.toString(count), " offers at same tick"));
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 2 ** 96, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    assertEq(MIDDLE_LOG_PRICE + 1, TickLib.fromBin(local.bestBin(), _olKey.tickSpacing));
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin_1 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(1);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin_2 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(2);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin_4 is
  ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(4);
  }
}

contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtManyBins is TickTreeBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
    description = "Market order taking offers up to a bin with offers on all test ticks";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int _tick) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _tick, 2 ** 104 - 1, false);
    gas_();
    (, MgvStructs.LocalPacked local) = mgv.config(_olKey);
    // In some tests the market order takes all offers, in others not. `local.bestBin()` must only be called when the book is non-empty
    if (!local.root().isEmpty()) {
      assertLt(
        _tick, TickLib.fromBin(local.bestBin(), _olKey.tickSpacing), "tick should be strictly less than current tick"
      );
    }
  }
}
