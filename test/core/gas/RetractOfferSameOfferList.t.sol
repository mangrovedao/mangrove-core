// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_LOG_PRICE} from "./GasTestBase.t.sol";
import {IMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";
import {MgvLib, OLKey} from "mgv_src/MgvLib.sol";
import {LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE} from "mgv_lib/TickLib.sol";
import "mgv_lib/Debug.sol";

int constant LOW_LOG_PRICE = MIDDLE_LOG_PRICE - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE * 2 * LEVEL2_SIZE / 3;

contract PosthookSuccessRetractOfferSameList_WithOtherOfferGasTest is TickBoundariesGasTest, GasTestBase {
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestPrices();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_LOG_PRICE, 1000 ether, 1_000_000, 0);
    logPriceOfferIds[MIDDLE_LOG_PRICE] = _offerId;
    // Offer to take at very low price
    mgv.newOfferByLogPrice(olKey, LOW_LOG_PRICE, 2 ** 96 - 1, 1_000_000, 0);
    offerId2 = mgv.newOfferByLogPrice(olKey, LOW_LOG_PRICE, 2 ** 96 - 1, 1_000_000, 0);
    description =
      "Retracting an offer in posthook for now empty offer list but where new offer has varying closeness to taken offer";
  }

  function makerPosthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) public virtual override {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    uint offerId = logPriceOfferIds[logPrice];
    _gas();
    mgv.retractOffer(_olKey, offerId, true);
    gas_();
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint, int) internal override {
    vm.prank($(taker));
    mgv.marketOrderByLogPrice(_olKey, LOW_LOG_PRICE, 1, true);
  }
}

contract PosthookSuccessRetractOfferSameList_WithPriorRetractOfferAndOtherOffersGasTest is
  PosthookSuccessRetractOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description =
      "Retracting a second offer at various tick-distances in posthook after retracting an offer at MIDDLE_LOG_PRICE";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata result) public virtual override {
    (IMangrove mgv,, OLKey memory _olKey,) = getStored();
    // Retract near taken - the measured one is at various tick-distances.
    mgv.retractOffer(_olKey, offerId2, true);
    super.makerPosthook(sor, result);
  }
}
