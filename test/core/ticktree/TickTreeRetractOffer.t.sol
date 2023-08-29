// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.retractOffer's interaction with the tick tree.
contract TickTreeRetractOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  // # Retract offer tests

  function test_retract_only_offer() public {
    OfferData memory offerData1 = createOfferData(Tick.wrap(MAX_TICK), 100_000, 1);

    TickTree storage tickTree = snapshotTickTree();

    // 1. New offer
    offerData1.id =
      mgv.newOfferByLogPrice(olKey, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice);
    addOffer(
      tickTree, offerData1.tick, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice, $(this)
    );
    assertMgvOfferListEqToTickTree(tickTree);

    // 2. Retract offer
    mgv.retractOffer(olKey, offerData1.id, false);
    removeOffer(tickTree, offerData1.id);
    assertMgvOfferListEqToTickTree(tickTree);
  }
}
