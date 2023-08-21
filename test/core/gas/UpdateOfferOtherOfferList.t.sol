// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_TICK} from "./GasTestBase.t.sol";
import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";

contract ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick($(base), $(quote), MIDDLE_TICK, 1, true);
    assertEq(0, mgv.best($(base), $(quote)));
    description =
      "Worst case scenario if strat updates an offer on a different offer list which has become empty. This can happen in practice if offer list runs out of liquidity";
  }

  function impl(AbstractMangrove mgv, TestTaker, address base, address quote, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByTick(base, quote, MIDDLE_TICK, 0.1 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest is TickBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    description =
      "Updating an offer when another offer exists at various tick-distances to the offer's new price (initial same price)";
  }

  function impl(AbstractMangrove mgv, TestTaker, address base, address quote, uint offerId, int tick) internal override {
    _gas();
    mgv.updateOfferByTick(base, quote, tick, 1 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickGasTest is
  ExternalUpdateOfferOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestTicks();
    description =
      "Updating an offer when another offer exists at various tick-distances to the new offer price but also on the same tick";
  }
}

contract ExternalUpdateOfferOtherOfferList_WithPriorUpdateOfferAndNoOtherOffersGasTest is
  ExternalUpdateOfferOtherOfferList_WithNoOtherOffersGasTest
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    offerId2 = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick($(base), $(quote), MIDDLE_TICK, 1, true);
    assertEq(0, mgv.best($(base), $(quote)));
    description = "Updating a second offer at various tick-distances after updating an offer at MIDDLE_TICK";
  }

  function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint offerId) internal override {
    mgv.updateOfferByTick(base, quote, MIDDLE_TICK, 1 ether, 100_000, 0, offerId2);
    super.impl(mgv, taker, base, quote, offerId);
  }
}