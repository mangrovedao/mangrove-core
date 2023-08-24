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
              // console.log("level2Pos: %s, level1Pos: %s, level0Pos: %s", level2Pos, level1Pos, level0Pos);
              // console.log("  leafPos: %s, offerId: %s", leafPos, offerId);
              MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
              assertEq(offer.tick(olKey.tickScale), tick, "offer's tick does not match location in tick tree");
              assertEq(offer.prev(), prev, "offer.prev does point to previous offer in tick list");
              prev = offerId;
              offerId = offer.next();
            } while (offerId != 0);
            assertEq(leaf.lastOfIndex(leafPos), prev, "last offer in tick does not match last offer in tick list");
          }
        }
      }
    }
  }

  // Checks that the given offer has been correctly added to `branchBefore`
  function assertOfferAddedToBranch(TickTreeBranch memory branchBefore, uint offerId) internal {
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    Tick tick = offer.tick(olKey.tickScale);

    // Check that the offer is added correctly to the tick list
    uint tickFirstBefore = branchBefore.leaf.firstOfIndex(tick.posInLeaf());
    uint tickLastBefore = branchBefore.leaf.firstOfIndex(tick.posInLeaf());
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
      assertEq(leaf.firstOfIndex(i), branchBefore.leaf.firstOfIndex(i), "other leaf positions should be unchanged");
      assertEq(leaf.lastOfIndex(i), branchBefore.leaf.lastOfIndex(i), "other leaf positions should be unchanged");
    }

    // Check that the levels are updated correctly
    assertEq(
      mgv.level0(olKey, tick.level0Index()),
      setBit(branchBefore.level0, tick.posInLevel0()),
      "level0 should have bit set for tick"
    );
    Field level1 = mgv.level1(olKey, tick.level1Index());
    assertEq(level1, setBit(level1, tick.posInLevel1()), "level1 should have bit set for tick");
    Field level2 = mgv.level2(olKey);
    assertEq(level2, setBit(level2, tick.posInLevel2()), "level2 should have bit set for tick");
  }

  struct TickTreeBranch {
    Field level2;
    Field level1;
    Field level0;
    Leaf leaf;
    uint posInLeaf;
  }

  function snapshotTickTreeBranch(Tick tick) internal returns (TickTreeBranch memory) {
    TickTreeBranch memory branch;
    branch.level2 = mgv.level2(olKey);
    branch.level1 = mgv.level1(olKey, tick.level1Index());
    branch.level0 = mgv.level0(olKey, tick.level0Index());
    branch.leaf = mgv.leafs(olKey, tick.leafIndex());
    branch.posInLeaf = reader.local(olKey).tickPosInLeaf();
    return branch;
  }

  // TODO:
  // - Extract assertion groups and give them logical names
  // - Extract state before insertion and use in assertions for things that should not change
  // - Consider naming expected values for later extraction to individual asserts
  function test_new_offer_in_empty_tree_at_max_tick() public {
    Tick tick = Tick.wrap(MAX_TICK);
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    uint gasreq = 100_000;
    uint gives = reader.minVolume(olKey, gasreq);

    // Tick assumptions
    assertTickAssumptions({
      tick: tick,
      posInLeaf: MAX_LEAF_POSITION,
      leafIndex: MAX_LEAF_INDEX,
      posInLevel0: MAX_LEVEL0_POSITION,
      level0Index: MAX_LEVEL0_INDEX,
      posInLevel1: MAX_LEVEL1_POSITION,
      level1Index: MAX_LEVEL1_INDEX,
      posInLevel2: MAX_LEVEL2_POSITION
    });

    TickTreeBranch memory branchBefore = snapshotTickTreeBranch(tick);
    // TODO:
    // Assert that the tick tree is empty. Maybe do this in a separate test, verifying that setup acts as expected

    // logTickTreeBranch(reader, olKey);
    assertTickTreeIsConsistent();
    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, gasreq, 0);
    // logTickTreeBranch(reader, olKey);
    assertTickTreeIsConsistent();
    // TODO:
    // how to check that other leafs and levels are empty?

    MgvStructs.OfferPacked offer = mgv.offers(olKey, ofr);
    assertEq(offer.logPrice(), logPrice, "offer's logPrice does not match insertion logPrice");
    assertEq(offer.tick(olKey.tickScale), tick, "offer's logPrice does not match insertion logPrice");

    assertOfferAddedToBranch(branchBefore, ofr);

    // FIXME: Take the asserts re. the best tick branch (incl. optimizations) and move to assert function
    // assertNewTickBranchIsBest(branchBefore, ofr);

    // Mangrove does not write level0 and level1 to the mappings if they are on the branch for the best tick.
    Field level0 = mgv.level0(olKey, tick.level0Index());
    Field level0FromMapping = mgv.level0FromMapping(olKey, tick.level0Index());
    Field level0FromLocal = reader.local(olKey).level0();
    assertEq(
      level0, level0FromLocal, "level0 returned from level0() does not match level0 in local though tick is best"
    ); // FIXME: Only when best
    assertEq(
      level0FromMapping,
      branchBefore.level0,
      "level0 in mapping should not be changed when inserting in best tick branch"
    );
    // FIXME: It's a bit weird that we consider level0 (Fields) the left-most bit as corresponding to the last leaf in that level. Normally, I'd expect a left-to-right reading of the tree
    // FIXME: The Excalidraw drawing says ticks go right (cheap) to left (expensive), so I guess it makes sense. But

    Field level1 = mgv.level1(olKey, tick.level1Index());
    Field level1FromMapping = mgv.level1FromMapping(olKey, tick.level1Index());
    Field level1FromLocal = reader.local(olKey).level1();
    assertEq(
      level1, level1FromLocal, "level1 returned from level1() does not match level1 in local though tick is best"
    ); // FIXME: Only when best
    assertEq(
      level1FromMapping, FieldLib.EMPTY, "level1 in mapping should not be changed when inserting in best tick branch"
    );
    assertEq(level1.firstOnePosition(), MAX_LEVEL1_POSITION, "first position in level1 does not match expected value");
    assertEq(level1.lastOnePosition(), MAX_LEVEL1_POSITION, "last position in level1 does not match expected value");

    Field level2 = mgv.level2(olKey);
    assertEq(level2.firstOnePosition(), MAX_LEVEL2_POSITION, "first position in level2 does not match expected value");
    assertEq(level2.lastOnePosition(), MAX_LEVEL2_POSITION, "last position in level2 does not match expected value");

    // FIXME: Comment in again later when stack issue is solved
    // // Assert that local looks as expected
    // MgvStructs.LocalPacked local = reader.local(olKey);
    // assertEq(local.last(), ofr); // FIXME: Only when inserting new offer
    // assertEq(local.tickPosInLeaf(), tick.posInLeaf(), "local.tickPosInLeaf does not match posInLeaf for best offer"); // FIXME: Only when best
    // assertEq(local.level0(), level0, "local.level0 does not match level0 for best tick"); // FIXME: Only when best
    // assertEq(local.level1(), level1, "local.level1 does not match level1 for best tick"); // FIXME: Only when best

    // // Assert that the offer is on the best tick
    // assertEq(mgv.best(olKey), ofr, "ofr should be best"); // FIXME: Only when best
  }
}
