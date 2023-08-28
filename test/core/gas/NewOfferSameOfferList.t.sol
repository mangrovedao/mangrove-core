// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";

contract PosthookSuccessNewOfferSameList_WithNoOtherOffersGasTest is TickBoundariesGasTest, GasTestBase {
  bool internal failExecute;

  function setUp() public virtual override {
    super.setUp();
    // At price MIDDLE_LOG_PRICE so we can post a better or worse offer in same leaf.
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 1_000_000, 0);
    description =
      "Posting a new offer in posthook for now empty offer list but where new offer has varying closeness to taken offer";
  }

  function makerExecute(MgvLib.SingleOrder calldata sor) external virtual override returns (bytes32) {
    // Other offers succeeds.
    if (failExecute && sor.offerId == _offerId) {
      revert("makerExecute/fail");
    }
    return "";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata) public virtual override {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    if (sor.offerId == offerId) {
      int _logPrice = logPrice;
      _gas();
      mgv.newOfferByLogPrice(_olKey, _logPrice, 1 ether, 1_000_000, 0);
      gas_();
    }
  }

  function impl(AbstractMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int) internal virtual override {
    vm.prank($(taker));
    mgv.marketOrderByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1, true);
  }
}

contract PosthookSuccessNewOfferSameList_WithOtherOfferGasTest is
  PosthookSuccessNewOfferSameList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    // We insert two others so PosthookFailure will still have the second offer on the book when executing posthook as the first is taken to do the fill.
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 1_000_000, 0);
    mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1 ether, 1_000_000, 0);
    description =
      "Posting a new offer in posthook for offer list with other offer at same tick as taken but where new offer has varying closeness to taken offer";
  }
}

contract PosthookSuccessNewOfferSameList_WithOtherOfferAndOfferOnSameTickGasTest is
  PosthookSuccessNewOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllHigherThanMiddleTestPrices();
    description =
      "Posting a new offer in posthook for offer list with other offer at same tick as taken but where new offer has varying closeness to taken offer, and is written where an offer already exists on that tick. This is only representative for ticks higher than the middle, as lower ticks would be taken by market order";
  }

  function impl(AbstractMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, int _logPrice)
    internal
    override
  {
    // Skip lower prices as they would be taken by market order if posted so they are not posted.
    if (_logPrice < MIDDLE_LOG_PRICE) {
      return;
    }
    super.impl(mgv, taker, _olKey, offerId, _logPrice);
  }
}

contract PosthookSuccessNewOfferSameList_WithPriorNewOfferAndNoOtherOffersGasTest is
  PosthookSuccessNewOfferSameList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description =
      "Posting a second new offer at various tick-distances in posthook after posting an offer at MIDDLE_LOG_PRICE";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata result) public virtual override {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    if (sor.offerId == offerId) {
      // Insert at middle price - the measured one is at various tick-distances.
      mgv.newOfferByLogPrice(_olKey, MIDDLE_LOG_PRICE, 1 ether, 1_000_000, 0);
    }
    super.makerPosthook(sor, result);
  }
}

contract PosthookFailureNewOfferSameListWith_NoOtherOffersGasTest is
  PosthookSuccessNewOfferSameList_WithNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    failExecute = true;
    description =
      "Posting a new offer in posthook after offer failure for now empty offer list but where new offer has varying closeness to taken offer";
  }
}

contract PosthookFailureNewOfferSameListWith_OtherOfferGasTest is
  PosthookSuccessNewOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    failExecute = true;
    description =
      "Posting a new offer in posthook after offer failure for offer list with other offer at same tick as taken but where new offer has varying closeness to taken offer";
  }
}

contract PosthookFailureNewOfferSameList_WithOtherOfferAndOfferOnSameTickGasTest is
  PosthookSuccessNewOfferSameList_WithOtherOfferAndOfferOnSameTickGasTest
{
  function setUp() public virtual override {
    super.setUp();
    failExecute = true;
    description =
      "Posting a new offer in posthook after offer failure for offer list with other offer at same tick as taken but where new offer has varying closeness to taken offer, and is written where an offer already exists on that tick";
  }
}

contract PosthookFailureNewOfferSameListWith_PriorNewOfferAndNoOtherOffersGasTest is
  PosthookSuccessNewOfferSameList_WithPriorNewOfferAndNoOtherOffersGasTest
{
  function setUp() public virtual override {
    super.setUp();
    failExecute = true;
    description =
      "Posting a second new offer after offer failure at various tick-distances in posthook after posting an offer at MIDDLE_LOG_PRICE";
  }
}
