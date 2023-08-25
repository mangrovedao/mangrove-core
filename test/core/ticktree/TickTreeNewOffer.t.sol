// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {AbstractMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {
  IERC20,
  MgvLib,
  HasMgvEvents,
  IMaker,
  ITaker,
  IMgvMonitor,
  MgvStructs,
  Leaf,
  Field,
  Tick,
  LeafLib,
  LogPriceLib,
  FieldLib,
  TickLib,
  MIN_TICK,
  MAX_TICK,
  LEAF_SIZE_BITS,
  LEVEL0_SIZE_BITS,
  LEVEL1_SIZE_BITS,
  LEAF_SIZE,
  LEVEL0_SIZE,
  LEVEL1_SIZE,
  LEVEL2_SIZE,
  NUM_LEVEL1,
  NUM_LEVEL0,
  NUM_LEAFS,
  NUM_TICKS,
  MIN_LEAF_INDEX,
  MAX_LEAF_INDEX,
  MIN_LEVEL0_INDEX,
  MAX_LEVEL0_INDEX,
  MIN_LEVEL1_INDEX,
  MAX_LEVEL1_INDEX,
  MAX_LEAF_POSITION,
  MAX_LEVEL0_POSITION,
  MAX_LEVEL1_POSITION,
  MAX_LEVEL2_POSITION
} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// import {TickLib, Tick, MIN_TICK, MAX_TICK, LEAF_SIZE, LEVEL0_SIZE, LEVEL1_SIZE, LEVEL2_SIZE, NUM_LEVEL1, NUM_LEVEL0, NUM_LEAFS, NUM_TICKS} from "mgv_lib/TickLib.sol";

// FIXME: Extract common constants and utility methods to a test base class
contract TickTreeNewOfferTest is MangroveTest {
  function test_constants_are_at_expected_locations() public {
    // FIXME: Assert that the constants have the expected locations at various levels
    // This also serves as a reading guide to the constants.
    // MIN_TICK
    Tick tick = Tick.wrap(MIN_TICK);
    // FIXME: This failed because MIN_TICK was 1 bigger than the smallest number representable by int20. I've changed MIN_TICK the min value of int20.
    assertEq(tick.posInLeaf(), 0);
    assertEq(tick.posInLevel0(), 0);
    assertEq(tick.posInLevel1(), 0);
    assertEq(tick.posInLevel2(), 0);

    // MAX_TICK
    tick = Tick.wrap(MAX_TICK);
    assertEq(tick.posInLeaf(), uint(LEAF_SIZE - 1));
    assertEq(tick.posInLevel0(), uint(LEVEL0_SIZE - 1));
    assertEq(tick.posInLevel1(), uint(LEVEL1_SIZE - 1));
    assertEq(tick.posInLevel2(), uint(LEVEL2_SIZE - 1));
  }

  //FIXME: Price calculations currently don't work for MIN_TICK and it is therefore impossible to post offers at MIN_TICK
  function testFail_new_offer_in_empty_tree_at_min_tick() public {
    Tick tick = Tick.wrap(MIN_TICK);
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    uint gasreq = 100_000;
    uint gives = reader.minVolume(olKey, gasreq);

    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, gasreq, 0);
    assertEq(mgv.best(olKey), ofr);
    //FIXME: Complete this test
  }

  function assertTickAssumptions(
    Tick tick,
    uint posInLeaf,
    int leafIndex,
    uint posInLevel0,
    int level0Index,
    uint posInLevel1,
    int level1Index,
    uint posInLevel2
  ) internal {
    assertEq(tick.posInLeaf(), posInLeaf, "tick's posInLeaf does not match expected value");
    assertEq(tick.leafIndex(), leafIndex, "tick's leafIndex does not match expected value");
    assertEq(tick.posInLevel0(), posInLevel0, "tick's posInLevel0 does not match expected value");
    assertEq(tick.level0Index(), level0Index, "tick's level0Index does not match expected value");
    assertEq(tick.posInLevel1(), posInLevel1, "tick's posInLevel1 does not match expected value");
    assertEq(tick.level1Index(), level1Index, "tick's level1Index does not match expected value");
    assertEq(tick.posInLevel2(), posInLevel2, "tick's posInLevel2 does not match expected value");
  }

  function setBit(Field field, uint pos) internal pure returns (Field) {
    return Field.wrap(Field.unwrap(field) | (1 << pos));
  }

  function unsetBit(Field field, uint pos) internal pure returns (Field) {
    return Field.wrap(Field.unwrap(field) & (0 << pos));
  }

  function isBitSet(Field field, uint pos) internal pure returns (bool) {
    return (Field.unwrap(field) & (1 << pos)) > 0;
  }

  function level1IndexFromLevel2Pos(uint pos) internal pure returns (int) {
    return int(pos) - LEVEL2_SIZE / 2;
  }

  function level0IndexFromLevel1IndexAndPos(int level1Index, uint pos) internal pure returns (int) {
    return (level1Index << LEVEL1_SIZE_BITS) | int(pos);
  }

  function leafIndexFromLevel0IndexAndPos(int level0Index, uint pos) internal pure returns (int) {
    return (level0Index << LEVEL0_SIZE_BITS) | int(pos);
  }

  function tickFromLeafIndexAndPos(int leafIndex, uint pos) internal pure returns (Tick) {
    return Tick.wrap((leafIndex << LEAF_SIZE_BITS) | int(pos));
  }

  // Traverses the tick tree and asserts that it is consistent
  function assertTickTreeIsConsistent() internal {
    Field level2 = mgv.level2(olKey);
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = mgv.level1(olKey, level1Index);
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = mgv.level0(olKey, level0Index);
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = mgv.leafs(olKey, leafIndex);
          assertTrue(!leaf.eq(LeafLib.EMPTY), "leaf should not be empty when bit is set in higher levels");
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              continue;
            }
            uint prev = 0;
            do {
              console.log("level2Pos: %s, level1Pos: %s, level0Pos: %s", level2Pos, level1Pos, level0Pos);
              console.log("  leafPos: %s, offerId: %s", leafPos, offerId);
              MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
              assertEq(offer.tick(olKey.tickScale), tick, "offer's tick does not match location in tick tree");
              assertEq(offer.prev(), prev, "offer.prev does point to previous offer in tick list");
              assertTrue(offer.isLive(), "offer in tick tree should be live");
              prev = offerId;
              offerId = offer.next();
            } while (offerId != 0);
            assertEq(leaf.lastOfIndex(leafPos), prev, "last offer in tick does not match last offer in tick list");
          }
        }
      }
    }
  }

  // Checks that the given offer has been correctly added to `offerBranchBefore`
  function assertOfferAddedCorrectlyToBranch(
    TickTreeBranch memory offerBranchBefore,
    uint offerId,
    Tick tick,
    int logPrice
  ) internal {
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    assertEq(offer.logPrice(), logPrice, "offer's logPrice does not match insertion logPrice");
    assertEq(offer.tick(olKey.tickScale), tick, "offer's logPrice does not match insertion logPrice");

    // Check that the offer is added correctly to the tick list
    uint tickFirstBefore = offerBranchBefore.leaf.firstOfIndex(tick.posInLeaf());
    uint tickLastBefore = offerBranchBefore.leaf.firstOfIndex(tick.posInLeaf());
    assertEq(offer.prev(), tickLastBefore, "offer.prev should be old last in tick list");
    assertEq(offer.next(), 0, "offer.next should be empty");
    if (tickLastBefore != 0) {
      MgvStructs.OfferPacked prevOffer = mgv.offers(olKey, tickLastBefore);
      assertEq(prevOffer.next(), offerId, "prevOffer.next should be new offer");
    }

    // Check that the leaf is updated correctly
    Leaf leaf = mgv.leafs(olKey, tick.leafIndex());
    assertEq(
      leaf.firstOfIndex(tick.posInLeaf()),
      tickFirstBefore == 0 ? offerId : tickFirstBefore,
      "offer should only be first in the tick list if it was empty before"
    );
    assertEq(leaf.lastOfIndex(tick.posInLeaf()), offerId, "offer should be last in the tick list");
    // Rest of leaf should be unchanged
    for (uint i = 0; i < uint(LEAF_SIZE); ++i) {
      if (i == tick.posInLeaf()) {
        continue;
      }
      assertEq(leaf.firstOfIndex(i), offerBranchBefore.leaf.firstOfIndex(i), "other leaf positions should be unchanged");
      assertEq(leaf.lastOfIndex(i), offerBranchBefore.leaf.lastOfIndex(i), "other leaf positions should be unchanged");
    }

    // Check that the levels are updated correctly
    assertEq(
      mgv.level0(olKey, tick.level0Index()),
      setBit(offerBranchBefore.level0, tick.posInLevel0()),
      "level0 should have bit set for tick"
    );
    Field level1 = mgv.level1(olKey, tick.level1Index());
    assertEq(level1, setBit(level1, tick.posInLevel1()), "level1 should have bit set for tick");
    Field level2 = mgv.level2(olKey);
    assertEq(level2, setBit(level2, tick.posInLevel2()), "level2 should have bit set for tick");
  }

  // Checks that the best tick branch has been updated correctly to the new best offer
  function assertBestBranchUpdatedCorrectly(
    TickTreeBranch memory bestBranchBefore,
    TickTreeBranch memory offerBranchBefore,
    uint bestOfferId
  ) internal {
    MgvStructs.OfferPacked bestOffer = mgv.offers(olKey, bestOfferId);
    Tick tick = bestOffer.tick(olKey.tickScale);

    // Check that local contains the offer's tick branch and that Mangrove reports it correctly
    {
      MgvStructs.LocalPacked local = reader.local(olKey);
      assertEq(
        local.level2(),
        setBit(offerBranchBefore.level2, tick.posInLevel2()),
        "local.level2 should have bit set for best offer's tick branch"
      );
      assertEq(
        mgv.level2(olKey),
        setBit(offerBranchBefore.level2, tick.posInLevel2()),
        "mgv.level2 should have bit set for best offer's tick branch"
      );
      assertEq(
        local.level1(),
        setBit(offerBranchBefore.level1, tick.posInLevel1()),
        "local.level1 should have bit set for best offer's tick branch"
      );
      assertEq(
        mgv.level1(olKey, tick.level1Index()),
        setBit(offerBranchBefore.level1, tick.posInLevel1()),
        "mgv.level1 should have bit set for best offer's tick branch"
      );
      assertEq(
        local.level0(),
        setBit(offerBranchBefore.level0, tick.posInLevel0()),
        "local.level0 should have bit set for best offer's tick branch"
      );
      assertEq(
        mgv.level0(olKey, tick.level0Index()),
        setBit(offerBranchBefore.level0, tick.posInLevel0()),
        "mgv.level0 should have bit set for best offer's tick branch"
      );
      assertEq(local.tickPosInLeaf(), tick.posInLeaf(), "local.tickPosInLeaf should be best offer's position in leaf");
      assertEq(mgv.best(olKey), bestOfferId, "offerId should be best");
    }

    // Check that any part of the previous best branch that is no longer part of the best branch is unchanged and has been written to the mappings
    // Thes mapping checks are needed due to the optimizations that avoid writing to the mappings when the tick branch is best

    // Also checking the do-not-update-mappings-for-levels-on-best-branch optimization: Any part of the new best tick branch that was not best before should not be written to the mappings
    // This isn't strictly necessary to check, but would be good to get a warning if it isn't working as expected. We can remove those checks if needed.
    bool level2PosChanged = bestBranchBefore.tick.posInLevel2() != tick.posInLevel2();
    bool level1PosChanged = level2PosChanged || bestBranchBefore.tick.posInLevel1() != tick.posInLevel1();
    bool level0PosChanged = level1PosChanged || bestBranchBefore.tick.posInLevel0() != tick.posInLevel0();
    bool posInLeafChanged = level0PosChanged || bestBranchBefore.tick.posInLeaf() != tick.posInLeaf();

    if (level2PosChanged) {
      assertEq(
        mgv.level1(olKey, bestBranchBefore.tick.level1Index()),
        bestBranchBefore.level1,
        "mgv.level1() for previous best branch should be unchanged"
      );
      assertEq(
        mgv.level1FromMapping(olKey, bestBranchBefore.tick.level1Index()),
        bestBranchBefore.level1,
        "level1 mapping for previous best branch should be updated"
      );

      assertEq(
        mgv.level1FromMapping(olKey, tick.level1Index()),
        offerBranchBefore.level1,
        "mgv.level1 mapping for new best branch was updated needlessly"
      );
    }
    if (level1PosChanged) {
      assertEq(
        mgv.level0(olKey, bestBranchBefore.tick.level0Index()),
        bestBranchBefore.level0,
        "mgv.level0() for previous best branch should be unchanged"
      );
      assertEq(
        mgv.level0FromMapping(olKey, bestBranchBefore.tick.level0Index()),
        bestBranchBefore.level0,
        "level0 mapping for previous best branch should be updated"
      );

      assertEq(
        mgv.level0FromMapping(olKey, tick.level0Index()),
        offerBranchBefore.level0,
        "mgv.level0 mapping for new best branch was updated needlessly"
      );
    }
    if (level0PosChanged) {
      assertEq(
        mgv.leafs(olKey, bestBranchBefore.tick.leafIndex()),
        bestBranchBefore.leaf,
        "mgv.leafs() for previous best branch should be unchanged"
      );
    }
    if (posInLeafChanged) {
      assertEq(
        mgv.leafs(olKey, bestBranchBefore.tick.leafIndex()).firstOfIndex(bestBranchBefore.tick.posInLeaf()),
        bestBranchBefore.leaf.firstOfIndex(bestBranchBefore.tick.posInLeaf()),
        "first in posInLeaf for previous best branch should be unchanged"
      );
      assertEq(
        mgv.leafs(olKey, bestBranchBefore.tick.leafIndex()).lastOfIndex(bestBranchBefore.tick.posInLeaf()),
        bestBranchBefore.leaf.lastOfIndex(bestBranchBefore.tick.posInLeaf()),
        "last in posInLeaf for previous best branch should be unchanged"
      );
    }
  }

  function assertOfferRemovedCorrectlyFromBranch(TickTreeBranch memory offerBranchBefore, uint offerId, Tick tick)
    internal
  {
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    assertFalse(offer.isLive(), "should not be live after retract");

    // TODO:
    // - If the tick list is now empty, check that the branch is removed correctly from the levels
    // - If the tick list is not empty, check that the branch is still active
    uint offerIdBefore = offerBranchBefore.leaf.firstOfIndex(tick.posInLeaf());
    assertNotEq(offerIdBefore, 0, "tick list should not have been empty before offer was retracted");
    Leaf leaf = mgv.leafs(olKey, tick.leafIndex());
    uint offerIdInTickList = leaf.firstOfIndex(tick.posInLeaf());
    bool tickListIsEmpty = offerIdInTickList == 0;

    while (offerIdInTickList != 0) {
      assertNotEq(offerIdInTickList, offerId, "offer should have been removed from tick list");
      MgvStructs.OfferPacked offerInTickList = mgv.offers(olKey, offerIdInTickList);
      offerIdInTickList = offerInTickList.next();
    }

    if (tickListIsEmpty) {
      assertEq(leaf.lastOfIndex(tick.posInLeaf()), 0, "last in tick list should be empty");
      if (leaf.eq(LeafLib.EMPTY)) {
        Field level0 = mgv.level0(olKey, tick.level0Index());
        assertEq(level0, unsetBit(offerBranchBefore.level0, tick.posInLevel0()), "level0 pos should be unset for tick");
        if (level0.eq(FieldLib.EMPTY)) {
          Field level1 = mgv.level1(olKey, tick.level1Index());
          assertEq(
            level1, unsetBit(offerBranchBefore.level1, tick.posInLevel1()), "level1 pos should be unset for tick"
          );
          if (level1.eq(FieldLib.EMPTY)) {
            Field level2 = mgv.level2(olKey);
            assertEq(
              level2, unsetBit(offerBranchBefore.level2, tick.posInLevel2()), "level2 pos should be unset for tick"
            );
          }
        }
      }
    } else {
      assertTrue(
        isBitSet(mgv.level0(olKey, tick.level0Index()), tick.posInLevel0()), "level0 pos should be set for tick"
      );
      assertTrue(
        isBitSet(mgv.level1(olKey, tick.level1Index()), tick.posInLevel1()), "level1 pos should be set for tick"
      );
      assertTrue(isBitSet(mgv.level2(olKey), tick.posInLevel2()), "level2 pos should be set for tick");
    }

    // FIXME: If offer was best, check that the best branch is updated correctly
  }

  struct TickTreeBranch {
    Field level2;
    Field level1;
    Field level0;
    Leaf leaf;
    uint posInLeaf;
    Tick tick;
  }

  function snapshotTickTreeBranch(Tick tick) internal view returns (TickTreeBranch memory) {
    TickTreeBranch memory branch;
    branch.level2 = mgv.level2(olKey);
    branch.level1 = mgv.level1(olKey, tick.level1Index());
    branch.level0 = mgv.level0(olKey, tick.level0Index());
    branch.leaf = mgv.leafs(olKey, tick.leafIndex());
    branch.posInLeaf = reader.local(olKey).tickPosInLeaf();
    branch.tick = tick;
    return branch;
  }

  function snapshotBestTickTreeBranch() internal view returns (TickTreeBranch memory) {
    Tick tick = reader.local(olKey).tick();
    return snapshotTickTreeBranch(tick);
  }

  function test_new_offer_in_empty_tree_at_max_tick() public {
    Tick tick = Tick.wrap(MAX_TICK);
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    uint gasreq = 100_000;
    uint gives = reader.minVolume(olKey, gasreq);

    // Tick assumptions
    // FIXME: Is this still needed? Do we use the constants?
    // assertTickAssumptions({
    //   tick: tick,
    //   posInLeaf: MAX_LEAF_POSITION,
    //   leafIndex: MAX_LEAF_INDEX,
    //   posInLevel0: MAX_LEVEL0_POSITION,
    //   level0Index: MAX_LEVEL0_INDEX,
    //   posInLevel1: MAX_LEVEL1_POSITION,
    //   level1Index: MAX_LEVEL1_INDEX,
    //   posInLevel2: MAX_LEVEL2_POSITION
    // });

    TickTreeBranch memory offerBranchBefore = snapshotTickTreeBranch(tick);
    TickTreeBranch memory bestBranchBefore = snapshotBestTickTreeBranch();
    // TODO:
    // Assert that the tick tree is empty. Maybe do this in a separate test, verifying that setup acts as expected

    // logTickTreeBranch(reader, olKey);
    assertTickTreeIsConsistent();
    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, gasreq, 0);
    // logTickTreeBranch(reader, olKey);
    assertTickTreeIsConsistent();
    // TODO:
    // how to check that other leafs and levels are empty?

    // Lasse: Maybe these can be combined into one, clearer function
    assertOfferAddedCorrectlyToBranch(offerBranchBefore, ofr, tick, logPrice);
    assertBestBranchUpdatedCorrectly(bestBranchBefore, offerBranchBefore, ofr);
  }

  function test_retract_only_offer() public {
    Tick tick = Tick.wrap(MAX_TICK);
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    uint gasreq = 100_000;
    uint gives = reader.minVolume(olKey, gasreq);

    TickTreeBranch memory offerBranchBefore = snapshotTickTreeBranch(tick);
    TickTreeBranch memory bestBranchBefore = snapshotBestTickTreeBranch();

    assertTickTreeIsConsistent();
    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, gasreq, 0);
    assertTickTreeIsConsistent();

    assertOfferAddedCorrectlyToBranch(offerBranchBefore, ofr, tick, logPrice);
    assertBestBranchUpdatedCorrectly(bestBranchBefore, offerBranchBefore, ofr);

    offerBranchBefore = snapshotTickTreeBranch(tick);
    bestBranchBefore = snapshotBestTickTreeBranch();

    mgv.retractOffer(olKey, ofr, false);
    assertTickTreeIsConsistent();

    assertOfferRemovedCorrectlyFromBranch(offerBranchBefore, ofr, tick);
  }

  // Lasse: Can we add these assertions to existing tests? Eg by adding a wrapper to Mangrove and adding assertions to that
  //        Possibly via the IMangrove interface so we exercise it regularly
  // Lasse: Can we do fuzz/invariant testing with this? Could supplement the more structured tests
}
