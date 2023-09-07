// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import "mgv_src/MgvLib.sol";
import {MgvCommon} from "mgv_src/MgvCommon.sol";
import "mgv_lib/Debug.sol";

int constant MIN_LEAF_INDEX = -NUM_LEAFS / 2;
int constant MAX_LEAF_INDEX = -MIN_LEAF_INDEX - 1;
int constant MIN_LEVEL0_INDEX = -NUM_LEVEL0 / 2;
int constant MAX_LEVEL0_INDEX = -MIN_LEVEL0_INDEX - 1;
int constant MIN_LEVEL1_INDEX = -NUM_LEVEL1 / 2;
int constant MAX_LEVEL1_INDEX = -MIN_LEVEL1_INDEX - 1;
uint constant MAX_LEAF_POSITION = uint(LEAF_SIZE - 1);
uint constant MAX_LEVEL0_POSITION = uint(LEVEL0_SIZE - 1);
uint constant MAX_LEVEL1_POSITION = uint(LEVEL1_SIZE - 1);
uint constant MAX_LEVEL2_POSITION = uint(LEVEL2_SIZE - 1);

// Provides a simple tick tree data structure and operations on it that can be used to simulate Mangrove's tick tree
// and then be compared to the actual tick tree.
//
// See core/ticktree/README.md for more details on how this can be used.
//
// NB: Inheriting from MangroveTest to get assert functions.
contract TestTickTree is MangroveTest {
  MgvStructs.LocalPacked public local;
  mapping(uint => MgvCommon.OfferData) public offers;
  mapping(int => Leaf) public leafs;
  mapping(int => Field) public level0s;
  mapping(int => Field) public level1s;

  constructor(IMangrove _mgv, MgvReader _reader, OLKey memory _olKey) {
    mgv = _mgv;
    reader = _reader;
    olKey = _olKey;

    // generic trace labeling
    vm.label($(this), "TestTickTree");
  }

  // Creates a snapshot of the Mangrove tick tree
  function snapshotMgvTickTree() public {
    local = reader.local(olKey);
    Field level2 = mgv.level2(olKey);
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = mgv.level1(olKey, level1Index);
      level1s[level1Index] = level1;
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = mgv.level0(olKey, level0Index);
        level0s[level0Index] = level0;
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = mgv.leafs(olKey, leafIndex);
          leafs[leafIndex] = leaf;
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            uint offerId = leaf.firstOfIndex(leafPos);
            while (offerId != 0) {
              offers[offerId].offer = mgv.offers(olKey, offerId);
              offers[offerId].detail = mgv.offerDetails(olKey, offerId);
              offerId = offers[offerId].offer.next();
            }
          }
        }
      }
    }
  }

  // Checks that the current Mangrove tick tree in olKey is consistent
  function assertMgvTickTreeIsConsistent() public {
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
  function assertEqToMgvOffer() public {
    Field level2 = mgv.level2(olKey);
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      assertEq(
        isBitSet(level2, level2Pos),
        isBitSet(local.level2(), level2Pos),
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
          isBitSet(level1s[level1Index], level1Pos),
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
            isBitSet(level0s[level0Index], level0Pos),
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
                leafs[leafIndex].firstOfIndex(leafPos),
                string.concat("leaf first mismatch, pos: ", vm.toString(leafPos))
              );
              assertEq(
                leaf.lastOfIndex(leafPos),
                leafs[leafIndex].lastOfIndex(leafPos),
                string.concat("leaf last mismatch, pos: ", vm.toString(leafPos))
              );
            }
            uint offerId = leaf.firstOfIndex(leafPos);
            while (offerId != 0) {
              {
                MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
                MgvStructs.OfferPacked offerTickTree = offers[offerId].offer;
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
                MgvStructs.OfferDetailPacked detailTickTree = offers[offerId].detail;
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

  function logTickTree() public view {
    Field level2 = local.level2();
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }
      console.log("l2: %s", level2Pos);

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = level1s[level1Index];
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }
        console.log("  l1: %s (index: %s)", level1Pos, vm.toString(level1IndexFromLevel2Pos(level2Pos)));

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = level0s[level0Index];
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }
          console.log(
            "    l0: %s (index: %s)", level0Pos, vm.toString(level0IndexFromLevel1IndexAndPos(level1Index, level1Pos))
          );

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = leafs[leafIndex];
          for (uint leafPos = 0; leafPos <= MAX_LEAF_POSITION; ++leafPos) {
            Tick tick = tickFromLeafIndexAndPos(leafIndex, leafPos);
            uint offerId = leaf.firstOfIndex(leafPos);
            if (offerId == 0) {
              continue;
            }
            console.log("      leaf: %s (index: %s) | tick: %s", leafPos, vm.toString(leafIndex), toString(tick));
            do {
              console.log("        offer: %s", offerId);
              offerId = offers[offerId].offer.next();
            } while (offerId != 0);
          }
        }
      }
    }
  }

  function best() public view returns (uint bestOfferId, Tick bestTick) {
    Field level2 = local.level2();
    for (uint level2Pos = 0; level2Pos <= MAX_LEVEL2_POSITION; ++level2Pos) {
      if (!isBitSet(level2, level2Pos)) {
        continue;
      }

      int level1Index = level1IndexFromLevel2Pos(level2Pos);
      Field level1 = level1s[level1Index];
      for (uint level1Pos = 0; level1Pos <= MAX_LEVEL1_POSITION; ++level1Pos) {
        if (!isBitSet(level1, level1Pos)) {
          continue;
        }

        int level0Index = level0IndexFromLevel1IndexAndPos(level1Index, level1Pos);
        Field level0 = level0s[level0Index];
        for (uint level0Pos = 0; level0Pos <= MAX_LEVEL0_POSITION; ++level0Pos) {
          if (!isBitSet(level0, level0Pos)) {
            continue;
          }

          int leafIndex = leafIndexFromLevel0IndexAndPos(level0Index, level0Pos);
          Leaf leaf = leafs[leafIndex];
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

  function addOffer(uint offerId, Tick tick, uint gives, uint gasreq, uint gasprice, address maker) public {
    // Update leaf and last offer
    Leaf leaf = leafs[tick.leafIndex()];
    // console.log("leaf before: %s", toString(leaf));
    uint lastId = leaf.lastOfIndex(tick.posInLeaf());
    if (lastId == 0) {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), offerId, false);
    } else {
      offers[lastId].offer = offers[lastId].offer.next(offerId);
    }
    leafs[tick.leafIndex()] = leaf.setIndexFirstOrLast(tick.posInLeaf(), offerId, true);
    // console.log("leaf after: %s", toString(leafs[tick.leafIndex()]));

    // Create offer
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    offers[offerId].offer = MgvStructs.Offer.pack({__prev: lastId, __next: 0, __logPrice: logPrice, __gives: gives});
    offers[offerId].detail = MgvStructs.OfferDetail.pack({
      __maker: maker,
      __gasreq: gasreq,
      __kilo_offer_gasbase: local.offer_gasbase() / 1e3,
      __gasprice: gasprice
    });

    // Update levels
    local = local.level2(setBit(local.level2(), tick.posInLevel2()));
    // As an optimization, Mangrove only updates these for the part of the branch that is not best.
    // We don't do that here, as there's no reason for the complexity.
    level1s[tick.level1Index()] = setBit(level1s[tick.level1Index()], tick.posInLevel1());
    level0s[tick.level0Index()] = setBit(level0s[tick.level0Index()], tick.posInLevel0());

    // Update local
    updateLocalWithBestBranch();
  }

  function removeOffer(uint offerId) public {
    MgvCommon.OfferData storage offer = offers[offerId];
    Tick tick = offer.offer.tick(olKey.tickScale);

    // Update leaf and tick list
    Leaf leaf = leafs[tick.leafIndex()];
    uint prevId = offer.offer.prev();
    uint nextId = offer.offer.next();
    if (prevId != 0) {
      offers[prevId].offer = offers[prevId].offer.next(nextId);
    } else {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), nextId, false);
    }
    if (nextId != 0) {
      offers[nextId].offer = offers[nextId].offer.prev(prevId);
    } else {
      leaf = leaf.setIndexFirstOrLast(tick.posInLeaf(), prevId, true);
    }
    leafs[tick.leafIndex()] = leaf;

    // Update levels
    if (leaf.eq(LeafLib.EMPTY)) {
      level0s[tick.level0Index()] = unsetBit(level0s[tick.level0Index()], tick.posInLevel0());
      if (level0s[tick.level0Index()].eq(FieldLib.EMPTY)) {
        level1s[tick.level1Index()] = unsetBit(level1s[tick.level1Index()], tick.posInLevel1());
        if (level1s[tick.level1Index()].eq(FieldLib.EMPTY)) {
          local = local.level2(unsetBit(local.level2(), tick.posInLevel2()));
        }
      }
    }

    // Update local
    updateLocalWithBestBranch();
  }

  function updateLocalWithBestBranch() internal {
    (, Tick tick) = best();
    local = local.level1(level1s[tick.level1Index()]);
    local = local.level0(level0s[tick.level0Index()]);
    local = local.tickPosInLeaf(tick.posInLeaf());
  }

  function addOffer(Tick tick, uint gives, uint gasreq, uint gasprice, address maker) public {
    uint offerId = 1 + local.last();
    local = local.last(offerId);

    addOffer(offerId, tick, gives, gasreq, gasprice, maker);
  }

  function updateOffer(uint offerId, Tick newTick, uint gives, uint gasreq, uint gasprice, address maker) public {
    if (offers[offerId].offer.isLive()) {
      removeOffer(offerId);
    }
    addOffer(offerId, newTick, gives, gasreq, gasprice, maker);
  }

  // Utility functions
  function setBit(Field field, uint pos) public pure returns (Field) {
    return Field.wrap(Field.unwrap(field) | (1 << pos));
  }

  function unsetBit(Field field, uint pos) public pure returns (Field) {
    return Field.wrap(Field.unwrap(field) ^ (1 << pos));
  }

  function isBitSet(Field field, uint pos) public pure returns (bool) {
    return (Field.unwrap(field) & (1 << pos)) > 0;
  }

  function level1IndexFromLevel2Pos(uint pos) public pure returns (int) {
    return int(pos) - LEVEL2_SIZE / 2;
  }

  function level0IndexFromLevel1IndexAndPos(int level1Index, uint pos) public pure returns (int) {
    return (level1Index << LEVEL1_SIZE_BITS) | int(pos);
  }

  function leafIndexFromLevel0IndexAndPos(int level0Index, uint pos) public pure returns (int) {
    return (level0Index << LEVEL0_SIZE_BITS) | int(pos);
  }

  function tickFromLeafIndexAndPos(int leafIndex, uint pos) public pure returns (Tick) {
    return Tick.wrap((leafIndex << LEAF_SIZE_BITS) | int(pos));
  }
}
