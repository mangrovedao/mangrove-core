// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";

// Note: These are very similar to the NewOffer tests.

contract PosthookSuccessUpdateOfferSameList_WithNoOtherOffersGasTest is TickTreeBoundariesGasTest, GasTestBase {
  bool internal failExecute;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 1_000_000, 0);
    description =
      "Updating an offer in posthook for now empty offer list but where new offer has varying closeness to taken offer";
  }

  function makerExecute(MgvLib.SingleOrder calldata sor) external virtual override returns (bytes32) {
    // Other offers succeeds.
    if (failExecute && sor.offerId == _offerId) {
      revert("makerExecute/fail");
    }
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata) public virtual override {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    if (sor.offerId == offerId) {
      int _tick = tick;
      _gas();
      // Same gasreq, not deprovisioned, gasprice unchanged.
      mgv.updateOfferByTick(_olKey, _tick, 0.00001 ether, 1_000_000, 0, offerId);
      gas_();
    }
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int) internal virtual override {
    vm.prank($(taker));
    mgv.marketOrderByTick(_olKey, MIDDLE_LOG_PRICE, 1, true);
  }
}

contract PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest is
  PosthookSuccessUpdateOfferSameList_WithNoOtherOffersGasTest
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    // We insert two others so PosthookFailure will still have the second offer on the book when executing posthook as the first is taken to do the fill.
    offerId2 = mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 1_000_000, 0);
    mgv.newOfferByTick(olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 1_000_000, 0);
    description =
      "Updating an offer in posthook for offer list with other offer at same tickTreeIndex as taken but where new offer has varying closeness to taken offer";
  }
}

contract PosthookSuccessUpdateOfferSameList_WithOtherOfferAndOfferOnSameTickTreeIndexGasTest is
  PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllHigherThanMiddleTestRatios();
    description =
      "Updating an offer in posthook for offer list with other offer at same tickTreeIndex as taken but where new offer has varying closeness to taken offer, and is written where an offer already exists on that tick";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, int _tick) internal override {
    // Skip lower ratios as they would be taken by market order if posted so they are not posted.
    if (_tick < MIDDLE_LOG_PRICE) {
      return;
    }
    super.impl(mgv, taker, _olKey, offerId, _tick);
  }
}

contract PosthookSuccessUpdateOfferSameList_WithPriorUpdateOfferAndNoOtherOffersGasTest is
  PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description =
      "Updating a second offer at various tick-distances in posthook after updating an offer at MIDDLE_LOG_PRICE";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata result) public virtual override {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    if (sor.offerId == offerId) {
      // Insert at middle ratio - the measured one is at various tick-distances.
      mgv.updateOfferByTick(_olKey, MIDDLE_LOG_PRICE, 0.00001 ether, 1_000_000, 0, offerId2);
    }
    super.makerPosthook(sor, result);
  }
}
