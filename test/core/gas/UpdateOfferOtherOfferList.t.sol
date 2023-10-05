// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import "@mgv/src/core/MgvLib.sol";

contract ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick(olKey, olKey.tick(MIDDLE_BIN), 1, true);
    assertEq(0, mgv.best(olKey));
    description =
      "Worst case scenario if strat updates an offer on a different offer list which has become empty. This can happen in practice if offer list runs out of liquidity";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest is TickTreeBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description =
      "Updating an offer when another offer exists at various tick-distances to the offer's new price (initial same price)";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId, Bin _bin) internal override {
    _gas();
    mgv.updateOfferByTick(_olKey, _olKey.tick(_bin), 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest is
  ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
    description =
      "Updating an offer when another offer exists at various bin-distances to the new offer price but also on the same bin";
  }
}

contract ExternalUpdateOfferOtherOfferList_WithPriorUpdateOfferAndNoOtherOffersGasTest is
  ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    offerId2 = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick(olKey, olKey.tick(MIDDLE_BIN), 1, true);
    assertEq(0, mgv.best(olKey));
    description = "Updating a second offer at various bin-distances after updating an offer at MIDDLE_BIN";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) internal override {
    mgv.updateOfferByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0, offerId2);
    super.impl(mgv, taker, _olKey, offerId);
  }
}
