// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  GasTestBaseStored,
  MIDDLE_TICK,
  LEAF_LOWER_TICK,
  LEAF_HIGHER_TICK,
  LEVEL3_LOWER_TICK,
  LEVEL3_HIGHER_TICK,
  LEVEL2_LOWER_TICK,
  LEVEL2_HIGHER_TICK,
  LEVEL1_LOWER_TICK,
  LEVEL1_HIGHER_TICK,
  ROOT_LOWER_TICK,
  ROOT_HIGHER_TICK
} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";

// Similar to RetractOffer tests.

contract ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal tick;

  function setUp() public virtual override {
    super.setUp();
    tick = MIDDLE_TICK;
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_TICK, 0.00001 ether, 100_000, 0);
    description = "Worst case scenario where cleaning an offer from an offer list which now becomes empty";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function setUpTick(int _tick) public virtual {
    tick = _tick;
    _offerId = mgv.newOfferByTick(olKey, _tick, 0.00001 ether, 100_000, 0);
    description = "Cleaning an offer when another offer exists at various tick-distances to the offer's ratio";
  }

  function test_clean() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();
    int _tick = tick;
    vm.prank($(taker));
    _gas();
    (, uint bounty) =
      mgv.cleanByImpersonation(_olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, _tick, 100_000, 0.05 ether)), $(taker));
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

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL3_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL3_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL3_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_TICK");
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

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(ROOT_LOWER_TICK);
    description = string.concat(description, " - Case: ROOT_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(ROOT_HIGHER_TICK);
    description = string.concat(description, " - Case: ROOT_HIGHER_TICK");
  }
}

abstract contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
  }

  function setUpTick(int _tick) public virtual override {
    super.setUpTick(_tick);
    description =
      "Retracting an offer when another offer exists at various tick-distances to the offer ratio but also on the same tick";
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_MIDDLE_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_LOWER_TICK);
    description = string.concat(description, " - Case: LEAF_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL3_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL3_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL3_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL2_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL1_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_LOWER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(ROOT_LOWER_TICK);
    description = string.concat(description, " - Case: ROOT_LOWER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_HIGHER_TICK is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(ROOT_HIGHER_TICK);
    description = string.concat(description, " - Case: ROOT_HIGHER_TICK");
  }
}

contract ExternalCleanOfferOtherOfferList_WithPriorCleanOfferAndNoOtherOffersGasTest is
  TickTreeBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_TICK, 0.00001 ether, 100_000, 0);
    tickOfferIds[MIDDLE_TICK] = _offerId;
    this.newOfferOnAllTestRatios();
    offerId2 = mgv.newOfferByTick(olKey, MIDDLE_TICK, 0.00001 ether, 100_000, 0);
    description = "Cleaning a second offer at various tick-distances after cleaning an offer at MIDDLE_TICK";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int _tick) internal override {
    vm.prank($(taker));
    mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId2, MIDDLE_TICK, 100_000, 0.05 ether)), $(taker)
    );

    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(tickOfferIds[_tick], _tick, 1_000_000, 0.05 ether)), $(taker)
    );
    gas_();
    require(bounty > 0);
  }
}

abstract contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest is SingleGasTestBase {
  MgvLib.CleanTarget[] internal targets;

  function setUp() public virtual override {
    super.setUp();
  }

  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      targets.push(
        MgvLib.CleanTarget(
          mgv.newOfferByTick(olKey, MIDDLE_TICK, 0.00001 ether, 100_000, 0), MIDDLE_TICK, 100_000, 0.05 ether
        )
      );
    }
    description =
      string.concat(string.concat("Mangrove cleaning multiple offers - ", vm.toString(count), " offers at same ratio"));
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(IMangrove, TestTaker taker, OLKey memory _olKey, uint) internal virtual override {
    MgvLib.CleanTarget[] memory _targets = targets;
    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(_olKey, _targets, $(taker));
    gas_();
    assertEq(0, mgv.best(_olKey));
    require(bounty > 0);
  }
}

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest_1 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(1);
  }
}

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest_2 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(2);
  }
}

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest_4 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(4);
  }
}
