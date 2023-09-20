// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

contract ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByLogPrice(olKey, MIDDLE_LOG_PRICE, 1, true);
    assertEq(0, mgv.best(olKey));
    description =
      "Worst case scenario if strat updates an offer on a different offer list which has become empty. This can happen in practice if offer list runs out of liquidity";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByLogPrice(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest is TickTreeBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description =
      "Updating an offer when another offer exists at various tick-distances to the offer's new ratio (initial same ratio)";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId, int _logPrice) internal override {
    _gas();
    mgv.updateOfferByLogPrice(_olKey, _logPrice, 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickTreeIndexGasTest is
  ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
    description =
      "Updating an offer when another offer exists at various tick-distances to the new offer ratio but also on the same tick";
  }
}

contract ExternalUpdateOfferOtherOfferList_WithPriorUpdateOfferAndNoOtherOffersGasTest is
  ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    offerId2 = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByLogPrice(olKey, MIDDLE_LOG_PRICE, 1, true);
    assertEq(0, mgv.best(olKey));
    description = "Updating a second offer at various tick-distances after updating an offer at MIDDLE_LOG_PRICE";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) internal override {
    mgv.updateOfferByLogPrice(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0, offerId2);
    super.impl(mgv, taker, _olKey, offerId);
  }
}
