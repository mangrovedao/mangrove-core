// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_TICK, LEVEL1_HIGHER_TICK} from "./GasTestBase.t.sol";
import {AbstractMangrove, TestTaker} from "mgv_test/lib/MangroveTest.sol";
import {TickBoundariesGasTest} from "./TickBoundariesGasTest.t.sol";
import {OLKey} from "mgv_src/MgvLib.sol";

contract ExternalUpdateOfferOtherOfferList_DeadDeprovisioned is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    mgv.retractOffer(olKey, _offerId, true);
    description = "Update dead deprovisioned offer";
  }

  function impl(AbstractMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByLogPrice(_olKey, LEVEL1_HIGHER_TICK, 0.1 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_DeadProvisioned is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    mgv.retractOffer(olKey, _offerId, false);
    description = "Update dead provisioned offer";
  }

  function impl(AbstractMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByLogPrice(_olKey, LEVEL1_HIGHER_TICK, 0.1 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_Gasreq is GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByLogPrice(olKey, MIDDLE_TICK, 1 ether, 100_000, 0);
    description = "Update live offer with different gasreq values.";
  }

  function test_live_far_away_same_gasreq() public {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByLogPrice(_olKey, LEVEL1_HIGHER_TICK, 0.1 ether, 100_000, 0, offerId);
    gas_();
    description = string.concat(description, " - Case: same gasreq");
    printDescription();
  }

  function test_live_far_away_higher_gasreq() public {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByLogPrice(_olKey, LEVEL1_HIGHER_TICK, 0.1 ether, 1_000_000, 0, offerId);
    gas_();
    description = string.concat(description, " - Case: higher gasreq");
    printDescription();
  }

  function test_live_far_away_lower_gasreq() public {
    (AbstractMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByLogPrice(_olKey, LEVEL1_HIGHER_TICK, 0.1 ether, 10_000, 0, offerId);
    gas_();
    description = string.concat(description, " - Case: lower gasreq");
    printDescription();
  }
}
