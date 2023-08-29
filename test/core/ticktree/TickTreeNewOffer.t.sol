// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {AbstractMangrove, TestTaker, MangroveTest, IMaker} from "mgv_test/lib/MangroveTest.sol";
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

// FIXME: Extract common constants and utility methods to a test base class
contract TickTreeNewOfferTest is MangroveTest {
  function setUp() public override {
    super.setUp();

    // generateInsertionTicks();
    // generateTickScenarios();
    // generateNewOfferScenarios();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
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

  // Cheks that the ticks used in these tests have the expected locations at various levels.
  // This also serves as a reading guide to the constants.
  function test_ticks_are_at_expected_locations() public {
    assertTickAssumptions({
      tick: Tick.wrap(MIN_TICK),
      // FIXME: This failed because MIN_TICK was 1 bigger than the smallest number representable by int20. I've changed MIN_TICK the min value of int20.
      posInLeaf: 0,
      leafIndex: MIN_LEAF_INDEX,
      posInLevel0: 0,
      level0Index: MIN_LEVEL0_INDEX,
      posInLevel1: 0,
      level1Index: MIN_LEVEL1_INDEX,
      posInLevel2: 0
    });

    assertTickAssumptions({
      tick: Tick.wrap(MAX_TICK),
      posInLeaf: MAX_LEAF_POSITION,
      leafIndex: MAX_LEAF_INDEX,
      posInLevel0: MAX_LEVEL0_POSITION,
      level0Index: MAX_LEVEL0_INDEX,
      posInLevel1: MAX_LEVEL1_POSITION,
      level1Index: MAX_LEVEL1_INDEX,
      posInLevel2: MAX_LEVEL2_POSITION
    });
  }

  struct OfferData {
    uint id;
    Tick tick;
    int logPrice;
    uint gives;
    uint gasreq;
    uint gasprice;
  }

  function createOfferData(Tick tick, uint gasreq, uint gasprice) internal view returns (OfferData memory offerData) {
    offerData.id = 0;
    offerData.tick = tick;
    offerData.logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    offerData.gasreq = gasreq;
    offerData.gives = reader.minVolume(olKey, offerData.gasreq);
    offerData.gasprice = gasprice;
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

  mapping(uint => TickTree) tickTrees;
  uint tickTreeCount;

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
  // # New offer tests

  // int[] insertionTicks;

  // function generateInsertionTicks() internal  {
  //   // FIXME: Create a more comprehensive set of insertion ticks
  //   // FIXME: Min tick currently doesn't work, generates wants=0
  //   // insertionTicks.push(MIN_TICK);
  //   // FIXME: Max tick currently doesn't work, generates a too big wants
  //   // insertionTicks.push(MAX_TICK);
  //   // insertionTicks.push(0);
  //   // insertionTicks.push(1);
  //   // insertionTicks.push(2);
  //   // insertionTicks.push(3);
  //   insertionTicks.push(-1);
  //   insertionTicks.push(-2);
  //   insertionTicks.push(-3);
  //   insertionTicks.push(-4);
  // }

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

  struct TickScenario {
    int tick;
    bool hasHigherTick;
    int higherTick;
    bool hasLowerTick;
    int lowerTick;
  }

  struct NewOfferScenario {
    TickScenario tickScenario;
    uint insertionTickListSize;
    uint higherTickListSize;
    uint lowerTickListSize;
  }

  // TickScenario[] tickScenarios;

  uint[] tickListSizeScenarios = [0, 1, 2]; // NB: 0 must be the first scenario, as we skip that for higher and lower tick scenarios

  // function generateTickScenarios() internal {
  //   for (uint i = 0; i < insertionTicks.length; ++i) {
  //     int[] memory higherTicks = generateHigherTickScenarios(insertionTicks[i]);
  //     int[] memory lowerTicks = generateLowerTickScenarios(insertionTicks[i]);
  //     tickScenarios.push(TickScenario({tick: insertionTicks[i], hasHigherTick: false, higherTick: 0, hasLowerTick: false, lowerTick: 0}));
  //     for (uint h = 0; h < higherTicks.length; ++h) {
  //       tickScenarios.push(TickScenario({tick: insertionTicks[i], hasHigherTick: true, higherTick: higherTicks[h], hasLowerTick: false, lowerTick: 0}));
  //     }
  //     for (uint l = 0; l < lowerTicks.length; ++l) {
  //       tickScenarios.push(TickScenario({tick: insertionTicks[i], hasHigherTick: false, higherTick: 0, hasLowerTick: true, lowerTick: lowerTicks[l]}));
  //     }
  //     for (uint h = 0; h < higherTicks.length; ++h) {
  //       for (uint l = 0; l < lowerTicks.length; ++l) {
  //         tickScenarios.push(TickScenario({tick: insertionTicks[i], hasHigherTick: true, higherTick: higherTicks[h], hasLowerTick: true, lowerTick: lowerTicks[l]}));
  //       }
  //     }
  //   }
  // }
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
    for (uint i = 1; i <= n; ++i) {
      mgv.newOfferByLogPrice(olKey, LogPriceLib.fromTick(Tick.wrap(tick), olKey.tickScale), 1 ether, i * 100_000, i);
    }
  }

  function test_new_offer_for_tick0() public {
    run_new_offer_scenarios_for_tick(0);
  }

  function test_new_offer_for_tick1() public {
    run_new_offer_scenarios_for_tick(1);
  }

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.
  function run_new_offer_scenarios_for_tick(int tick) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios = generateTickScenarios(tick);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
        uint insertionTickListSize = tickListSizeScenarios[j];
        if (!tickScenario.hasHigherTick) {
          if (!tickScenario.hasLowerTick) {
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: 0,
                lowerTickListSize: 0
              })
            );
          } else {
            for (uint l = 1; l < tickListSizeScenarios.length; ++l) {
              uint lowerTickListSize = tickListSizeScenarios[l];
              run_new_offer_scenario(
                NewOfferScenario({
                  tickScenario: tickScenario,
                  insertionTickListSize: insertionTickListSize,
                  higherTickListSize: 0,
                  lowerTickListSize: lowerTickListSize
                })
              );
            }
          }
        } else if (!tickScenario.hasLowerTick) {
          for (uint h = 1; h < tickListSizeScenarios.length; ++h) {
            uint higherTickListSize = tickListSizeScenarios[h];
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: higherTickListSize,
                lowerTickListSize: 0
              })
            );
          }
        }
        // For higher and lower tick, we skip the empty tick list scenario as it's equivalent to has{Higher, Lower}Tick = false
        for (uint k = 1; k < tickListSizeScenarios.length; ++k) {
          uint higherTickListSize = tickListSizeScenarios[k];
          for (uint l = 1; l < tickListSizeScenarios.length; ++l) {
            uint lowerTickListSize = tickListSizeScenarios[l];
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: higherTickListSize,
                lowerTickListSize: lowerTickListSize
              })
            );
          }
        }
      }
    }
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario) internal {
    console.log("new offer scenario");
    console.log("  insertionTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
    console.log("  insertionTickListSize: %s", scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      console.log("  higherTick: %s", toString(Tick.wrap(scenario.tickScenario.higherTick)));
      console.log("  higherTickListSize: %s", scenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
      console.log("  lowerTickListSize: %s", scenario.lowerTickListSize);
    }
    // TODO:
    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();
    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.tick, scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.lowerTickListSize);
    }
    // 3. Snapshot tick tree
    TickTree storage tickTree = snapshotTickTree();
    // 4. Create new offer and add it to tick tree
    Tick _insertionTick = Tick.wrap(scenario.tickScenario.tick);
    int logPrice = LogPriceLib.fromTick(_insertionTick, olKey.tickScale);
    mgv.newOfferByLogPrice(olKey, logPrice, 1 ether, 50_000, 50);
    addOffer(tickTree, _insertionTick, logPrice, 1 ether, 50_000, 50, $(this));
    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);
    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
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

  function test_new_offer_in_empty_tree_at_max_tick() public {
    OfferData memory offerData1 = createOfferData(Tick.wrap(MAX_TICK), 100_000, 1);

    TickTree storage tickTree = snapshotTickTree();

    offerData1.id =
      mgv.newOfferByLogPrice(olKey, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice);
    addOffer(
      tickTree, offerData1.tick, offerData1.logPrice, offerData1.gives, offerData1.gasreq, offerData1.gasprice, $(this)
    );
    assertMgvOfferListEqToTickTree(tickTree);
  }

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

  // # Update offer tests

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

  // TODO:
  // - Test variants where offers move:
  //   - to end of tick list
  //   - to other leaf position
  //   - to other level0 position
  //   - to other level1 position
  //   - to other level2 position
  //   This may be easiest to do, if we make a test function, that is parametric in the old and new tick etc
  // - Test MgvOfferTaking operations

  // Lasse: Can we add these assertions to existing tests? Eg by adding a wrapper to Mangrove and adding assertions to that
  //        Possibly via the IMangrove interface so we exercise it regularly
  // Lasse: Can we do fuzz/invariant testing with this? Could supplement the more structured tests
}
