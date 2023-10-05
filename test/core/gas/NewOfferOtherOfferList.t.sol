// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";

contract ExternalNewOfferOtherOfferList_AlwaysEmptyGasTest is SingleGasTestBase {
  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint) internal override {
    _gas();
    mgv.newOfferByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    gas_();
    description =
      "Worst case scenario if strat posts on different, as of yet always empty, list. This is unlikely to happen in practice";
  }
}

contract ExternalNewOfferOtherOfferList_WithNoOtherOffersGasTest is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    vm.prank($(_taker));
    mgv.marketOrderByTick(olKey, olKey.tick(MIDDLE_BIN), 1, true);
    assertEq(0, mgv.best(olKey));
    description =
      "Worst case scenario if strat posts on a different offer list which has become empty. This can happen in practice if offer list runs out of liquidity";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint) internal virtual override {
    _gas();
    mgv.newOfferByTick(_olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    gas_();
  }
}

contract ExternalNewOfferOtherOfferList_WithOtherOfferGasTest is TickTreeBoundariesGasTest, GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Posting a new offer when another offer exists at various bin-distances to the new offer";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint, Bin _bin) internal override {
    _gas();
    mgv.newOfferByTick(_olKey, _olKey.tick(_bin), 0.00001 ether, 100_000, 0);
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
      "Posting a new offer when another offer exists at various bin-distances to the new offer but also on the same bin";
  }
}

contract ExternalNewOfferOtherOfferList_WithPriorNewOfferAndNoOtherOffersGasTest is
  ExternalNewOfferOtherOfferList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description = "Posting a second new offer at various bin-distances after posting an offer at MIDDLE_BIN";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) internal override {
    mgv.newOfferByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    super.impl(mgv, taker, _olKey, offerId);
  }
}
