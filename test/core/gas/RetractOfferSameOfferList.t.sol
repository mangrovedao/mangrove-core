// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_TICK} from "./GasTestBase.t.sol";
import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE} from "mgv_lib/TickLib.sol";

int constant LOW_TICK = MIDDLE_TICK - 2 * LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE;

contract PosthookSuccessRetractOfferSameList_WithOtherOfferGasTest is TickBoundariesGasTest, GasTestBase {
  uint internal offerId2;

  function setUp() public virtual override {
    super.setUp();
    this.newOfferOnAllTestTicks();
    _offerId = mgv.newOfferByTick($(base), $(quote), MIDDLE_TICK, 1 ether, 1_000_000, 0);
    tickOfferIds[MIDDLE_TICK] = _offerId;
    // Offer to take at very low tick
    mgv.newOfferByTick($(base), $(quote), LOW_TICK, 2 ** 96 - 1, 1_000_000, 0);
    offerId2 = mgv.newOfferByTick($(base), $(quote), LOW_TICK, 2 * 96 - 1, 1_000_000, 0);
    description =
      "Retracting an offer in posthook for now empty offer list but where new offer has varying closeness to taken offer";
  }

  function makerPosthook(MgvLib.SingleOrder calldata, MgvLib.OrderResult calldata) public virtual override {
    (AbstractMangrove mgv,, address base, address quote,) = getStored();
    uint offerId = tickOfferIds[tick];
    _gas();
    mgv.retractOffer(base, quote, offerId, true);
    gas_();
  }

  function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint, int) internal override {
    vm.prank($(taker));
    mgv.marketOrderByTick(base, quote, LOW_TICK, 1, true);
  }
}

contract PosthookSuccessRetractOfferSameList_WithPriorRetractOfferAndOtherOffersGasTest is
  PosthookSuccessRetractOfferSameList_WithOtherOfferGasTest
{
  function setUp() public virtual override {
    super.setUp();
    description =
      "Retracting a second offer at various tick-distances in posthook after retracting an offer at MIDDLE_TICK";
  }

  function makerPosthook(MgvLib.SingleOrder calldata sor, MgvLib.OrderResult calldata result) public virtual override {
    (AbstractMangrove mgv,, address base, address quote,) = getStored();
    // Retract near taken - the measured one is at various tick-distances.
    mgv.retractOffer(base, quote, offerId2, true);
    super.makerPosthook(sor, result);
  }
}
