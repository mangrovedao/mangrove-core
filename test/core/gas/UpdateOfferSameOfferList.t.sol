// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";

// Note: These are very similar to the NewOffer tests.

contract PosthookSuccessUpdateOfferSameList_WithNoOtherOffersGasTest is TickTreeBoundariesGasTest, GasTestBase {
  bool internal failExecute;

  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 1_000_000, 0);
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
      _gas();
      // Same gasreq, not deprovisioned, gasprice unchanged.
      mgv.updateOfferByTick(_olKey, _olKey.tick(bin), 0.00001 ether, 1_000_000, 0, offerId);
      gas_();
    }
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, Bin) internal virtual override {
    vm.prank($(taker));
    mgv.marketOrderByTick(_olKey, olKey.tick(MIDDLE_BIN), 1, true);
  }
}

contract PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest is
  PosthookSuccessUpdateOfferSameList_WithNoOtherOffersGasTest
{
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    // We insert two others so PosthookFailure will still have the second offer on the book when executing posthook as the first is taken to do the fill.
    offerId2 = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 1_000_000, 0);
    mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 1_000_000, 0);
    description =
      "Updating an offer in posthook for offer list with other offer at same bin as taken but where new offer has varying closeness to taken offer";
  }
}

contract PosthookSuccessUpdateOfferSameList_WithOtherOfferAndOfferOnSameBinGasTest is
  PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllHigherThanMiddleTestRatios();
    description =
      "Updating an offer in posthook for offer list with other offer at same bin as taken but where new offer has varying closeness to taken offer, and is written where an offer already exists on that bin";
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, Bin _bin) internal override {
    // Skip lower ratios as they would be taken by market order if posted so they are not posted.
    if (_bin.strictlyBetter(MIDDLE_BIN)) {
      return;
    }
    super.impl(mgv, taker, _olKey, offerId, _bin);
  }
}

contract PosthookSuccessUpdateOfferSameList_WithPriorUpdateOfferAndNoOtherOffersGasTest is
  PosthookSuccessUpdateOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description = "Updating a second offer at various bin-distances in posthook after updating an offer at MIDDLE_BIN";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata result) public virtual override {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    if (sor.offerId == offerId) {
      // Insert at middle tick - the measured one is at various bin-distances.
      mgv.updateOfferByTick(_olKey, _olKey.tick(MIDDLE_BIN), 0.00001 ether, 1_000_000, 0, offerId2);
    }
    super.makerPosthook(sor, result);
  }
}
