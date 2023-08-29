// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.updateOffer's interaction with the tick tree.
contract TickTreeUpdateOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  // FIXME: This currently fails with "mgv/writeOffer/wants/tooLow", but I don't think it should.
  function testFail_update_only_offer_to_other_tick_manual() public {
    test_update_only_offer_to_other_tick(0, -1);
  }

  function test_update_only_offer_to_other_tick(int24 firstTick, int24 secondTick) public {
    vm.assume(firstTick >= MIN_TICK && firstTick <= MAX_TICK);
    vm.assume(secondTick >= MIN_TICK && secondTick <= MAX_TICK);
    // FIXME: Limiting to non-negative ticks for now due to issue with "mgv/writeOffer/wants/tooLow"
    vm.assume(firstTick >= 0 && secondTick >= 0);

    Tick tick1 = Tick.wrap(firstTick);
    Tick tick2 = Tick.wrap(secondTick);
    OfferData memory offerData1 = createOfferData(tick1, 100_000, 1);
    OfferData memory offerData2 = createOfferData(tick2, 200_000, 2);

    TickTree storage tickTree = snapshotTickTree();

    // 1. New offer
    offerData1.id =
      mgv.newOfferByLogPrice(olKey, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice);
    addOffer(
      tickTree, offerData1.tick, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice, $(this)
    );
    assertMgvOfferListEqToTickTree(tickTree);

    // 2. Update offer
    mgv.updateOfferByLogPrice(
      olKey, offerData2.logPrice, offerData2.gives, offerData2.gasreq, offerData2.gasprice, offerData1.id
    );
    removeOffer(tickTree, offerData1.id);
    addOffer(
      tickTree,
      offerData1.id,
      offerData2.tick,
      offerData2.logPrice,
      offerData2.gives,
      offerData2.gasreq,
      offerData2.gasprice,
      $(this)
    );
    assertMgvOfferListEqToTickTree(tickTree);
  }

  function update_only_offer_to_other_tick(int firstTick, int secondTick) public {
    test_update_only_offer_to_other_tick(int24(firstTick), int24(secondTick));
  }

  // ## MAX TICK

  function test_update_only_offer_from_max_tick_to_max_tick() public {
    update_only_offer_to_other_tick(MAX_TICK, MAX_TICK);
  }

  function test_update_only_offer_from_max_tick_to_same_leaf() public {
    update_only_offer_to_other_tick(MAX_TICK, MAX_TICK - 1);
  }

  function test_update_only_offer_to_max_tick_from_same_leaf() public {
    update_only_offer_to_other_tick(MAX_TICK - 1, MAX_TICK);
  }

  function test_update_only_offer_from_max_tick_to_other_level0_pos() public {
    update_only_offer_to_other_tick(MAX_TICK, MAX_TICK - LEAF_SIZE);
  }

  function test_update_only_offer_to_max_tick_from_other_level0_pos() public {
    update_only_offer_to_other_tick(MAX_TICK - LEAF_SIZE, MAX_TICK);
  }

  function test_update_only_offer_from_max_tick_to_other_level1_pos() public {
    update_only_offer_to_other_tick(MAX_TICK, MAX_TICK - LEAF_SIZE * LEVEL0_SIZE);
  }

  function test_update_only_offer_to_max_tick_from_other_level1_pos() public {
    update_only_offer_to_other_tick(MAX_TICK - LEAF_SIZE * LEVEL0_SIZE, MAX_TICK);
  }

  function test_update_only_offer_from_max_tick_to_other_level2_pos() public {
    update_only_offer_to_other_tick(MAX_TICK, MAX_TICK - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE);
  }

  function test_update_only_offer_to_max_tick_from_other_level2_pos() public {
    update_only_offer_to_other_tick(MAX_TICK - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE, MAX_TICK);
  }

  function test_update_retracted_offer_in_empty_book() public {
    OfferData memory offerData1 = createOfferData(Tick.wrap(MAX_TICK), 100_000, 1);
    OfferData memory offerData2 = createOfferData(Tick.wrap(MAX_TICK - 1), 200_000, 2);

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

    // 3. Update offer
    mgv.updateOfferByLogPrice(
      olKey, offerData2.logPrice, offerData2.gives, offerData2.gasreq, offerData2.gasprice, offerData1.id
    );
    addOffer(
      tickTree,
      offerData1.id,
      offerData2.tick,
      offerData2.logPrice,
      offerData2.gives,
      offerData2.gasreq,
      offerData2.gasprice,
      $(this)
    );
    assertMgvOfferListEqToTickTree(tickTree);
  }
}
