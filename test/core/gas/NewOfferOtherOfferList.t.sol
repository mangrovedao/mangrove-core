// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

contract ExternalNewOfferOtherOfferList_AlwaysEmptyGasTest is SingleGasTestBase {
  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint) internal override {
    _gas();
    mgv.newOfferByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    gas_();
    description =
      "Worst case scenario if strat posts on different, as of yet always empty, list. This is unlikely to happen in practice";
  }
}

contract ExternalNewOfferOtherOfferList_WithNoOtherOffersGasTest is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick(olKey, MIDDLE_LOG_PRICE, 1, true);
    assertEq(0, mgv.best(olKey));
    description =
      "Worst case scenario if strat posts on a different offer list which has become empty. This can happen in practice if offer list runs out of liquidity";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint) internal virtual override {
    _gas();
    mgv.newOfferByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    gas_();
  }
}

contract ExternalNewOfferOtherOfferList_WithOtherOfferGasTest is TickTreeBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    description = "Posting a new offer when another offer exists at various tick-distances to the new offer";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint, int _tick) internal override {
    _gas();
    mgv.newOfferByTick(_olKey, _tick, 0.00001 ether, 100_000, 0);
    gas_();
  }
}

contract ExternalNewOfferOtherOfferList_WithOtherOfferAndOfferOnSameBinGasTest is
  ExternalNewOfferOtherOfferList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestRatios();
    description =
      "Posting a new offer when another offer exists at various tick-distances to the new offer but also on the same tick";
  }
}

contract ExternalNewOfferOtherOfferList_WithPriorNewOfferAndNoOtherOffersGasTest is
  ExternalNewOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description = "Posting a second new offer at various tick-distances after posting an offer at MIDDLE_LOG_PRICE";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) internal override {
    mgv.newOfferByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 100_000, 0);
    super.impl(mgv, taker, _olKey, offerId);
  }
}
