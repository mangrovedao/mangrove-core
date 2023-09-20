// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  SingleGasTestBase,
  GasTestBase,
  GasTestBaseStored,
  MIDDLE_LOG_PRICE,
  LEAF_LOWER_LOG_PRICE,
  LEAF_HIGHER_LOG_PRICE,
  LEVEL0_LOWER_LOG_PRICE,
  LEVEL0_HIGHER_LOG_PRICE,
  LEVEL1_LOWER_LOG_PRICE,
  LEVEL1_HIGHER_LOG_PRICE,
  LEVEL2_LOWER_LOG_PRICE,
  LEVEL2_HIGHER_LOG_PRICE,
  ROOT_LOWER_LOG_PRICE,
  ROOT_HIGHER_LOG_PRICE
} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";

// Similar to RetractOffer tests.

contract ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest is GasTestBase {
  int internal logPrice;

  function setUp() public virtual override {
    super.setUp();
    logPrice = MIDDLE_LOG_PRICE;
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description = "Worst case scenario where cleaning an offer from an offer list which now becomes empty";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function setUpLogPrice(int _logPrice) public virtual {
    logPrice = _logPrice;
    _offerId = mgv.newOfferByLogPrice(olKey, _logPrice, 0.00001 ether, 100_000, 0);
    description = "Cleaning an offer when another offer exists at various tick-distances to the offer's price";
  }

  function test_clean() public {
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();
    int _logPrice = logPrice;
    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, _logPrice, 100_000, 0.05 ether)), $(taker)
    );
    gas_();
    require(bounty > 0);
    printDescription();
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_MIDDLE_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(ROOT_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: ROOT_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferGasTest_ROOT_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(ROOT_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: ROOT_HIGHER_LOG_PRICE");
  }
}

abstract contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest is
  ExternalCleanOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestPrices();
  }

  function setUpLogPrice(int _logPrice) public virtual override {
    super.setUpLogPrice(_logPrice);
    description =
      "Retracting an offer when another offer exists at various tick-distances to the offer price but also on the same tick";
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_MIDDLE_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: MIDDLE_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEAF_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEAF_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL0_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL0_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL1_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL1_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_LEVEL2_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: LEVEL2_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_ROOT_LOWER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(ROOT_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: ROOT_LOWER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest_ROOT_HIGHER_LOG_PRICE is
  ExternalCleanOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpLogPrice(ROOT_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: ROOT_HIGHER_LOG_PRICE");
  }
}

contract ExternalCleanOfferOtherOfferList_WithPriorCleanOfferAndNoOtherOffersGasTest is
  TickBoundariesGasTest,
  GasTestBase
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    logPriceOfferIds[MIDDLE_LOG_PRICE] = _offerId;
    this.newOfferOnAllTestPrices();
    offerId2 = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description = "Cleaning a second offer at various tick-distances after cleaning an offer at MIDDLE_LOG_PRICE";
  }

  function makerExecute(MgvLib.SingleOrder calldata) external virtual override returns (bytes32) {
    revert("fail"); // fail
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int _logPrice) internal override {
    vm.prank($(taker));
    mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(offerId2, MIDDLE_LOG_PRICE, 100_000, 0.05 ether)), $(taker)
    );

    vm.prank($(taker));
    _gas();
    (, uint bounty) = mgv.cleanByImpersonation(
      _olKey, wrap_dynamic(MgvLib.CleanTarget(logPriceOfferIds[_logPrice], _logPrice, 1_000_000, 0.05 ether)), $(taker)
    );
    gas_();
    require(bounty > 0);
  }
}

abstract contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest is SingleGasTestBase {
  MgvLib.CleanTarget[] internal targets;

  function setUp() public virtual override {
    super.setUp();
  }

  function setUpOffers(uint count) internal {
    for (uint i; i < count; ++i) {
      targets.push(
        MgvLib.CleanTarget(
          mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0),
          MIDDLE_LOG_PRICE,
          100_000,
          0.05 ether
        )
      );
    }
    description =
      string.concat(string.concat("Mangrove cleaning multiple offers - ", vm.toString(count), " offers at same price"));
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

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest_1 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(1);
  }
}

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest_2 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(2);
  }
}

contract ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest_4 is
  ExternalCleanOtherOfferList_WithMultipleOffersAtSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    setUpOffers(4);
  }
}
