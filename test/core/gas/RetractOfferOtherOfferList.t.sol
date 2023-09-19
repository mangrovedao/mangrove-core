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
  LEVEL2_HIGHER_LOG_PRICE,
  LEVEL3_LOWER_LOG_PRICE,
  LEVEL3_HIGHER_LOG_PRICE
} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {OLKey} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";

contract ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    description =
      "Worst case scenario if strat retracts an offer from an offer list which has now become empty - with and without deprovision";
  }

  function setUpLogPrice(int _logPrice) public virtual {
    _offerId = mgv.newOfferByLogPrice(olKey, _logPrice, 1 ether, 100_000, 0);
    description = "Retracting an offer when another offer exists at various tick-distances to the offer's price";
  }

  function test_retract_offer_deprovision() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, true);
    gas_();
    description = string.concat(description, " - deprovision");
    printDescription();
  }

  function test_retract_offer_keep_provision() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
    description = string.concat(description, " - keep provision");
    printDescription();
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL3_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL3_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL3_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_LOG_PRICE");
  }
}

///
abstract contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestPrices();
  }

  function setUpLogPrice(int _logPrice) public virtual override {
    _logPrice; // silence irrelevant warning for override
    description =
      "Retracting an offer when another offer exists at various tick-distances to the offer price but also on the same tick";
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_MIDDLE_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL3_LOWER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL3_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL3_LOWER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL3_HIGHER_LOG_PRICE is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL3_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_LOG_PRICE");
  }
}

contract ExternalRetractOfferOtherOfferList_WithPriorRetractOfferAndNoOtherOffersGasTest is
  TickBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    logPriceOfferIds[MIDDLE_LOG_PRICE] = _offerId;
    this.newOfferOnAllTestPrices();
    offerId2 = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 100_000, 0);
    description = "Retracting a second offer at various tick-distances after retracting an offer at MIDDLE_LOG_PRICE";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint, int _logPrice) internal override {
    mgv.retractOffer(_olKey, offerId2, false);
    uint offerId = logPriceOfferIds[_logPrice];
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
  }
}
