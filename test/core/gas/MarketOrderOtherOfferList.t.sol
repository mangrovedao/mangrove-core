// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  MIDDLE_BIN,
  LEAF_LOWER_BIN,
  LEAF_HIGHER_BIN,
  LEVEL3_LOWER_BIN,
  LEVEL3_HIGHER_BIN,
  LEVEL2_LOWER_BIN,
  LEVEL2_HIGHER_BIN,
  LEVEL1_LOWER_BIN,
  LEVEL1_HIGHER_BIN,
  ROOT_LOWER_BIN,
  ROOT_HIGHER_BIN
} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import {TickTreeLib, Bin, LEAF_SIZE, LEVEL_SIZE, ROOT_SIZE} from "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

contract ExternalMarketOrderOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  Bin internal bin;

  function setUp() public virtual override {
    super.setUp();
    bin = MIDDLE_BIN;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Worst case scenario of taking the last offer from an offer list which now becomes empty";
  }

  function setUpBin(Bin _bin) public virtual {
    bin = _bin;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(bin), 0.00001 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), 1, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    printDescription(" - Case: market order partial");
  }

  function test_market_order_partial_fillwants() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), 1, true);
    gas_();
    assertEq(0, mgv.best(_olKey));
    printDescription(" - Case: market order partial with fillwants=true");
  }

  function test_market_order_by_tick_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    printDescription(" - Case: market order by log price full fill");
  }

  function test_market_order_by_volume_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    uint takerGives = 0.00001 ether;
    uint takerWants = _olKey.tick(MIDDLE_BIN).outboundFromInbound(takerGives);
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByVolume(_olKey, takerWants, takerGives, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    printDescription(" - Case: market order by volume full fill");
  }

  function test_market_order_by_ratio_full() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, false);
    gas_();
    assertEq(0, mgv.best(_olKey));
    printDescription(" - Case: market order by tick full fill");
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest is GasTestBase {
  Bin internal bin;

  function setUp() public virtual override {
    super.setUp();
    // The offer to take
    bin = MIDDLE_BIN;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Market order taking an offer which moves the tick up various bin-distances";
  }

  function setUpBin(Bin _bin) public virtual {
    // The offer price ends up at
    bin = _bin;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(bin), 0.00001 ether, 100_000, 0);
  }

  function test_market_order_partial() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey,) = getStored();
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), 1, false);
    gas_();
    (, Local local) = mgv.config(_olKey);
    assertEq(bin, local.bestBin());
    printDescription();
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_MIDDLE_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: MIDDLE_BIN");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: LEAF_HIGHER_BIN");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL3_HIGHER_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_BIN");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_BIN");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_BIN");
  }
}

contract ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_BIN is
  ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: ROOT_HIGHER_BIN");
  }
}

abstract contract ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin is SingleGasTestBase {
  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    }
    mgv.newOfferByTick(olKey, olKey.tick(Bin.wrap(Bin.unwrap(MIDDLE_BIN) + 1)), 0.00001 ether, 100_000, 0);
    description = string.concat(string.concat("Market order taking ", vm.toString(count), " offers at same bin"));
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(MIDDLE_BIN), 2 ** 96, false);
    gas_();
    (, Local local) = mgv.config(_olKey);
    assertEq(Bin.unwrap(MIDDLE_BIN) + 1, Bin.unwrap(local.bestBin()));
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

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, Bin _bin) internal virtual override {
    vm.prank($(taker));
    _gas();
    mgv.marketOrderByTick(_olKey, _olKey.tick(_bin), 2 ** 104 - 1, false);
    gas_();
    (, Local local) = mgv.config(_olKey);
    // In some tests the market order takes all offers, in others not. `local.bestBin()` must only be called when the book is non-empty
    if (!local.root().isEmpty()) {
      assertTrue(_bin.strictlyBetter(local.bestBin()), "tick should be strictly less than current tick");
    }
  }
}
