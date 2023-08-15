// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  GasTestBaseStored,
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
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";

// Similar to RetractOffer tests.

contract ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    tick = MIDDLE_TICK;
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Worst case scenario where cleaning an offer from an offer list which now becomes empty";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function setUpTick(int tick_) public virtual {
    tick = tick_;
    _offerId = mgv.newOfferByTick($(base), $(quote), tick_, 1 ether, 100_000, 0);
    description = "Cleaning an offer when another offer exists at various tick-distances to the offer's price";
  }

  function test_clean() public {
    (AbstractMangrove mgv, TestTaker taker, address base, address quote, uint offerId) = getStored();
    vm.prank($(taker));
    _gas();
    uint bounty = mgv.clean(base, quote, offerId, tick, 100_000, 0.05 ether, true, $(taker));
    gas_();
    require(bounty > 0);
    printDescription();
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_LOWER_TICK);
    description = string.concat(description, " - Case: LEAF_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL0_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL1_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL2_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

abstract contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestTicks();
  }

  function setUpTick(int tick_) public virtual override {
    super.setUpTick(tick_);
    description =
      "Retracting an offer when another offer exists at various tick-distances to the offer price but also on the same tick";
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_MIDDLE_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_LOWER_TICK);
    description = string.concat(description, " - Case: LEAF_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL0_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL1_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL2_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithPriorCleanOfferAndNoOtherOffersGasTest is
  TickBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    tickOfferIds[MIDDLE_TICK] = _offerId;
    this.newOfferOnAllTestTicks();
    offerId2 = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Cleaning a second offer at various tick-distances after cleaning an offer at MIDDLE_TICK";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint, int tick) internal override {
    vm.prank($(taker));
    mgv.clean(base, quote, offerId2, MIDDLE_TICK, 100_000, 0.05 ether, true, $(taker));

    vm.prank($(taker));
    _gas();
    uint bounty = mgv.clean(base, quote, tickOfferIds[tick], tick, 1_000_000, 0.05 ether, true, $(taker));
    gas_();
    require(bounty > 0);
  }
}

abstract contract ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest is SingleGasTestBase {
  uint[4][] internal targets;

  MgvCleaner internal cleaner;

  function setUp() public virtual override {
    super.setUp();
    cleaner = new MgvCleaner($(mgv));
  }

  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      targets.push(
        [
          mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0),
          uint(MIDDLE_TICK),
          0.05 ether,
          100_000
        ]
      );
    }
    description =
      string.concat(string.concat("MgvCleaner cleaning multiple offers - ", vm.toString(count), " offers at same tick"));
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(AbstractMangrove, TestTaker taker, address base, address quote, uint) internal virtual override {
    uint[4][] memory targets_ = targets;
    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.collect(base, quote, targets_, false, $(taker));
    gas_();
    assertEq(0, mgv.best(base, quote));
    require(bounty > 0);
  }
}

contract ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest_1 is
  ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(1);
  }
}

contract ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest_2 is
  ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(2);
  }
}

contract ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest_4 is
  ExternalMgvCleanerOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(4);
  }
}
