// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {MangroveTest} from "@mgv/test/lib/MangroveTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import "@mgv/src/core/MgvLib.sol";
import {MgvCommon} from "@mgv/src/core/MgvCommon.sol";
import "@mgv/lib/Debug.sol";

int constant MIN_LEAF_INDEX = -NUM_LEAFS / 2;
int constant MAX_LEAF_INDEX = -MIN_LEAF_INDEX - 1;
int constant MIN_LEVEL3_INDEX = -NUM_LEVEL3 / 2;
int constant MAX_LEVEL3_INDEX = -MIN_LEVEL3_INDEX - 1;
int constant MIN_LEVEL2_INDEX = -NUM_LEVEL2 / 2;
int constant MAX_LEVEL2_INDEX = -MIN_LEVEL2_INDEX - 1;
int constant MIN_LEVEL1_INDEX = -NUM_LEVEL1 / 2;
int constant MAX_LEVEL1_INDEX = -MIN_LEVEL1_INDEX - 1;

uint constant MIN_LEAF_POS = 0;
uint constant MIN_LEVEL_POS = 0;
uint constant MIN_ROOT_POS = 0;

uint constant MAX_LEAF_POS = uint(LEAF_SIZE - 1);
uint constant MAX_LEVEL_POS = uint(LEVEL_SIZE - 1);
uint constant MAX_ROOT_POS = uint(ROOT_SIZE - 1);

uint constant MID_LEAF_POS = MAX_LEAF_POS / 2;
uint constant MID_LEVEL_POS = MAX_LEVEL_POS / 2;
uint constant MID_ROOT_POS = MAX_ROOT_POS / 2;

/* Since the tick range is slightly smaller than the bin range, those values are used to constraint the bins being used */
int constant MIN_BIN_ALLOWED = MIN_TICK;
int constant MAX_BIN_ALLOWED = MAX_TICK;

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

  function level1IndexFromRootPos(uint pos) public pure returns (int) {
    return int(pos) - ROOT_SIZE / 2;
  }

  function level2IndexFromLevel1IndexAndPos(int level1Index, uint pos) public pure returns (int) {
    return (level1Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function level3IndexFromLevel2IndexAndPos(int level2Index, uint pos) public pure returns (int) {
    return (level2Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function leafIndexFromLevel3IndexAndPos(int level3Index, uint pos) public pure returns (int) {
    return (level3Index << LEVEL_SIZE_BITS) | int(pos);
  }

  function binFromLeafIndexAndPos(int leafIndex, uint pos) public pure returns (Bin) {
    return Bin.wrap((leafIndex << LEAF_SIZE_BITS) | int(pos));
  }

  function binFromPositions(uint posInRoot, uint posInLevel1, uint posInLevel2, uint posInLevel3, uint posInLeaf)
    public
    pure
    returns (Bin)
  {
    unchecked {
      uint ubin = posInLeaf
        | (
          (
            posInLevel3
              | (posInLevel2 | (posInLevel1 | uint((int(posInRoot) - ROOT_SIZE / 2) << LEVEL_SIZE_BITS)) << LEVEL_SIZE_BITS)
                << LEVEL_SIZE_BITS
          ) << LEAF_SIZE_BITS
        );
      return Bin.wrap(int(ubin));
    }
  }
}

// Provides a simple tick tree data structure and operations on it that can be used to simulate Mangrove's tick tree
// and then be compared to the actual tick tree.
//
// See core/ticktree/README.md for more details on how this can be used.
//
// NB: Inheriting from MangroveTest to get assert functions.
contract TestTickTree is MangroveTest {
  Local public local;
  mapping(uint => MgvCommon.OfferData) public offers;
  mapping(int => Leaf) public leafs;
  mapping(int => Field) public level3s;
  mapping(int => Field) public level2s;
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
    local = mgv.local(olKey);
    Field root = mgv.root(olKey);
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(root, levelPoss[3])) {
        continue;
      }

      int level1Index = TickTreeUtil.level1IndexFromRootPos(levelPoss[3]);
      Field level1 = mgv.level1s(olKey, level1Index);
      level1s[level1Index] = level1;
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level1, levelPoss[2])) {
          continue;
        }

        int level2Index = TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]);
        Field level2 = mgv.level2s(olKey, level2Index);
        level2s[level2Index] = level2;
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level2, levelPoss[1])) {
            continue;
          }

          int level3Index = TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]);
          Field level3 = mgv.level3s(olKey, level3Index);
          level3s[level3Index] = level3;
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level3, levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel3IndexAndPos(level3Index, levelPoss[0]);
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

  // Checks that the current Mangrove tick tree in olKey is consistent
  function assertMgvTickTreeIsConsistent() public {
    Field root = mgv.root(olKey);
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      bool rootPosIsSet = TickTreeUtil.isBitSet(root, levelPoss[3]);
      int level1Index = TickTreeUtil.level1IndexFromRootPos(levelPoss[3]);
      Field level1 = mgv.level1s(olKey, level1Index);

      if (!rootPosIsSet) {
        assertTrue(
          level1.eq(FieldLib.EMPTY),
          string.concat(
            "level1 should be empty when bit is not set in root | tree branch: ", branchToString(levelPoss, 3)
          )
        );
        // checking that the entire subtree is empty is too expensive, so we stop here
        continue;
      }
      assertTrue(
        !level1.eq(FieldLib.EMPTY),
        string.concat(
          "level1 should not be empty when bit is set in root | tree branch: ", branchToString(levelPoss, 3)
        )
      );

      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        bool level1PosIsSet = TickTreeUtil.isBitSet(level1, levelPoss[2]);
        int level2Index = TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]);
        Field level2 = mgv.level2s(olKey, level2Index);

        if (!level1PosIsSet) {
          assertTrue(
            level1.eq(FieldLib.EMPTY),
            string.concat(
              "level2 should be empty when bit is not set in level1 | tree branch: ", branchToString(levelPoss, 2)
            )
          );
          // checking that the entire subtree is empty is too expensive, so we stop here
          continue;
        }
        assertTrue(
          !level2.eq(FieldLib.EMPTY),
          string.concat(
            "level2 should not be empty when bit is set in level1 | tree branch: ",
            vm.toString(levelPoss[3]),
            "->",
            vm.toString(levelPoss[2])
          )
        );

        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          bool level2PosIsSet = TickTreeUtil.isBitSet(level2, levelPoss[1]);
          int level3Index = TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]);
          Field level3 = mgv.level3s(olKey, level3Index);

          if (!level2PosIsSet) {
            assertTrue(
              level3.eq(FieldLib.EMPTY),
              string.concat(
                "level3 should be empty when bit is not set in level2 | tree branch: ", branchToString(levelPoss, 1)
              )
            );
            // checking that the entire subtree is empty is too expensive, so we stop here
            continue;
          }
          assertTrue(
            !level3.eq(FieldLib.EMPTY),
            string.concat(
              "level3 should not be empty when bit is set in level2 | tree branch: ", branchToString(levelPoss, 1)
            )
          );

          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            bool level3PosIsSet = TickTreeUtil.isBitSet(level3, levelPoss[0]);
            int leafIndex = TickTreeUtil.leafIndexFromLevel3IndexAndPos(level3Index, levelPoss[0]);
            Leaf leaf = mgv.leafs(olKey, leafIndex);

            if (!level3PosIsSet) {
              assertTrue(
                leaf.eq(LeafLib.EMPTY),
                string.concat(
                  "leaf should be empty when bit is not set in level3 | tree branch: ", branchToString(levelPoss, 0)
                )
              );
              // checking that the entire subtree is empty is too expensive, so we stop here
              continue;
            }
            assertTrue(
              !level3PosIsSet || !leaf.eq(LeafLib.EMPTY),
              string.concat(
                "leaf should not be empty when bit is set in level3 | tree branch: ", branchToString(levelPoss, 0)
              )
            );

            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              Bin bin = TickTreeUtil.binFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leaf.firstOfPos(leafPos);
              if (offerId == 0) {
                assertEq(
                  leaf.lastOfPos(leafPos),
                  0,
                  string.concat("last offer should be 0 when first is 0 | bin: ", toString(bin))
                );
                continue;
              }
              uint prev = 0;
              do {
                Offer offer = mgv.offers(olKey, offerId);
                assertEq(
                  offer.bin(olKey.tickSpacing),
                  bin,
                  string.concat(
                    "offer[", vm.toString(offerId), "] bin does not match location in tick tree | bin: ", toString(bin)
                  )
                );
                assertEq(
                  offer.prev(),
                  prev,
                  string.concat(
                    "offer[",
                    vm.toString(offerId),
                    "].prev does point to previous offer in bin list | bin: ",
                    toString(bin)
                  )
                );
                assertTrue(
                  offer.isLive(),
                  string.concat("offer[", vm.toString(offerId), "] in tick tree should be live | bin: ", toString(bin))
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
                  "] in bin does not match last offer[",
                  vm.toString(prev),
                  "] in bin list | bin: ",
                  toString(bin)
                )
              );
            }
          }
        }
      }
    }
  }

  // Checks that the current Mangrove tick tree in olKey is equal to the tick tree passed as argument
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

      int level1Index = TickTreeUtil.level1IndexFromRootPos(levelPoss[3]);
      Field level1 = mgv.level1s(olKey, level1Index);
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        assertEq(
          TickTreeUtil.isBitSet(level1, levelPoss[2]),
          TickTreeUtil.isBitSet(level1s[level1Index], levelPoss[2]),
          string.concat("level1 bit mismatch, branch: ", branchToString(levelPoss, 2))
        );
        if (!TickTreeUtil.isBitSet(level1, levelPoss[2])) {
          continue;
        }

        int level2Index = TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]);
        Field level2 = mgv.level2s(olKey, level2Index);
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          assertEq(
            TickTreeUtil.isBitSet(level2, levelPoss[1]),
            TickTreeUtil.isBitSet(level2s[level2Index], levelPoss[1]),
            string.concat("level2 bit mismatch, branch: ", branchToString(levelPoss, 1))
          );
          if (!TickTreeUtil.isBitSet(level2, levelPoss[1])) {
            continue;
          }

          int level3Index = TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]);
          Field level3 = mgv.level3s(olKey, level3Index);
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            assertEq(
              TickTreeUtil.isBitSet(level3, levelPoss[0]),
              TickTreeUtil.isBitSet(level3s[level3Index], levelPoss[0]),
              string.concat("level3 bit mismatch, branch: ", branchToString(levelPoss, 0))
            );
            if (!TickTreeUtil.isBitSet(level3, levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel3IndexAndPos(level3Index, levelPoss[0]);
            Leaf leaf = mgv.leafs(olKey, leafIndex);
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              {
                Bin bin = TickTreeUtil.binFromLeafIndexAndPos(leafIndex, leafPos);
                assertEq(
                  leaf.firstOfPos(leafPos),
                  leafs[leafIndex].firstOfPos(leafPos),
                  string.concat("leaf first mismatch | bin: ", toString(bin))
                );
                assertEq(
                  leaf.lastOfPos(leafPos),
                  leafs[leafIndex].lastOfPos(leafPos),
                  string.concat("leaf last mismatch | bin: ", toString(bin))
                );
              }
              uint offerId = leaf.firstOfPos(leafPos);
              while (offerId != 0) {
                {
                  Offer offer = mgv.offers(olKey, offerId);
                  Offer offerTickTree = offers[offerId].offer;
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
                  OfferDetail detail = mgv.offerDetails(olKey, offerId);
                  OfferDetail detailTickTree = offers[offerId].detail;
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
  }

  function logTickTree() public view {
    Field root = local.root();
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(root, levelPoss[3])) {
        continue;
      }
      console.log("l3: %s", levelPoss[3]);

      int level1Index = TickTreeUtil.level1IndexFromRootPos(levelPoss[3]);
      Field level1 = level1s[level1Index];
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level1, levelPoss[2])) {
          continue;
        }
        console.log(
          "  l2: %s (index: %s)", levelPoss[2], vm.toString(TickTreeUtil.level1IndexFromRootPos(levelPoss[3]))
        );

        int level2Index = TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]);
        Field level2 = level2s[level2Index];
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level2, levelPoss[1])) {
            continue;
          }
          console.log(
            "    l1: %s (index: %s)",
            levelPoss[1],
            vm.toString(TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]))
          );

          int level3Index = TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]);
          Field level3 = level3s[level3Index];
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level3, levelPoss[0])) {
              continue;
            }
            console.log(
              "      l0: %s (index: %s)",
              levelPoss[0],
              vm.toString(TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]))
            );

            int leafIndex = TickTreeUtil.leafIndexFromLevel3IndexAndPos(level3Index, levelPoss[0]);
            Leaf leaf = leafs[leafIndex];
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              Bin bin = TickTreeUtil.binFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leaf.firstOfPos(leafPos);
              if (offerId == 0) {
                continue;
              }
              console.log("        leaf: %s (index: %s) | bin: %s", leafPos, vm.toString(leafIndex), toString(bin));
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

  function best() public view returns (uint bestOfferId, Bin bestBin) {
    uint[4] memory levelPoss;
    for (levelPoss[3] = 0; levelPoss[3] <= MAX_ROOT_POS; ++levelPoss[3]) {
      if (!TickTreeUtil.isBitSet(local.root(), levelPoss[3])) {
        continue;
      }

      int level1Index = TickTreeUtil.level1IndexFromRootPos(levelPoss[3]);
      for (levelPoss[2] = 0; levelPoss[2] <= MAX_LEVEL_POS; ++levelPoss[2]) {
        if (!TickTreeUtil.isBitSet(level1s[level1Index], levelPoss[2])) {
          continue;
        }

        int level2Index = TickTreeUtil.level2IndexFromLevel1IndexAndPos(level1Index, levelPoss[2]);
        for (levelPoss[1] = 0; levelPoss[1] <= MAX_LEVEL_POS; ++levelPoss[1]) {
          if (!TickTreeUtil.isBitSet(level2s[level2Index], levelPoss[1])) {
            continue;
          }

          int level3Index = TickTreeUtil.level3IndexFromLevel2IndexAndPos(level2Index, levelPoss[1]);
          for (levelPoss[0] = 0; levelPoss[0] <= MAX_LEVEL_POS; ++levelPoss[0]) {
            if (!TickTreeUtil.isBitSet(level3s[level3Index], levelPoss[0])) {
              continue;
            }

            int leafIndex = TickTreeUtil.leafIndexFromLevel3IndexAndPos(level3Index, levelPoss[0]);
            for (uint leafPos = 0; leafPos <= MAX_LEAF_POS; ++leafPos) {
              Bin bin = TickTreeUtil.binFromLeafIndexAndPos(leafIndex, leafPos);
              uint offerId = leafs[leafIndex].firstOfPos(leafPos);
              if (offerId == 0) {
                continue;
              }
              return (offerId, bin);
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

  function addOffer(uint offerId, Bin bin, uint gives, uint gasreq, uint gasprice, address maker) public {
    // Update leaf and last offer
    Leaf leaf = leafs[bin.leafIndex()];
    // console.log("leaf before: %s", toString(leaf));
    uint lastId = leaf.lastOfPos(bin.posInLeaf());
    if (lastId == 0) {
      leaf = leaf.setPosFirstOrLast(bin.posInLeaf(), offerId, false);
    } else {
      offers[lastId].offer = offers[lastId].offer.next(offerId);
    }
    leafs[bin.leafIndex()] = leaf.setPosFirstOrLast(bin.posInLeaf(), offerId, true);
    // console.log("leaf after: %s", toString(leafs[bin.leafIndex()]));

    // Create offer
    Tick tick = bin.tick(olKey.tickSpacing);
    offers[offerId].offer = OfferLib.pack({__prev: lastId, __next: 0, __tick: tick, __gives: gives});
    offers[offerId].detail = OfferDetailLib.pack({
      __maker: maker,
      __gasreq: gasreq,
      __kilo_offer_gasbase: local.offer_gasbase() / 1e3,
      __gasprice: gasprice
    });

    // Update levels
    local = local.root(TickTreeUtil.setBit(local.root(), bin.posInRoot()));
    // As an optimization, Mangrove only updates these for the part of the branch that is not best.
    // We don't do that here, as there's no reason for the complexity.
    level1s[bin.level1Index()] = TickTreeUtil.setBit(level1s[bin.level1Index()], bin.posInLevel1());
    level2s[bin.level2Index()] = TickTreeUtil.setBit(level2s[bin.level2Index()], bin.posInLevel2());
    level3s[bin.level3Index()] = TickTreeUtil.setBit(level3s[bin.level3Index()], bin.posInLevel3());

    // Update local
    updateLocalWithBestBranch();
  }

  function removeOffer(uint offerId) public {
    MgvCommon.OfferData storage offer = offers[offerId];
    Bin bin = offer.offer.bin(olKey.tickSpacing);

    // Update leaf and bin list
    Leaf leaf = leafs[bin.leafIndex()];
    uint prevId = offer.offer.prev();
    uint nextId = offer.offer.next();
    if (prevId != 0) {
      offers[prevId].offer = offers[prevId].offer.next(nextId);
    } else {
      leaf = leaf.setPosFirstOrLast(bin.posInLeaf(), nextId, false);
    }
    if (nextId != 0) {
      offers[nextId].offer = offers[nextId].offer.prev(prevId);
    } else {
      leaf = leaf.setPosFirstOrLast(bin.posInLeaf(), prevId, true);
    }
    leafs[bin.leafIndex()] = leaf;

    // Update levels
    if (leaf.eq(LeafLib.EMPTY)) {
      level3s[bin.level3Index()] = TickTreeUtil.unsetBit(level3s[bin.level3Index()], bin.posInLevel3());
      if (level3s[bin.level3Index()].eq(FieldLib.EMPTY)) {
        level2s[bin.level2Index()] = TickTreeUtil.unsetBit(level2s[bin.level2Index()], bin.posInLevel2());
        if (level2s[bin.level2Index()].eq(FieldLib.EMPTY)) {
          level1s[bin.level1Index()] = TickTreeUtil.unsetBit(level1s[bin.level1Index()], bin.posInLevel1());
          if (level1s[bin.level1Index()].eq(FieldLib.EMPTY)) {
            local = local.root(TickTreeUtil.unsetBit(local.root(), bin.posInRoot()));
          }
        }
      }
    }

    // Update local
    updateLocalWithBestBranch();
  }

  function updateLocalWithBestBranch() internal {
    (, Bin bin) = best();
    local = local.level1(level1s[bin.level1Index()]);
    local = local.level2(level2s[bin.level2Index()]);
    local = local.level3(level3s[bin.level3Index()]);
    local = local.binPosInLeaf(bin.posInLeaf());
  }

  function addOffer(Bin bin, uint gives, uint gasreq, uint gasprice, address maker) public {
    uint offerId = 1 + local.last();
    local = local.last(offerId);

    addOffer(offerId, bin, gives, gasreq, gasprice, maker);
  }

  function updateOffer(uint offerId, Bin newBin, uint gives, uint gasreq, uint gasprice, address maker) public {
    if (offers[offerId].offer.isLive()) {
      removeOffer(offerId);
    }
    addOffer(offerId, newBin, gives, gasreq, gasprice, maker);
  }
}
