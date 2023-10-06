// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {SingleGasTestBase, GasTestBase, MIDDLE_BIN, LEVEL2_HIGHER_BIN} from "@mgv/test/lib/gas/GasTestBase.t.sol";
import {IMangrove, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import {TickTreeBoundariesGasTest} from "./TickTreeBoundariesGasTest.t.sol";
import "@mgv/src/core/MgvLib.sol";

contract ExternalUpdateOfferOtherOfferList_DeadDeprovisioned is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    mgv.retractOffer(olKey, _offerId, true);
    description = "Update dead deprovisioned offer";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByTick(_olKey, olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_DeadProvisioned is SingleGasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    mgv.retractOffer(olKey, _offerId, false);
    description = "Update dead provisioned offer";
  }

  function impl(IMangrove mgv, TestTaker, OLKey memory _olKey, uint offerId) internal virtual override {
    _gas();
    mgv.updateOfferByTick(_olKey, olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 100_000, 0, offerId);
    gas_();
  }
}

contract ExternalUpdateOfferOtherOfferList_Gasreq is GasTestBase {
  function setUp() public virtual override {
    super.setUp();
    _offerId = mgv.newOfferByTick(olKey, olKey.tick(MIDDLE_BIN), 0.00001 ether, 100_000, 0);
    description = "Update live offer with different gasreq values.";
  }

  function test_live_far_away_same_gasreq() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByTick(_olKey, olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 100_000, 0, offerId);
    gas_();
    printDescription(" - Case: same gasreq");
  }

  function test_live_far_away_higher_gasreq() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByTick(_olKey, olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 1_000_000, 0, offerId);
    gas_();
    printDescription(" - Case: higher gasreq");
  }

  function test_live_far_away_lower_gasreq() public {
    (IMangrove mgv,, OLKey memory _olKey, uint offerId) = getStored();
    _gas();
    mgv.updateOfferByTick(_olKey, olKey.tick(LEVEL2_HIGHER_BIN), 0.00001 ether, 10_000, 0, offerId);
    gas_();
    printDescription(" - Case: lower gasreq");
  }
}
