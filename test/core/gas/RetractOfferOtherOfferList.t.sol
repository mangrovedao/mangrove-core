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

contract ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description =
      "Worst case scenario if strat retracts an offer from an offer list which has now become empty - with and without deprovision";
  }

  function setUpBin(Bin _bin) public virtual {
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(_bin), 0.00001 ether, 100_000, 0);
    description = "Retracting an offer when another offer exists at various bin-distances to the offer's ratio";
  }

  function test_retract_offer_deprovision() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, true);
    gas_();
    printDescription(" - deprovision");
  }

  function test_retract_offer_keep_provision() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
    printDescription(" - keep provision");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: MIDDLE_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_LOWER_BIN);
    description = string.concat(description, " - Case: LEAF_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: LEAF_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL3_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL2_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL1_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_ROOT_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_LOWER_BIN);
    description = string.concat(description, " - Case: ROOT_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: ROOT_HIGHER_BIN");
  }
}

///
abstract contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest is
  ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
  }

  function setUpBin(Bin _bin) public virtual override {
    _bin; // silence irrelevant warning for override
    description =
      "Retracting an offer when another offer exists at various bin-distances to the offer price but also on the same bin";
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_MIDDLE_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: MIDDLE_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_LOWER_BIN);
    description = string.concat(description, " - Case: LEAF_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: LEAF_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL3_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL2_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL1_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_LOWER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_LOWER_BIN);
    description = string.concat(description, " - Case: ROOT_LOWER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_HIGHER_BIN is
  ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: ROOT_HIGHER_BIN");
  }
}

contract ExternalRetractOfferOtherOfferList_WithPriorRetractOfferAndNoOtherOffersGasTest is
  TickTreeBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    binOfferIds[MIDDLE_BIN] = _offerId;
    this.newOfferOnAllTestRatios();
    offerId2 = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Retracting a second offer at various bin-distances after retracting an offer at MIDDLE_BIN";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint, Bin _bin) internal override {
    mgv.retractOffer(_olKey, offerId2, false);
    uint offerId = binOfferIds[_bin];
    _gas();
    mgv.retractOffer(_olKey, offerId, false);
    gas_();
  }
}
