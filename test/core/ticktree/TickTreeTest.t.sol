// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {AbstractMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Base class for test of Mangrove's tick tree data structure
//
// Provides a simple tick tree data structure and operations on it that can be used to simulate Mangrove's tick tree
// and then be compared to the actual tick tree.
//
// The test tick tree operations uses simpler (and less efficient) code to manipulate the tick tree, which should make
// it clearer what is going on and easier to convince yourself that the tick tree is manipulated correctly.
//
// In contrast, Mangrove's tick tree operations are optimized and interleaved with other code, which makes it harder to
// reason about.
//
// tl;dr: We use a simple tick tree operations to verify Mangrove's complex tick tree operations.
//
// Basic test flow:
// 1. Set up Mangrove's initial state, ie post offers at relevant ticks
// 2. Take a snapshot of Mangrove's tick tree using `snapshotTickTree` which returns a `TickTree` struct
// 3. Perform some operation on Mangrove (eg add or remove an offer)
// 4. Perform equivalent operation on the snapshot tick tree
// 5. Compare Mangrove's tick tree to the snapshot tick tree using `assertMgvOfferListEqToTickTree`
abstract contract TickTreeTest is MangroveTest {
  // # Offer utility functions

  struct OfferData {
    uint id;
    Tick tick;
    int logPrice;
    uint gives;
    uint gasreq;
    uint gasprice;
  }

  // Calculates gives that Mangrove will accept for a tick & gasreq
  function getAcceptableGivesForTick(Tick tick, uint gasreq) internal view returns (uint gives) {
    // First, try minVolume
    gives = reader.minVolume(olKey, gasreq);
    uint wants = LogPriceLib.inboundFromOutbound(LogPriceLib.fromTick(tick, olKey.tickScale), gives);
    if (wants > 0 && uint96(wants) == wants) {
      return gives;
    }
    // Else, try max
    gives = type(uint96).max;
  }

  function createOfferData(Tick tick, uint gasreq, uint gasprice) internal view returns (OfferData memory offerData) {
    offerData.id = 0;
    offerData.tick = tick;
    offerData.logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    offerData.gasreq = gasreq;
    offerData.gives = getAcceptableGivesForTick(tick, gasreq);
    offerData.gasprice = gasprice;
  }

  // # Mangrove tick tree asserts

  // Checks that the current Mangrove tick tree in olKey is consistent
  function assertMgvTickTreeIsConsistent() internal {
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

  // Checks that the current Mangrove tick tree in olKey is equal to the tick tree passed as argument
  function assertMgvOfferListEqToTickTree(TickTree storage tickTree) internal {
    Field level2 = mgv.level2(olKey);
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      assertEq(
        isBitSet(level2, level2Pos),
        isBitSet(tickTree.local.level2(), level2Pos),
        string.concat("level2 bit mismatch, pos: ", vm.toString(level2Pos))
      );
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = mgv.level1(olKey, level1Index);
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        assertEq(
          isBitSet(level1, level1Pos),
          isBitSet(tickTree.level1[level1Index], level1Pos),
          string.concat("level1 bit mismatch, pos: ", vm.toString(level1Pos))
        );
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = mgv.level0(olKey, level0Index);
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          assertEq(
            isBitSet(level0, level0Pos),
            isBitSet(tickTree.level0[level0Index], level0Pos),
            string.concat("level0 bit mismatch, pos: ", vm.toString(level0Pos))
          );
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = mgv.leafs(olKey, leafIndex);
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            {
              assertEq(
                leaf.firstOfIndex(leafPos),
                tickTree.leafs[leafIndex].firstOfIndex(leafPos),
                string.concat("leaf first mismatch, pos: ", vm.toString(leafPos))
              );
              assertEq(
                leaf.lastOfIndex(leafPos),
                tickTree.leafs[leafIndex].lastOfIndex(leafPos),
                string.concat("leaf last mismatch, pos: ", vm.toString(leafPos))
              );
            }
            uint offerId = leaf.firstOfIndex(leafPos);
            while (offerId != 0) {
              {
                MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
                MgvStructs.OfferPacked offerTickTree = tickTree.offers[offerId].offer;
                assertTrue(
                  offer.eq(offerTickTree),
                  string.concat("offer mismatch | MGV ", toString(offer), " | tick tree ", toString(offerTickTree))
                );
                offerId = offer.next();
              }
              {
                MgvStructs.OfferDetailPacked detail = mgv.offerDetails(olKey, offerId);
                assertTrue(
                  detail.eq(tickTree.offers[offerId].detail),
                  string.concat("offer detail mismatch, offer detail:", toString(detail))
                );
              }
            }
          }
        }
      }
    }
  }

  // # Test tick tree data structure and operations

  struct Offer {
    MgvStructs.OfferPacked offer;
    MgvStructs.OfferDetailPacked detail;
  }

  struct TickTree {
    MgvStructs.LocalPacked local;
    mapping(uint => Offer) offers;
    mapping(int => Leaf) leafs;
    mapping(int => Field) level0;
    mapping(int => Field) level1;
  }

  // Tick trees are in storage because they contain mappings
  mapping(uint => TickTree) tickTrees;
  uint tickTreeCount;

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

  // Creates a snapshot of the tick tree
  function snapshotTickTree() internal returns (TickTree storage) {
    TickTree storage tickTree = tickTrees[tickTreeCount++];
    tickTree.local = reader.local(olKey);
    Field level2 = mgv.level2(olKey);
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = mgv.level1(olKey, level1Index);
      tickTree.level1[level1Index] = level1;
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = mgv.level0(olKey, level0Index);
        tickTree.level0[level0Index] = level0;
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = mgv.leafs(olKey, leafIndex);
          tickTree.leafs[leafIndex] = leaf;
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            uint offerId = leaf.firstOfIndex(leafPos);
            while (offerId != 0) {
              tickTree.offers[offerId].offer = mgv.offers(olKey, offerId);
              tickTree.offers[offerId].detail = mgv.offerDetails(olKey, offerId);
              offerId = tickTree.offers[offerId].offer.next();
            }
          }
        }
      }
    }

    return tickTree;
  }

  function logTickTree(TickTree storage tickTree) internal view {
    Field level2 = tickTree.local.level2();
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }
      console.log("l2: %s", level2Pos);

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = tickTree.level1[level1Index];
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }
        console.log("  l1: %s", level1Pos);

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = tickTree.level0[level0Index];
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }
          console.log("    l0: %s", level0Pos);

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = tickTree.leafs[leafIndex];
          console.log("      leaf: %s", leafIndex);
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              continue;
            }
            console.log("        tick: %s", toString(tick));
            do {
              console.log("          offer: %s", offerId);
              offerId = tickTree.offers[offerId].offer.next();
            } while (offerId != 0);
          }
        }
      }
    }
  }

  function best(TickTree storage tickTree) internal view returns (uint bestOfferId, Tick bestTick) {
    Field level2 = tickTree.local.level2();
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = tickTree.level1[level1Index];
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = tickTree.level0[level0Index];
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = tickTree.leafs[leafIndex];
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              continue;
            }
            return (offerId, tick);
          }
        }
      }
    }
  }

  function updateLocalWithBestBranch(TickTree storage tickTree) internal {
    (, Tick tick) = best(tickTree);
    tickTree.local = tickTree.local.level1(tickTree.level1[tick.level1Index()]);
    tickTree.local = tickTree.local.level0(tickTree.level0[tick.level0Index()]);
    tickTree.local = tickTree.local.tickPosInLeaf(tick.posInLeaf());
  }

  function addOffer(
    TickTree storage tickTree,
    Tick tick,
    int logPrice,
    uint gives,
    uint gasreq,
    uint gasprice,
    address maker
  ) internal {
    uint offerId = 1 + tickTree.local.last();
    tickTree.local = tickTree.local.last(offerId);

    addOffer(tickTree, offerId, tick, logPrice, gives, gasreq, gasprice, maker);
  }

  function addOffer(
    TickTree storage tickTree,
    uint offerId,
    Tick tick,
    int logPrice,
    uint gives,
    uint gasreq,
    uint gasprice,
    address maker
  ) internal {
    // Update leaf and last offer
    Leaf leaf = tickTree.leafs[tick.leafIndex()];
    // console.log("leaf before: %s", toString(leaf));
    uint lastId = leaf.lastOfIndex(tick.posInLeaf());
    if (lastId == 0) {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), offerId, false);
    } else {
      tickTree.offers[lastId].offer = tickTree.offers[lastId].offer.next(offerId);
    }
    tickTree.leafs[tick.leafIndex()] = leaf.setIndexFirstOrLast(tick.posInLeaf(), offerId, true);
    // console.log("leaf after: %s", toString(tickTree.leafs[tick.leafIndex()]));

    // Create offer
    tickTree.offers[offerId].offer =
      MgvStructs.Offer.pack({__prev: lastId, __next: 0, __logPrice: logPrice, __gives: gives});
    tickTree.offers[offerId].detail = MgvStructs.OfferDetail.pack({
      __maker: maker,
      __gasreq: gasreq,
      __kilo_offer_gasbase: tickTree.local.offer_gasbase() / 1e3,
      __gasprice: gasprice
    });

    // Update levels
    tickTree.local = tickTree.local.level2(setBit(tickTree.local.level2(), tick.posInLevel2()));
    // As an optimization, Mangrove only updates these for the part of the branch that is not best.
    // We don't do that here, as there's no reason for the complexity.
    tickTree.level1[tick.level1Index()] = setBit(tickTree.level1[tick.level1Index()], tick.posInLevel1());
    tickTree.level0[tick.level0Index()] = setBit(tickTree.level0[tick.level0Index()], tick.posInLevel0());

    // Update local
    updateLocalWithBestBranch(tickTree);
  }

  function removeOffer(TickTree storage tickTree, uint offerId) internal {
    Offer storage offer = tickTree.offers[offerId];
    Tick tick = offer.offer.tick(olKey.tickScale);

    // Update leaf and tick list
    Leaf leaf = tickTree.leafs[tick.leafIndex()];
    uint currentId = leaf.firstOfIndex(tick.posInLeaf());
    uint prevId = 0;
    while (currentId != offerId) {
      prevId = currentId;
      currentId = tickTree.offers[currentId].offer.next();
    }
    if (prevId == 0) {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), offer.offer.next(), false);
    } else {
      tickTree.offers[prevId].offer = tickTree.offers[prevId].offer.next(offer.offer.next());
    }
    if (offer.offer.next() == 0) {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), prevId, true);
    }
    tickTree.leafs[tick.leafIndex()] = leaf;

    // Update levels
    if (leaf.eq(LeafLib.EMPTY)) {
      tickTree.level0[tick.level0Index()] = unsetBit(tickTree.level0[tick.level0Index()], tick.posInLevel0());
      if (tickTree.level0[tick.level0Index()].eq(FieldLib.EMPTY)) {
        tickTree.level1[tick.level1Index()] = unsetBit(tickTree.level1[tick.level1Index()], tick.posInLevel1());
        if (tickTree.level1[tick.level1Index()].eq(FieldLib.EMPTY)) {
          tickTree.local = tickTree.local.level2(unsetBit(tickTree.local.level2(), tick.posInLevel2()));
        }
      }
    }

    // Update local
    updateLocalWithBestBranch(tickTree);
  }

  // # Tick scenario utility structs and functions

  struct TickScenario {
    int tick;
    bool hasHigherTick;
    int higherTick;
    bool hasLowerTick;
    int lowerTick;
  }

  function generateHigherTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() < MAX_LEAF_POSITION) {
      ticks[next++] = tick + 1; // in leaf
    }
    if (_tick.posInLevel0() < MAX_LEVEL0_POSITION) {
      ticks[next++] = tick + LEAF_SIZE; // in level0
    }
    if (_tick.posInLevel1() < MAX_LEVEL1_POSITION) {
      ticks[next++] = tick + LEAF_SIZE * LEVEL0_SIZE; // in level1
    }
    if (_tick.posInLevel2() < MAX_LEVEL2_POSITION) {
      ticks[next++] = tick + LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE; // in level2
    }
    // FIXME: MAX_TICK is currently out of range
    // if (tick < MAX_TICK) {
    //   ticks[next++] = MAX_TICK; // at max tick
    // }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateLowerTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() > 0) {
      ticks[next++] = tick - 1; // in leaf
    }
    if (_tick.posInLevel0() > 0) {
      ticks[next++] = tick - LEAF_SIZE; // in level0
    }
    if (_tick.posInLevel1() > 0) {
      ticks[next++] = tick - LEAF_SIZE * LEVEL0_SIZE; // in level1
    }
    if (_tick.posInLevel2() > 0) {
      ticks[next++] = tick - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE; // in level2
    }
    // FIXME: MIN_TICK is currently out of range
    // if (tick > MIN_TICK) {
    //   ticks[next++] = MIN_TICK; // at min tick
    // }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  uint[] tickListSizeScenarios = [0, 1, 2]; // NB: 0 must be the first scenario, as we skip that for higher and lower tick scenarios

  function generateTickScenarios(int tick) internal pure returns (TickScenario[] memory) {
    int[] memory higherTicks = generateHigherTickScenarios(tick);
    int[] memory lowerTicks = generateLowerTickScenarios(tick);
    TickScenario[] memory tickScenarios =
      new TickScenario[](1 + higherTicks.length + lowerTicks.length + higherTicks.length * lowerTicks.length);
    uint next = 0;
    tickScenarios[next++] =
      TickScenario({tick: tick, hasHigherTick: false, higherTick: 0, hasLowerTick: false, lowerTick: 0});
    for (uint h = 0; h < higherTicks.length; ++h) {
      tickScenarios[next++] =
        TickScenario({tick: tick, hasHigherTick: true, higherTick: higherTicks[h], hasLowerTick: false, lowerTick: 0});
    }
    for (uint l = 0; l < lowerTicks.length; ++l) {
      tickScenarios[next++] =
        TickScenario({tick: tick, hasHigherTick: false, higherTick: 0, hasLowerTick: true, lowerTick: lowerTicks[l]});
    }
    for (uint h = 0; h < higherTicks.length; ++h) {
      for (uint l = 0; l < lowerTicks.length; ++l) {
        tickScenarios[next++] = TickScenario({
          tick: tick,
          hasHigherTick: true,
          higherTick: higherTicks[h],
          hasLowerTick: true,
          lowerTick: lowerTicks[l]
        });
      }
    }
    return tickScenarios;
  }

  function add_n_offers_to_tick(int tick, uint n) internal {
    Tick _tick = Tick.wrap(tick);
    uint gives = getAcceptableGivesForTick(_tick, 100_000);
    for (uint i = 1; i <= n; ++i) {
      mgv.newOfferByLogPrice(olKey, LogPriceLib.fromTick(_tick, olKey.tickScale), gives, 100_000, 1);
    }
  }

  // # Tick utility functions

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
}