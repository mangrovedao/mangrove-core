// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "mgv_lib/Constants.sol";
import {BitLib} from "mgv_lib/BitLib.sol";
import {console2 as csf} from "forge-std/console2.sol";
import {LocalPacked} from "mgv_src/preprocessed/MgvLocal.post.sol";

type Leaf is uint;
type DirtyLeaf is uint;

using LeafLib for Leaf global;
using DirtyLeafLib for DirtyLeaf global;

type Field is uint;
type DirtyField is uint;

using FieldLib for Field global;
using DirtyFieldLib for DirtyField global;

type Bin is int;

using BinLib for Bin global;

// Leafs are of the ford [id,id][id,id][id,id][id,id]
// With the property that within a [id1,id2] pair, id1==0 iff id2==0
// So 1 is not a valid leaf
// We use that (for storage gas savings) yet the field is still considered empty
// 1 is chosen as a special invalid leaf value to make dirty/clean more gas efficient
library DirtyLeafLib {
  // Return 0 if leaf is 1, leaf otherwise
  function clean(DirtyLeaf leaf) internal pure returns (Leaf) {
    unchecked {
      assembly ("memory-safe") {
        leaf := xor(eq(leaf,ONE),leaf)
      }
      return Leaf.wrap(DirtyLeaf.unwrap(leaf));
    }
  }
  function isDirty(DirtyLeaf leaf) internal pure returns (bool) {
    unchecked {
      return DirtyLeaf.unwrap(leaf) == ONE;
    }
  }
  function eq(DirtyLeaf leaf1, DirtyLeaf leaf2) internal pure returns (bool) {
    unchecked {
      return DirtyLeaf.unwrap(leaf1) == DirtyLeaf.unwrap(leaf2);
    }
  }
}

library LeafLib {
  Leaf constant EMPTY = Leaf.wrap(uint(0));

  // Return 1 if leaf is 0, leaf otherwise
  function dirty(Leaf leaf) internal pure returns (DirtyLeaf) {
    unchecked {
      assembly ("memory-safe") {
        leaf := or(iszero(leaf),leaf)
      }
      return DirtyLeaf.wrap(Leaf.unwrap(leaf));
    }
  }

  function eq(Leaf leaf1, Leaf leaf2) internal pure returns (bool) {
    unchecked {
      return Leaf.unwrap(leaf1) == Leaf.unwrap(leaf2);
    }
  }

  // Does not accept 1 as an empty value
  function isEmpty(Leaf leaf) internal pure returns (bool) {
    unchecked {
      return Leaf.unwrap(leaf) == Leaf.unwrap(EMPTY);
    }
  }

  function uint_of_bool(bool b) internal pure returns (uint u) {
    unchecked {
      assembly {
        u := b
      }
    }
  }

  // Set either tick's first (at pos*size) or last (at pos*size + 1)
  function setPosFirstOrLast(Leaf leaf, uint pos, uint id, bool last) internal pure returns (Leaf) {
    unchecked {
      uint before = OFFER_BITS * ((pos * 2) + uint_of_bool(last));

      // cleanup necessary?
      uint cleanupMask = ~(OFFER_MASK << (256 - OFFER_BITS - before));

      uint shiftedId = id << (256 - OFFER_BITS - before);
      uint newLeaf = Leaf.unwrap(leaf) & cleanupMask | shiftedId;
      return Leaf.wrap(newLeaf);
    }
  }

  function setBinFirst(Leaf leaf, Bin bin, uint id) internal pure returns (Leaf) {
    unchecked {
      uint posInLeaf = BinLib.posInLeaf(bin);
      return setPosFirstOrLast(leaf, posInLeaf, id, false);
    }
  }

  function setBinLast(Leaf leaf, Bin bin, uint id) internal pure returns (Leaf) {
    unchecked {
      uint posInLeaf = BinLib.posInLeaf(bin);
      return setPosFirstOrLast(leaf, posInLeaf, id, true);
    }
  }

  // useful for quickly accessing the next bin even when the current offer is not the best
  // not for onchain use
  function eraseToBin(Leaf leaf, Bin bin) internal pure returns (Leaf) {
    unchecked {
      uint mask = ONES >> ((bin.posInLeaf() + 1) * OFFER_BITS * 2);
      return Leaf.wrap(Leaf.unwrap(leaf) & mask);
    }
  }

  function eraseFromBin(Leaf leaf, Bin bin) internal pure returns (Leaf) {
    unchecked {
      uint mask = ~(ONES >> (bin.posInLeaf() * OFFER_BITS * 2));
      return Leaf.wrap(Leaf.unwrap(leaf) & mask);
    }
  }

  function firstOfBin(Leaf leaf, Bin bin) internal pure returns (uint) {
    unchecked {
      return firstOfPos(leaf, BinLib.posInLeaf(bin));
    }
  }

  function lastOfBin(Leaf leaf, Bin bin) internal pure returns (uint) {
    unchecked {
      return lastOfPos(leaf, BinLib.posInLeaf(bin));
    }
  }

  function firstOfPos(Leaf leaf, uint pos) internal pure returns (uint) {
    unchecked {
      uint raw = Leaf.unwrap(leaf);
      return uint(raw << (pos * OFFER_BITS * 2) >> (256 - OFFER_BITS));
    }
  }

  function lastOfPos(Leaf leaf, uint pos) internal pure returns (uint) {
    unchecked {
      uint raw = Leaf.unwrap(leaf);
      return uint(raw << (OFFER_BITS * ((pos * 2) + 1)) >> (256 - OFFER_BITS));
    }
  }

  // Will check for the first position (0,1,2 or 3) that has a nonzero first-of-bin or a nonzero last-of-bin offer. Leafs where only one of those is nonzero are invalid anyway.
  // Offers are ordered msb to lsb
  function firstOfferPosition(Leaf leaf) internal pure returns (uint ret) {
    assembly("memory-safe") {
      ret := gt(leaf,0xffffffffffffffffffffffffffffffff)
      ret := or(shl(1,iszero(ret)),iszero(gt(shr(shl(7,ret),leaf),0xffffffffffffffff)))
    }
  }

  function getNextOfferId(Leaf leaf) internal pure returns (uint offerId) {
    unchecked {
      return firstOfPos(leaf,firstOfferPosition(leaf));
    }
  }
}


library BinLib {

  function eq(Bin tick1, Bin tick2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(tick1) == Bin.unwrap(tick2);
    }
  }

  function inRange(Bin bin) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(bin) >= MIN_BIN && Bin.unwrap(bin) <= MAX_BIN;
    }
  }

  // Returns the nearest, higher bin to the given tick at the given tickSpacing
  function nearestHigherTickToTick(int tick, uint tickSpacing) internal pure returns (Bin) {
    unchecked {
      // Do not force ticks to fit the tickSpacing (aka tick%tickSpacing==0)
      // Round maker ratios up such that maker is always paid at least what they asked for
      int bin = tick / int(tickSpacing);
      if (tick > 0 && tick % int(tickSpacing) != 0) {
        bin = bin + 1;
      }
      return Bin.wrap(bin);
    }
  }

  // Optimized conversion for ticks that are known to map exactly to a bin at the given tickSpacing,
  // eg for offers in the offer list which are always written with a tick-aligned tick
  function fromBinAlignedTick(int tick, uint tickSpacing) internal pure returns (Bin) {
    return Bin.wrap(tick / int(tickSpacing));
  }

  // Utility for tests&unpacked structs, less gas-optimal
  // Must not be called with any of level2, level1, level0 or root empty
  function bestBinFromBranch(uint binPosInLeaf,Field level2, Field level1, Field level0, Field root) internal pure returns (Bin) {
    unchecked {
      LocalPacked local;
      local = local.binPosInLeaf(binPosInLeaf).level2(level2).level1(level1).level0(level0).root(root);
      return bestBinFromLocal(local);
    }
  }

  function bestBinFromLocal(LocalPacked local) internal pure returns (Bin) {
    unchecked {
      uint ubin = local.binPosInLeaf() |
        ((BitLib.ctz64(Field.unwrap(local.level2())) |
          (BitLib.ctz64(Field.unwrap(local.level1())) |
            (BitLib.ctz64(Field.unwrap(local.level0())) |
              uint(
                (int(BitLib.ctz64(Field.unwrap(local.root())))-ROOT_SIZE/2) << LEVEL_SIZE_BITS)) 
              << LEVEL_SIZE_BITS)
            << LEVEL_SIZE_BITS)
          << LEAF_SIZE_BITS);
      return Bin.wrap(int(ubin));
    }
  }

  // I could revert to indices being uints if I do (+ BIG_NUMBER) systematically,
  // then / something. More gas costly (a little) but
  // a) clearer
  // b) allows non-power-of-two sizes for "offers_per_leaf"
  function leafIndex(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> LEAF_SIZE_BITS;
    }
  }

  // ok because 2^BIN_BITS%BINS_PER_LEAF=0
  // note "posIn*"
  // could instead write uint(bin) / a % b
  // but it's less explicit why it works:
  // works because sizes are powers of two, otherwise will have to do
  // tick+(MIN_OFFER/BINS_PER_LEAF * BINS_PER_LEAF), so that we are in positive range and have not changed modulo BINS_PER_LEAF
  // otherwise if you mod negative numbers you get signed modulo defined as
  // a%b = sign(a) abs(a)%abs(b), e.g. -1%6=-1 when we would like -1%6=5
  // I could also do like uintX(intX(a%x)) but the method below means I don't need to edit all the code when I change mask sizes
  function posInLeaf(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(Bin.unwrap(bin)) & LEAF_SIZE_MASK;
    }
  }

  function level2Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + LEVEL_SIZE_BITS);
    }
  }

  // see note posIn*
  function posInLevel2(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.leafIndex()) & LEVEL_SIZE_MASK;
    }
  }

  function level1Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + 2* LEVEL_SIZE_BITS);
    }
  }

  function level0Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + 3 * LEVEL_SIZE_BITS);
    }
  }

  // see note posIn*
  function posInLevel1(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level2Index()) & LEVEL_SIZE_MASK;
    }
  }

  function posInLevel0(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level1Index()) & LEVEL_SIZE_MASK;
    }
  }

  // see note posIn*
  // note with int24 bin we only use 2 bits in root
  //   level 3 single node
  // <--------------------->
  //  1                  0
  //  ^initial level0
  // so we can immediately add 32 to that
  // and there is no need to take a modulo
  function posInRoot(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level0Index() + ROOT_SIZE / 2);
    }
  }

  function strictlyBetter(Bin tick1, Bin tick2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(tick1) < Bin.unwrap(tick2);
    }
  }

  function better(Bin tick1, Bin tick2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(tick1) <= Bin.unwrap(tick2);
    }
  }  

}


// We use TOPBIT as the optimized in-storage value since 1 is a valid Field value
library DirtyFieldLib {
  DirtyField constant DIRTY_EMPTY = DirtyField.wrap(TOPBIT);
  DirtyField constant CLEAN_EMPTY = DirtyField.wrap(0);

  // Return clean field with topbit set to 0
  function clean(DirtyField field) internal pure returns (Field) {
    unchecked {
      assembly ("memory-safe") {
        field := and(NOT_TOPBIT,field)
      }
      return Field.wrap(DirtyField.unwrap(field));
    }
  }
  function isDirty(DirtyField field) internal pure returns (bool) {
    unchecked {
      return DirtyField.unwrap(field) & TOPBIT == TOPBIT;
    }
  }

  function eq(DirtyField leaf1, DirtyField leaf2) internal pure returns (bool) {
    unchecked {
      return DirtyField.unwrap(leaf1) == DirtyField.unwrap(leaf2);
    }
  }
}

// In fields, positions are counted from the right
library FieldLib {
  Field constant EMPTY = Field.wrap(uint(0));

  // Return clean field with topbit set to 1
  function dirty(Field field) internal pure returns (DirtyField) {
    unchecked {
      assembly ("memory-safe") {
        field := or(TOPBIT,field)
      }
      return DirtyField.wrap(Field.unwrap(field));
    }
  }

  function eq(Field field1, Field field2) internal pure returns (bool) {
    unchecked {
      return Field.unwrap(field1) == Field.unwrap(field2);
    }
  }

  // Does not accept TOPBIT as an empty value
  function isEmpty(Field field) internal pure returns (bool) {
    unchecked {
      return Field.unwrap(field) == Field.unwrap(EMPTY);
    }
  }

  function flipBitAtLevel2(Field level2, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel2();
      level2 = Field.wrap(Field.unwrap(level2) ^ (1 << pos));
      return level2;
    }
  }

  function flipBitAtLevel1(Field level1, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel1();
      level1 = Field.wrap(Field.unwrap(level1) ^ (1 << pos));
      return level1;
    }
  }

  function flipBitAtLevel0(Field level0, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel0();
      level0 = Field.wrap(Field.unwrap(level0) ^ (1 << pos));
      return level0;
    }
  }

  function flipBitAtRoot(Field root, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInRoot();
      root = Field.wrap(Field.unwrap(root) ^ (1 << pos));
      return root;
    }
  }

  // utility fn
  function eraseToBin0(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel2() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  function eraseFromBin0(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel2());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // utility fn
  function eraseToBin1(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel1() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  function eraseFromBin1(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel1());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // utility fn
  function eraseToBin2(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel0() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  function eraseFromBin2(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel0());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // utility fn
  function eraseToBin3(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInRoot() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  function eraseFromBin3(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInRoot());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // Will return 64 if field is empty
  function firstOnePosition(Field field) internal pure returns (uint) {
    unchecked {
      return BitLib.ctz64(Field.unwrap(field));
    }
  }

  // Will return 64 if field is empty
  function lastOnePosition(Field field) internal pure returns (uint) {
    unchecked {
      return BitLib.fls(Field.unwrap(field));
    }
  }

  // Get the index of the first level(i) of a level(i+1)
  function firstLevel0Index(Field root) internal pure returns (int) {
    unchecked {
      return int(root.firstOnePosition()) - ROOT_SIZE / 2;
    }
  }
  function lastLevel0Index(Field root) internal pure returns (int) {
    unchecked {
      return int(root.lastOnePosition()) - ROOT_SIZE / 2;
    }
  }
  function firstLevel1Index(Field level0, int level0Index) internal pure returns (int) {
    unchecked {
      return level0Index * LEVEL_SIZE + int(level0.firstOnePosition());
    }
  }
  function lastLevel1Index(Field level0, int level0Index) internal pure returns (int) {
    unchecked {
      return level0Index * LEVEL_SIZE + int(level0.lastOnePosition());
    }
  }
  function firstLevel2Index(Field level1, int level1Index) internal pure returns (int) {
    unchecked {
      return level1Index * LEVEL_SIZE + int(level1.firstOnePosition());
    }
  }
  function lastLevel2Index(Field level1, int level1Index) internal pure returns (int) {
    unchecked {
      return level1Index * LEVEL_SIZE + int(level1.lastOnePosition());
    }
  }
  function firstLeafIndex(Field level2, int level2Index) internal pure returns (int) {
    unchecked {
      return level2Index * LEVEL_SIZE + int(level2.firstOnePosition());
    }
  }
  function lastLeafIndex(Field level2, int level2Index) internal pure returns (int) {
    unchecked {
      return level2Index * LEVEL_SIZE + int(level2.lastOnePosition());
    }
  }

 }
