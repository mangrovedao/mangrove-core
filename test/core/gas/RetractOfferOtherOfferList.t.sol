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
import {OLKey} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";

contract ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    description =
      "Worst case scenario if strat retracts an offer from an offer list which has now become empty - with and without deprovision";
  }

  function setUpTick(int _tick) public virtual {
    _offerId = mgv.newOfferByLogPrice(olKey, _tick, 1 ether, 100_000, 0);
    description = "Retracting an offer when another offer exists at various tick-distances to the offer's price";
  }

  function test_retract_offer_deprovision() public {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, true);
    gas_();
    description = string.concat(description, " - deprovision");
    printDescription();
  }

  function test_retract_offer_keep_provision() public {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
    description = string.concat(description, " - keep provision");
    printDescription();
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_LOWER_TICK);
    description = string.concat(description, " - Case: LEAF_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL0_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL1_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL2_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

///
abstract contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestTicks();
  }

  function setUpTick(int _tick) public virtual override {
    _tick; // silence irrelevant warning for override
    description =
      "Retracting an offer when another offer exists at various tick-distances to the offer price but also on the same tick";
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_MIDDLE_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(MIDDLE_TICK);
    description = string.concat(description, " - Case: MIDDLE_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_LOWER_TICK);
    description = string.concat(description, " - Case: LEAF_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEAF_HIGHER_TICK);
    description = string.concat(description, " - Case: LEAF_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL0_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL0_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL1_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL1_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_LOWER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_LOWER_TICK);
    description = string.concat(description, " - Case: LEVEL2_LOWER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_HIGHER_TICK is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpTick(LEVEL2_HIGHER_TICK);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_TICK");
  }
}

contract ExternalRetractOfferOtherOfferList_WithPriorRetractOfferAndNoOtherOffersGasTest is
  TickBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    tickOfferIds[MIDDLE_TICK] = _offerId;
    this.newOfferOnAllTestTicks();
    offerId2 = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Retracting a second offer at various tick-distances after retracting an offer at MIDDLE_TICK";
  }

  function impl(AbstractMangrove mgv, TestTaker, OLKey memory _olKey, uint, int tick) internal override {
    mgv.retractOffer(_olKey, offerId2, false);
    uint offerId = tickOfferIds[tick];
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
  }
}
