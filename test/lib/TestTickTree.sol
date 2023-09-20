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
int constant MIN_LEVEL2_INDEX = -NUM_LEVEL2 / 2;
int constant MAX_LEVEL2_INDEX = -MIN_LEVEL2_INDEX - 1;

uint constant MIN_LEAF_POS = 0;
uint constant MIN_LEVEL_POS = 0;
uint constant MIN_ROOT_POS = 0;

uint constant MAX_LEAF_POS = uint(LEAF_SIZE - 1);
uint constant MAX_LEVEL_POS = uint(LEVEL_SIZE - 1);
uint constant MAX_ROOT_POS = uint(ROOT_SIZE - 1);

uint constant MID_LEAF_POS = MAX_LEAF_POS / 2;
uint constant MID_LEVEL_POS = MAX_LEVEL_POS / 2;
uint constant MID_ROOT_POS = MAX_ROOT_POS / 2;

library TickTreeUtil {
  function setBit(Field field, uint pos) public pure returns (Field) {
    return Field.wrap(Field.unwrap(field) | (1 << pos));
  }

  function unsetBit(Field field, uint pos) public pure returns (Field) {
    return Field.wrap(Field.unwrap(field) ^ (1 << pos));
  }

  function isBitSet(Field field, uint pos) public pure returns (bool) {
    return (Field.unwrap(field) & (1 << pos)) > 0;
  }

  function level2IndexFromRootPos(uint pos) public pure returns (int) {
    return int(pos) - ROOT_SIZE / 2;
  }

  function level1IndexFromLevel2IndexAndPos(int level2Index, uint pos) public pure returns (int) {
    return (level2Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function level0IndexFromLevel1IndexAndPos(int level1Index, uint pos) public pure returns (int) {
    return (level1Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function leafIndexFromLevel0IndexAndPos(int level0Index, uint pos) public pure returns (int) {
    return (level0Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function tickTreeIndexFromLeafIndexAndPos(int leafIndex, uint pos) public pure returns (TickTreeIndex) {
    return TickTreeIndex.wrap((leafIndex << LEAF_SIZE_BITS) | int(pos));
  }

  function tickTreeIndexFromPositions(
    uint posInRoot,
    uint posInLevel2,
    uint posInLevel1,
    uint posInLevel0,
    uint posInLeaf
  ) public pure returns (TickTreeIndex) {
    unchecked {
      uint utickTreeIndex = posInLeaf
        | (
          (
            posInLevel0
              | (posInLevel1 | (posInLevel2 | uint((int(posInRoot) - ROOT_SIZE / 2) << LEVEL_SIZE_BITS)) << LEVEL_SIZE_BITS)
                << LEVEL_SIZE_BITS
          ) << LEAF_SIZE_BITS
        );
      return TickTreeIndex.wrap(int(utickTreeIndex));
    }
  }
}

// Provides a simple tickTreeIndex tree data structure and operations on it that can be used to simulate Mangrove's tickTreeIndex tree
// and then be compared to the actual tickTreeIndex tree.
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
  mapping(int => Field) public level2s;

  constructor(IMangrove _mgv, MgvReader _reader, OLKey memory _olKey) {
    mgv = _mgv;
    reader = _reader;
    olKey = _olKey;

    // generic trace labeling
    vm.label($(this), "TestTickTree");
  }

  // Creates a snapshot of the Mangrove tickTreeIndex tree
  function snapshotMgvTickTree() public {
    local = mgv.local(olKey);
    Field root = mgv.root(olKey);
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(root, levelPoss[3])) {
        continue;
      }

      int level2Index = TickTreeUtil.level2IndexFromRootPos(levelPoss[3]);
      Field level2 = mgv.level2(olKey, level2Index);
      level2s[level2Index] = level2;
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level2, levelPoss[2])) {
          continue;
        }

        int level1Index = TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]);
        Field level1 = mgv.level1(olKey, level1Index);
        level1s[level1Index] = level1;
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level1, levelPoss[1])) {
            continue;
          }

          int level0Index = TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]);
          Field level0 = mgv.level0(olKey, level0Index);
          level0s[level0Index] = level0;
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level0, levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel0IndexAndPos(level0Index, levelPoss[0]);
            Leaf leaf = mgv.leafs(olKey, leafIndex);
            leafs[leafIndex] = leaf;
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              uint offerId = leaf.firstOfPos(leafPos);
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
  }

  // Checks that the current Mangrove tickTreeIndex tree in olKey is consistent
  function assertMgvTickTreeIsConsistent() public {
    Field root = mgv.root(olKey);
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      bool rootPosIsSet = TickTreeUtil.isBitSet(root, levelPoss[3]);
      int level2Index = TickTreeUtil.level2IndexFromRootPos(levelPoss[3]);
      Field level2 = mgv.level2(olKey, level2Index);

      if (!rootPosIsSet) {
        assertTrue(
          level2.eq(FieldLib.EMPTY),
          string.concat(
            "level2 should be empty when bit is not set in root | tree branch: ", branchToString(levelPoss, 3)
          )
        );
        // checking that the entire subtree is empty is too expensive, so we stop here
        continue;
      }
      assertTrue(
        !level2.eq(FieldLib.EMPTY),
        string.concat(
          "level2 should not be empty when bit is set in root | tree branch: ", branchToString(levelPoss, 3)
        )
      );

      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        bool level2PosIsSet = TickTreeUtil.isBitSet(level2, levelPoss[2]);
        int level1Index = TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]);
        Field level1 = mgv.level1(olKey, level1Index);

        if (!level2PosIsSet) {
          assertTrue(
            level2.eq(FieldLib.EMPTY),
            string.concat(
              "level1 should be empty when bit is not set in level2 | tree branch: ", branchToString(levelPoss, 2)
            )
          );
          // checking that the entire subtree is empty is too expensive, so we stop here
          continue;
        }
        assertTrue(
          !level1.eq(FieldLib.EMPTY),
          string.concat(
            "level1 should not be empty when bit is set in level2 | tree branch: ",
            vm.toString(levelPoss[3]),
            "->",
            vm.toString(levelPoss[2])
          )
        );

        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          bool level1PosIsSet = TickTreeUtil.isBitSet(level1, levelPoss[1]);
          int level0Index = TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]);
          Field level0 = mgv.level0(olKey, level0Index);

          if (!level1PosIsSet) {
            assertTrue(
              level0.eq(FieldLib.EMPTY),
              string.concat(
                "level0 should be empty when bit is not set in level1 | tree branch: ", branchToString(levelPoss, 1)
              )
            );
            // checking that the entire subtree is empty is too expensive, so we stop here
            continue;
          }
          assertTrue(
            !level0.eq(FieldLib.EMPTY),
            string.concat(
              "level0 should not be empty when bit is set in level1 | tree branch: ", branchToString(levelPoss, 1)
            )
          );

          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            bool level0PosIsSet = TickTreeUtil.isBitSet(level0, levelPoss[0]);
            int leafIndex = TickTreeUtil.leafIndexFromLevel0IndexAndPos(level0Index, levelPoss[0]);
            Leaf leaf = mgv.leafs(olKey, leafIndex);

            if (!level0PosIsSet) {
              assertTrue(
                leaf.eq(LeafLib.EMPTY),
                string.concat(
                  "leaf should be empty when bit is not set in level0 | tree branch: ", branchToString(levelPoss, 0)
                )
              );
              // checking that the entire subtree is empty is too expensive, so we stop here
              continue;
            }
            assertTrue(
              !level0PosIsSet || !leaf.eq(LeafLib.EMPTY),
              string.concat(
                "leaf should not be empty when bit is set in level0 | tree branch: ", branchToString(levelPoss, 0)
              )
            );

            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              TickTreeIndex tickTreeIndex = TickTreeUtil.tickTreeIndexFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leaf.firstOfPos(leafPos);
              if (offerId == 0) {
                assertEq(
                  leaf.lastOfPos(leafPos),
                  0,
                  string.concat("last offer should be 0 when first is 0 | tickTreeIndex: ", toString(tickTreeIndex))
                );
                continue;
              }
              uint prev = 0;
              do {
                MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
                assertEq(
                  offer.tickTreeIndex(olKey.tickSpacing),
                  tickTreeIndex,
                  string.concat(
                    "offer[",
                    vm.toString(offerId),
                    "] tickTreeIndex does not match location in tickTreeIndex tree | tickTreeIndex: ",
                    toString(tickTreeIndex)
                  )
                );
                assertEq(
                  offer.prev(),
                  prev,
                  string.concat(
                    "offer[",
                    vm.toString(offerId),
                    "].prev does point to previous offer in tickTreeIndex list | tickTreeIndex: ",
                    toString(tickTreeIndex)
                  )
                );
                assertTrue(
                  offer.isLive(),
                  string.concat(
                    "offer[",
                    vm.toString(offerId),
                    "] in tickTreeIndex tree should be live | tickTreeIndex: ",
                    toString(tickTreeIndex)
                  )
                );
                prev = offerId;
                offerId = offer.next();
              } while (offerId != 0);
              assertEq(
                leaf.lastOfPos(leafPos),
                prev,
                string.concat(
                  "last offer[",
                  vm.toString(leaf.lastOfPos(leafPos)),
                  "] in tickTreeIndex does not match last offer[",
                  vm.toString(prev),
                  "] in tickTreeIndex list | tickTreeIndex: ",
                  toString(tickTreeIndex)
                )
              );
            }
          }
        }
      }
    }
  }

  // Checks that the current Mangrove tickTreeIndex tree in olKey is equal to the tickTreeIndex tree passed as argument
  function assertEqToMgvTickTree() public {
    Field root = mgv.root(olKey);
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      assertEq(
        TickTreeUtil.isBitSet(root, levelPoss[3]),
        TickTreeUtil.isBitSet(local.root(), levelPoss[3]),
        string.concat("root bit mismatch, branch: ", branchToString(levelPoss, 3))
      );
      if (!TickTreeUtil.isBitSet(root, levelPoss[3])) {
        continue;
      }

      int level2Index = TickTreeUtil.level2IndexFromRootPos(levelPoss[3]);
      Field level2 = mgv.level2(olKey, level2Index);
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        assertEq(
          TickTreeUtil.isBitSet(level2, levelPoss[2]),
          TickTreeUtil.isBitSet(level2s[level2Index], levelPoss[2]),
          string.concat("level2 bit mismatch, branch: ", branchToString(levelPoss, 2))
        );
        if (!TickTreeUtil.isBitSet(level2, levelPoss[2])) {
          continue;
        }

        int level1Index = TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]);
        Field level1 = mgv.level1(olKey, level1Index);
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          assertEq(
            TickTreeUtil.isBitSet(level1, levelPoss[1]),
            TickTreeUtil.isBitSet(level1s[level1Index], levelPoss[1]),
            string.concat("level1 bit mismatch, branch: ", branchToString(levelPoss, 1))
          );
          if (!TickTreeUtil.isBitSet(level1, levelPoss[1])) {
            continue;
          }

          int level0Index = TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]);
          Field level0 = mgv.level0(olKey, level0Index);
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            assertEq(
              TickTreeUtil.isBitSet(level0, levelPoss[0]),
              TickTreeUtil.isBitSet(level0s[level0Index], levelPoss[0]),
              string.concat("level0 bit mismatch, branch: ", branchToString(levelPoss, 0))
            );
            if (!TickTreeUtil.isBitSet(level0, levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel0IndexAndPos(level0Index, levelPoss[0]);
            Leaf leaf = mgv.leafs(olKey, leafIndex);
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              {
                TickTreeIndex tickTreeIndex = TickTreeUtil.tickTreeIndexFromLeafIndexAndPos(leafIndex, leafPos);
                assertEq(
                  leaf.firstOfPos(leafPos),
                  leafs[leafIndex].firstOfPos(leafPos),
                  string.concat("leaf first mismatch | tickTreeIndex: ", toString(tickTreeIndex))
                );
                assertEq(
                  leaf.lastOfPos(leafPos),
                  leafs[leafIndex].lastOfPos(leafPos),
                  string.concat("leaf last mismatch | tickTreeIndex: ", toString(tickTreeIndex))
                );
              }
              uint offerId = leaf.firstOfPos(leafPos);
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
                      " | tickTreeIndex tree ",
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
                      " | tickTreeIndex tree ",
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
  }

  function logTickTree() public view {
    Field root = local.root();
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(root, levelPoss[3])) {
        continue;
      }
      console.log("l3: %s", levelPoss[3]);

      int level2Index = TickTreeUtil.level2IndexFromRootPos(levelPoss[3]);
      Field level2 = level2s[level2Index];
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level2, levelPoss[2])) {
          continue;
        }
        console.log(
          "  l2: %s (index: %s)", levelPoss[2], vm.toString(TickTreeUtil.level2IndexFromRootPos(levelPoss[3]))
        );

        int level1Index = TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]);
        Field level1 = level1s[level1Index];
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level1, levelPoss[1])) {
            continue;
          }
          console.log(
            "    l1: %s (index: %s)",
            levelPoss[1],
            vm.toString(TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]))
          );

          int level0Index = TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]);
          Field level0 = level0s[level0Index];
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level0, levelPoss[0])) {
              continue;
            }
            console.log(
              "      l0: %s (index: %s)",
              levelPoss[0],
              vm.toString(TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]))
            );

            int leafIndex = TickTreeUtil.leafIndexFromLevel0IndexAndPos(level0Index, levelPoss[0]);
            Leaf leaf = leafs[leafIndex];
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              TickTreeIndex tickTreeIndex = TickTreeUtil.tickTreeIndexFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leaf.firstOfPos(leafPos);
              if (offerId == 0) {
                continue;
              }
              console.log(
                "        leaf: %s (index: %s) | tickTreeIndex: %s",
                leafPos,
                vm.toString(leafIndex),
                toString(tickTreeIndex)
              );
              do {
                console.log("          offer: %s", offerId);
                offerId = offers[offerId].offer.next();
              } while (offerId != 0);
            }
          }
        }
      }
    }
  }

  function best() public view returns (uint bestOfferId, TickTreeIndex bestTickTreeIndex) {
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(local.root(), levelPoss[3])) {
        continue;
      }

      int level2Index = TickTreeUtil.level2IndexFromRootPos(levelPoss[3]);
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level2s[level2Index], levelPoss[2])) {
          continue;
        }

        int level1Index = TickTreeUtil.level1IndexFromLevel2IndexAndPos(level2Index, levelPoss[2]);
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level1s[level1Index], levelPoss[1])) {
            continue;
          }

          int level0Index = TickTreeUtil.level0IndexFromLevel1IndexAndPos(level1Index, levelPoss[1]);
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level0s[level0Index], levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel0IndexAndPos(level0Index, levelPoss[0]);
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              TickTreeIndex tickTreeIndex = TickTreeUtil.tickTreeIndexFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leafs[leafIndex].firstOfPos(leafPos);
              if (offerId == 0) {
                continue;
              }
              return (offerId, tickTreeIndex);
            }
          }
        }
      }
    }
  }

  function branchToString(uint[4] memory levelPoss, uint toLevel) internal pure returns (string memory res) {
    res = vm.toString(levelPoss[3]);
    if (toLevel <= 2) {
      res = string.concat(res, "->", vm.toString(levelPoss[2]));
      if (toLevel <= 1) {
        res = string.concat(res, "->", vm.toString(levelPoss[1]));
        if (toLevel <= 0) {
          res = string.concat(res, "->", vm.toString(levelPoss[0]));
        }
      }
    }
  }

  function addOffer(uint offerId, TickTreeIndex tickTreeIndex, uint gives, uint gasreq, uint gasprice, address maker)
    public
  {
    // Update leaf and last offer
    Leaf leaf = leafs[tickTreeIndex.leafIndex()];
    // console.log("leaf before: %s", toString(leaf));
    uint lastId = leaf.lastOfPos(tickTreeIndex.posInLeaf());
    if (lastId == 0) {
      leaf = leaf.setPosFirstOrLast(tickTreeIndex.posInLeaf(), offerId, false);
    } else {
      offers[lastId].offer = offers[lastId].offer.next(offerId);
    }
    leafs[tickTreeIndex.leafIndex()] = leaf.setPosFirstOrLast(tickTreeIndex.posInLeaf(), offerId, true);
    // console.log("leaf after: %s", toString(leafs[tickTreeIndex.leafIndex()]));

    // Create offer
    int tick = TickLib.fromTickTreeIndex(tickTreeIndex, olKey.tickSpacing);
    offers[offerId].offer = MgvStructs.Offer.pack({__prev: lastId, __next: 0, __tick: tick, __gives: gives});
    offers[offerId].detail = MgvStructs.OfferDetail.pack({
      __maker: maker,
      __gasreq: gasreq,
      __kilo_offer_gasbase: local.offer_gasbase() / 1e3,
      __gasprice: gasprice
    });

    // Update levels
    local = local.root(TickTreeUtil.setBit(local.root(), tickTreeIndex.posInRoot()));
    // As an optimization, Mangrove only updates these for the part of the branch that is not best.
    // We don't do that here, as there's no reason for the complexity.
    level2s[tickTreeIndex.level2Index()] =
      TickTreeUtil.setBit(level2s[tickTreeIndex.level2Index()], tickTreeIndex.posInLevel2());
    level1s[tickTreeIndex.level1Index()] =
      TickTreeUtil.setBit(level1s[tickTreeIndex.level1Index()], tickTreeIndex.posInLevel1());
    level0s[tickTreeIndex.level0Index()] =
      TickTreeUtil.setBit(level0s[tickTreeIndex.level0Index()], tickTreeIndex.posInLevel0());

    // Update local
    updateLocalWithBestBranch();
  }

  function removeOffer(uint offerId) public {
    MgvCommon.OfferData storage offer = offers[offerId];
    TickTreeIndex tickTreeIndex = offer.offer.tickTreeIndex(olKey.tickSpacing);

    // Update leaf and tickTreeIndex list
    Leaf leaf = leafs[tickTreeIndex.leafIndex()];
    uint prevId = offer.offer.prev();
    uint nextId = offer.offer.next();
    if (prevId != 0) {
      offers[prevId].offer = offers[prevId].offer.next(nextId);
    } else {
      leaf = leaf.setPosFirstOrLast(tickTreeIndex.posInLeaf(), nextId, false);
    }
    if (nextId != 0) {
      offers[nextId].offer = offers[nextId].offer.prev(prevId);
    } else {
      leaf = leaf.setPosFirstOrLast(tickTreeIndex.posInLeaf(), prevId, true);
    }
    leafs[tickTreeIndex.leafIndex()] = leaf;

    // Update levels
    if (leaf.eq(LeafLib.EMPTY)) {
      level0s[tickTreeIndex.level0Index()] =
        TickTreeUtil.unsetBit(level0s[tickTreeIndex.level0Index()], tickTreeIndex.posInLevel0());
      if (level0s[tickTreeIndex.level0Index()].eq(FieldLib.EMPTY)) {
        level1s[tickTreeIndex.level1Index()] =
          TickTreeUtil.unsetBit(level1s[tickTreeIndex.level1Index()], tickTreeIndex.posInLevel1());
        if (level1s[tickTreeIndex.level1Index()].eq(FieldLib.EMPTY)) {
          level2s[tickTreeIndex.level2Index()] =
            TickTreeUtil.unsetBit(level2s[tickTreeIndex.level2Index()], tickTreeIndex.posInLevel2());
          if (level2s[tickTreeIndex.level2Index()].eq(FieldLib.EMPTY)) {
            local = local.root(TickTreeUtil.unsetBit(local.root(), tickTreeIndex.posInRoot()));
          }
        }
      }
    }

    // Update local
    updateLocalWithBestBranch();
  }

  function updateLocalWithBestBranch() internal {
    (, TickTreeIndex tickTreeIndex) = best();
    local = local.level2(level2s[tickTreeIndex.level2Index()]);
    local = local.level1(level1s[tickTreeIndex.level1Index()]);
    local = local.level0(level0s[tickTreeIndex.level0Index()]);
    local = local.tickTreeIndexPosInLeaf(tickTreeIndex.posInLeaf());
  }

  function addOffer(TickTreeIndex tickTreeIndex, uint gives, uint gasreq, uint gasprice, address maker) public {
    uint offerId = 1 + local.last();
    local = local.last(offerId);

    addOffer(offerId, tickTreeIndex, gives, gasreq, gasprice, maker);
  }

  function updateOffer(
    uint offerId,
    TickTreeIndex newTickTreeIndex,
    uint gives,
    uint gasreq,
    uint gasprice,
    address maker
  ) public {
    if (offers[offerId].offer.isLive()) {
      removeOffer(offerId);
    }
    addOffer(offerId, newTickTreeIndex, gives, gasreq, gasprice, maker);
  }
}
