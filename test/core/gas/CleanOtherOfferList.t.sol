// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  GasTestBaseStored,
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

// Similar to RetractOffer tests.

contract ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  Bin internal bin;

  function setUp() public virtual override {
    super.setUp();
    bin = MIDDLE_BIN;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Worst case scenario where cleaning an offer from an offer list which now becomes empty";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function setUpBin(Bin _bin) public virtual {
    bin = _bin;
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(_bin), 0.00001 ether, 100_000, 0);
    description = "Cleaning an offer when another offer exists at various bin-distances to the offer's ratio";
  }

  function test_clean() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();
    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, _olKey.tick(bin), 100_000, 0.05 ether)), $(taker)
    );
    gas_();
    require(bounty > 0);
    printDescription();
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: MIDDLE_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_LOWER_BIN);
    description = string.concat(description, " - Case: LEAF_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: LEAF_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL3_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL3_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL2_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL1_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_LOWER_BIN);
    description = string.concat(description, " - Case: ROOT_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: ROOT_HIGHER_BIN");
  }
}

abstract contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
  }

  function setUpBin(Bin _bin) public virtual override {
    super.setUpBin(_bin);
    description =
      "Retracting an offer when another offer exists at various bin-distances to the offer price but also on the same bin";
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_MIDDLE_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: MIDDLE_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_LOWER_BIN);
    description = string.concat(description, " - Case: LEAF_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEAF_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: LEAF_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL3_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL3_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL3_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL2_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL2_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_LOWER_BIN);
    description = string.concat(description, " - Case: LEVEL1_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_LEVEL1_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_LOWER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_LOWER_BIN);
    description = string.concat(description, " - Case: ROOT_LOWER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest_ROOT_HIGHER_BIN is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: ROOT_HIGHER_BIN");
  }
}

contract ExternalCleanOfferOtherOfferList_WithPriorCleanOfferAndNoOtherOffersGasTest is
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
    description = "Cleaning a second offer at various bin-distances after cleaning an offer at MIDDLE_BIN";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, Bin bin) internal override {
    vm.prank($(taker));
    mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId2, _olKey.tick(MIDDLE_BIN), 100_000, 0.05 ether)), $(taker)
    );

    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(binOfferIds[bin], _olKey.tick(bin), 1_000_000, 0.05 ether)), $(taker)
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
          mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0),
          olKey.tick(MIDDLE_BIN),
          100_000,
          0.05 ether
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
