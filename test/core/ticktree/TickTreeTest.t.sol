// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {AbstractMangrove, TestTaker, MangroveTest, IMaker, TestMaker} from "mgv_test/lib/MangroveTest.sol";
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
//
// See README.md in this folder for more details.
abstract contract TickTreeTest is MangroveTest {
  TestMaker mkr;

  receive() external payable {}

  function setUp() public virtual override {
    super.setUp();

    mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, type(uint).max);
    mkr.provisionMgv(1 ether);

    deal($(base), $(mkr), type(uint).max);
    deal($(quote), $(this), type(uint).max);
  }

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
      bool level2PosIsSet = isBitSet(level2, level2Pos);
      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = mgv.level1(olKey, level1Index);

      if (!level2PosIsSet) {
        assertTrue(
          level1.eq(FieldLib.EMPTY),
          string.concat("level1 should be empty when bit is not set in level2 | tree branch: ", vm.toString(level2Pos))
        );
        // checking that the entire subtree is empty is too expensive, so we stop here
        continue;
      }
      assertTrue(
        !level1.eq(FieldLib.EMPTY),
        string.concat("level1 should not be empty when bit is set in level2 | tree branch: ", vm.toString(level2Pos))
      );

      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        bool level1PosIsSet = isBitSet(level1, level1Pos);
        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = mgv.level0(olKey, level0Index);

        if (!level1PosIsSet) {
          assertTrue(
            level0.eq(FieldLib.EMPTY),
            string.concat(
              "level0 should be empty when bit is not set in level1 | tree branch: ",
              vm.toString(level2Pos),
              "->",
              vm.toString(level1Pos)
            )
          );
          // checking that the entire subtree is empty is too expensive, so we stop here
          continue;
        }
        assertTrue(
          !level0.eq(FieldLib.EMPTY),
          string.concat(
            "level0 should not be empty when bit is set in level1 | tree branch: ",
            vm.toString(level2Pos),
            "->",
            vm.toString(level1Pos)
          )
        );

        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          bool level0PosIsSet = isBitSet(level0, level0Pos);
          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = mgv.leafs(olKey, leafIndex);

          if (!level0PosIsSet) {
            assertTrue(
              leaf.eq(LeafLib.EMPTY),
              string.concat(
                "leaf should be empty when bit is not set in level0 | tree branch: ",
                vm.toString(level2Pos),
                "->",
                vm.toString(level1Pos),
                "->",
                vm.toString(level0Pos)
              )
            );
            // checking that the entire subtree is empty is too expensive, so we stop here
            continue;
          }
          assertTrue(
            !level0PosIsSet || !leaf.eq(LeafLib.EMPTY),
            string.concat(
              "leaf should not be empty when bit is set in level0 | tree branch: ",
              vm.toString(level2Pos),
              "->",
              vm.toString(level1Pos),
              "->",
              vm.toString(level0Pos)
            )
          );

          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              assertEq(leaf.lastOfIndex(leafPos), 0);
              continue;
            }
            uint prev = 0;
            do {
              MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
              assertEq(
                offer.tick(olKey.tickScale),
                tick,
                string.concat(
                  "offer[", vm.toString(offerId), "] tick does not match location in tick tree | tick: ", toString(tick)
                )
              );
              assertEq(
                offer.prev(),
                prev,
                string.concat(
                  "offer[",
                  vm.toString(offerId),
                  "].prev does point to previous offer in tick list | tick: ",
                  toString(tick)
                )
              );
              assertTrue(
                offer.isLive(),
                string.concat("offer[", vm.toString(offerId), "] in tick tree should be live | tick: ", toString(tick))
              );
              prev = offerId;
              offerId = offer.next();
            } while (offerId != 0);
            assertEq(
              leaf.lastOfIndex(leafPos),
              prev,
              string.concat(
                "last offer[",
                vm.toString(leaf.lastOfIndex(leafPos)),
                "] in tick does not match last offer[",
                vm.toString(prev),
                "] in tick list | tick: ",
                toString(tick)
              )
            );
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
          string.concat("level1 bit mismatch, branch: ", vm.toString(level2Pos), "->", vm.toString(level1Pos))
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
            string.concat(
              "level0 bit mismatch, branch: ",
              vm.toString(level2Pos),
              "->",
              vm.toString(level1Pos),
              "->",
              vm.toString(level0Pos)
            )
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
                  string.concat(
                    "offer mismatch | offerId ",
                    vm.toString(offerId),
                    " | MGV ",
                    toString(offer),
                    " | tick tree ",
                    toString(offerTickTree)
                  )
                );
                offerId = offer.next();
              }
              {
                MgvStructs.OfferDetailPacked detail = mgv.offerDetails(olKey, offerId);
                MgvStructs.OfferDetailPacked detailTickTree = tickTree.offers[offerId].detail;
                assertTrue(
                  detail.eq(detailTickTree),
                  string.concat(
                    "offer detail mismatch | offerId ",
                    vm.toString(offerId),
                    " | MGV ",
                    toString(detail),
                    " | tick tree ",
                    toString(detailTickTree)
                  )
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
    return Field.wrap(Field.unwrap(field) ^ (1 << pos));
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
        console.log("  l1: %s (index: %s)", level1Pos, vm.toString(level1IndexFromLevel2Pos(level2Pos)));

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = tickTree.level0[level0Index];
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }
          console.log(
            "    l0: %s (index: %s)", level0Pos, vm.toString(level0IndexFromLevel1IndexAndPos(level1Index, level1Pos))
          );

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = tickTree.leafs[leafIndex];
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              continue;
            }
            console.log("      leaf: %s (index: %s) | tick: %s", leafPos, vm.toString(leafIndex), toString(tick));
            do {
              console.log("        offer: %s", offerId);
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

  function addOffer(TickTree storage tickTree, Tick tick, uint gives, uint gasreq, uint gasprice, address maker)
    internal
  {
    uint offerId = 1 + tickTree.local.last();
    tickTree.local = tickTree.local.last(offerId);

    addOffer(tickTree, offerId, tick, gives, gasreq, gasprice, maker);
  }

  function addOffer(
    TickTree storage tickTree,
    uint offerId,
    Tick tick,
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
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
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
    uint prevId = offer.offer.prev();
    uint nextId = offer.offer.next();
    if (prevId != 0) {
      tickTree.offers[prevId].offer = tickTree.offers[prevId].offer.next(nextId);
    } else {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), nextId, false);
    }
    if (nextId != 0) {
      tickTree.offers[nextId].offer = tickTree.offers[nextId].offer.prev(prevId);
    } else {
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

  function updateOffer(
    TickTree storage tickTree,
    uint offerId,
    Tick newTick,
    uint gives,
    uint gasreq,
    uint gasprice,
    address maker
  ) internal {
    if (tickTree.offers[offerId].offer.isLive()) {
      removeOffer(tickTree, offerId);
    }
    addOffer(tickTree, offerId, newTick, gives, gasreq, gasprice, maker);
  }

  // # Tick scenario utility structs and functions

  struct TickScenario {
    int tick;
    bool hasHigherTick;
    int higherTick;
    uint higherTickListSize;
    bool hasLowerTick;
    int lowerTick;
    uint lowerTickListSize;
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
    if (tick < MAX_TICK) {
      ticks[next++] = MAX_TICK; // at max tick
    }

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
    if (tick > MIN_TICK) {
      ticks[next++] = MIN_TICK; // at min tick
    }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateTickScenarios(
    int tick,
    uint[] storage higherTickListSizeScenarios,
    uint[] storage lowerTickListSizeScenarios
  ) internal view returns (TickScenario[] memory) {
    int[] memory higherTicks = generateHigherTickScenarios(tick);
    int[] memory lowerTicks = generateLowerTickScenarios(tick);
    TickScenario[] memory tickScenarios =
    new TickScenario[](1 + higherTicks.length * higherTickListSizeScenarios.length + lowerTicks.length * lowerTickListSizeScenarios.length + higherTicks.length * lowerTicks.length * higherTickListSizeScenarios.length * lowerTickListSizeScenarios.length);
    uint next = 0;
    tickScenarios[next++] = TickScenario({
      tick: tick,
      hasHigherTick: false,
      higherTick: 0,
      higherTickListSize: 0,
      hasLowerTick: false,
      lowerTick: 0,
      lowerTickListSize: 0
    });
    for (uint h = 0; h < higherTicks.length; ++h) {
      for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
        tickScenarios[next++] = TickScenario({
          tick: tick,
          hasHigherTick: true,
          higherTick: higherTicks[h],
          higherTickListSize: higherTickListSizeScenarios[hs],
          hasLowerTick: false,
          lowerTick: 0,
          lowerTickListSize: 0
        });
      }
    }
    for (uint l = 0; l < lowerTicks.length; ++l) {
      for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
        tickScenarios[next++] = TickScenario({
          tick: tick,
          hasHigherTick: false,
          higherTick: 0,
          higherTickListSize: 0,
          hasLowerTick: true,
          lowerTick: lowerTicks[l],
          lowerTickListSize: lowerTickListSizeScenarios[ls]
        });
      }
    }
    for (uint h = 0; h < higherTicks.length; ++h) {
      for (uint l = 0; l < lowerTicks.length; ++l) {
        for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
          for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
            tickScenarios[next++] = TickScenario({
              tick: tick,
              hasHigherTick: true,
              higherTick: higherTicks[h],
              higherTickListSize: higherTickListSizeScenarios[hs],
              hasLowerTick: true,
              lowerTick: lowerTicks[l],
              lowerTickListSize: lowerTickListSizeScenarios[ls]
            });
          }
        }
      }
    }
    return tickScenarios;
  }

  function add_n_offers_to_tick(int tick, uint n) internal returns (uint[] memory offerIds, uint gives) {
    return add_n_offers_to_tick(tick, n, false);
  }

  function add_n_offers_to_tick(int tick, uint n, bool offersFail)
    internal
    returns (uint[] memory offerIds, uint gives)
  {
    Tick _tick = Tick.wrap(tick);
    int logPrice = LogPriceLib.fromTick(_tick, olKey.tickScale);
    gives = getAcceptableGivesForTick(_tick, 100_000);
    offerIds = new uint[](n);
    for (uint i = 0; i < n; ++i) {
      if (offersFail) {
        offerIds[i] = mkr.newFailingOfferByLogPrice(logPrice, gives, 100_000);
      } else {
        offerIds[i] = mkr.newOfferByLogPrice(logPrice, gives, 100_000);
      }
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
