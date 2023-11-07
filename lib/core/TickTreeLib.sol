// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "@mgv/lib/core/Constants.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {BitLib} from "@mgv/lib/core/BitLib.sol";
import {console2 as csf} from "@mgv/forge-std/console2.sol";
import {Local} from "@mgv/src/preprocessed/Local.post.sol";


/* # Libraries for tick tree manipulation 

Offers in Mangrove are structured in a tree so that offer insertion, removal, and update can happen in constant time.

The tree has the following structure: nodes at height 0, 1, 2 and 3 are bit fields (type `Field`) and nodes at height 4 (leaves) are arrays of pairs of offers (type `Leaf`).

- The root node is a 2-bit `Field` and has 2 child nodes.
- The nodes below are called `level1` nodes and are 64-bit `Field`s, with 64 child nodes each.
- The nodes below are called `level2` nodes and are 64-bit `Field`s with 64 child nodes each.
- The nodes below are called `level3` nodes and are 64-bit `Field`s with 64 child nodes each.
- The nodes below are called `leaf` nodes and are arrays of pairs of offers. Each pair of offers represents the first and last offer of a bin.
- Bins are linked lists of offers.

For each field, the i-th bit (starting from least significant) is set if there is at least one bin holding offers below the i-th child of the field. */


/* Globally enable `leaf.method(...)` */
type Leaf is uint;
using LeafLib for Leaf global;

/* Each `Leaf` holds information about 4 bins as follows: `[firstId,lastId] [firstId,lastId] [firstId,lastId] [firstId,lastId]`. For each bin `firstId` is used by `marketOrder` to start consuming offers in the bin (each offer contains a pointer to the next offer in the bin, until `lastId` is reacher). `lastId` is used when inserting offers in the bin: the newly inserted offer replaces the last offer.

Each `leaf` has an `index`: it is the number of leaves before it.
*/
library LeafLib {
  Leaf constant EMPTY = Leaf.wrap(uint(0));

  /* Checks if a leaf is dirty or not (see below for more on dirty leaves). */
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

  function isEmpty(Leaf leaf) internal pure returns (bool) {
    unchecked {
      return Leaf.unwrap(leaf) == Leaf.unwrap(EMPTY);
    }
  }

  /* `bool -> int` cast */
  function uint_of_bool(bool b) internal pure returns (uint u) {
    unchecked {
      assembly ("memory-safe") {
        u := b
      }
    }
  }

  /* Set either tick's first (at pos*size) or last (at pos*size + 1) */
  function setPosFirstOrLast(Leaf leaf, uint pos, uint id, bool last) internal pure returns (Leaf) {
    unchecked {
      uint before = OFFER_BITS * ((pos * 2) + uint_of_bool(last));

      uint cleanupMask = ~(OFFER_MASK << (256 - OFFER_BITS - before));

      uint shiftedId = id << (256 - OFFER_BITS - before);
      uint newLeaf = Leaf.unwrap(leaf) & cleanupMask | shiftedId;
      return Leaf.wrap(newLeaf);
    }
  }

  /* Assume `leaf` is the leaf of `bin`. Set the first offer of `bin` in leaf to `id`. */
  function setBinFirst(Leaf leaf, Bin bin, uint id) internal pure returns (Leaf) {
    unchecked {
      uint posInLeaf = bin.posInLeaf();
      return setPosFirstOrLast(leaf, posInLeaf, id, false);
    }
  }

  /* Assume `leaf` is the leaf of `bin`. Set the last offer of `bin` in leaf to `id`. */
  function setBinLast(Leaf leaf, Bin bin, uint id) internal pure returns (Leaf) {
    unchecked {
      uint posInLeaf = bin.posInLeaf();
      return setPosFirstOrLast(leaf, posInLeaf, id, true);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `leaf` is the leaf of `bin`. Erase contents of bins in `leaf` to (not including) `bin`. */
  function eraseBelow(Leaf leaf, Bin bin) internal pure returns (Leaf) {
    unchecked {
      uint mask = ONES >> ((bin.posInLeaf() + 1) * OFFER_BITS * 2);
      return Leaf.wrap(Leaf.unwrap(leaf) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `leaf` is the leaf of `bin`. Erase contents of bins in `leaf` from (not including) `bin`. */
  function eraseAbove(Leaf leaf, Bin bin) internal pure returns (Leaf) {
    unchecked {
      uint mask = ~(ONES >> (bin.posInLeaf() * OFFER_BITS * 2));
      return Leaf.wrap(Leaf.unwrap(leaf) & mask);
    }
  }


  // _This function is not used by Mangrove but is part of the library._
  /* Return the id of the first offer in `bin`, assuming `bin`'s leaf is `leaf`. */
  function firstOfBin(Leaf leaf, Bin bin) internal pure returns (uint) {
    unchecked {
      return firstOfPos(leaf, bin.posInLeaf());
    }
  }

  /* Return the id of the last offer in `bin`, assuming `bin`'s leaf is `leaf`. */
  function lastOfBin(Leaf leaf, Bin bin) internal pure returns (uint) {
    unchecked {
      return lastOfPos(leaf, bin.posInLeaf());
    }
  }

  /* Return first offer of pair in position `pos` */
  function firstOfPos(Leaf leaf, uint pos) internal pure returns (uint) {
    unchecked {
      uint raw = Leaf.unwrap(leaf);
      return uint(raw << (pos * OFFER_BITS * 2) >> (256 - OFFER_BITS));
    }
  }

  /* Return second offer of pair in position `pos` */
  function lastOfPos(Leaf leaf, uint pos) internal pure returns (uint) {
    unchecked {
      uint raw = Leaf.unwrap(leaf);
      return uint(raw << (OFFER_BITS * ((pos * 2) + 1)) >> (256 - OFFER_BITS));
    }
  }

  /* Return the position of the first pair of `leaf` (0, 1, 2 or 3) that has a nonzero offer.

  Explanation:
  Note that unlike in fields, have their low bin on the most significant bits.
  `pos` is initially 1 if `leaf` has some nonzero bit in its MSB half, 0 otherwise. Then `pos` is `A | B`, where `A` is `1<<iszero(ret)`, so `A` is 0 if leaf has some nonzero bit in its MSB half, 2 otherwise. And `B` is 0 if `leaf >> (pos << 7)` has some nonzero bit in its most significant 192 bits, 0 otherwise.
  */
  function bestNonEmptyBinPos(Leaf leaf) internal pure returns (uint pos) {
    assembly("memory-safe") {
      pos := gt(leaf,0xffffffffffffffffffffffffffffffff)
      pos := or(shl(1,iszero(pos)),iszero(gt(shr(shl(7,pos),leaf),0xffffffffffffffff)))
    }
  }

  /* Return the offer id of the first offer of the first non-empty pair in `leaf`. */
  function bestOfferId(Leaf leaf) internal pure returns (uint offerId) {
    unchecked {
      return firstOfPos(leaf,bestNonEmptyBinPos(leaf));
    }
  }
}


/* Bins are numbered from MIN_BIN to MAX_BIN (inclusive). Each bin contains the offers at a given price. For a given `tickSpacing`, bins represent the following prices (centered on the central bin): 
```
...
1.0001^-(tickSpacing*2)
1.0001^-(tickSpacing*1)
1.0001
1.0001^(tickSpacing*1)
1.0001^(tickSpacing*2)
...
``` 

There are 4 bins per leaf, `4 * 64` bins per level3, etc. The leaf of a bin is the leaf that holds its first/last offer id. The level3 of a bin is the level3 field above its leaf; the level2 of a bin is the level2 field above its level3, etc. */

/* Globally enable `bin.method(...)` */
type Bin is int;
using TickTreeLib for Bin global;

library TickTreeLib {

  function eq(Bin bin1, Bin bin2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(bin1) == Bin.unwrap(bin2);
    }
  }

  function inRange(Bin bin) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(bin) >= MIN_BIN && Bin.unwrap(bin) <= MAX_BIN;
    }
  }

  // _This function is not used by Mangrove but is part of the library for convenience._
  
  /* Not optimized for gas. Returns the bin induced by the branch formed by the arguments. Returned value will make no sense if any of the `Field` arguments are empty. */
  function bestBinFromBranch(uint binPosInLeaf,Field level3, Field level2, Field level1, Field root) internal pure returns (Bin) {
    unchecked {
      Local local;
      local = local.binPosInLeaf(binPosInLeaf).level3(level3).level2(level2).level1(level1).root(root);
      return bestBinFromLocal(local);
    }
  }

  /* Returns tick held by the `bin`, given a `tickSpacing`. */
  function tick(Bin bin, uint tickSpacing) internal pure returns (Tick) {
    return Tick.wrap(Bin.unwrap(bin) * int(tickSpacing));
  }

  /* Returns the bin induced by the branch held in `local`. Returned value will make no sense if any of the fields of `local` are empty. */
  function bestBinFromLocal(Local local) internal pure returns (Bin) {
    unchecked {
      uint ubin = local.binPosInLeaf() |
        ((BitLib.ctz64(Field.unwrap(local.level3())) |
          (BitLib.ctz64(Field.unwrap(local.level2())) |
            (BitLib.ctz64(Field.unwrap(local.level1())) |
              uint(
                (int(BitLib.ctz64(Field.unwrap(local.root())))-ROOT_SIZE/2) << LEVEL_SIZE_BITS)) 
              << LEVEL_SIZE_BITS)
            << LEVEL_SIZE_BITS)
          << LEAF_SIZE_BITS);
      return Bin.wrap(int(ubin));
    }
  }

  /* Returns the index of the leaf that holds `bin` */
  function leafIndex(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> LEAF_SIZE_BITS;
    }
  }

  /* Returns the position of `bin` in its leaf. */
  function posInLeaf(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(Bin.unwrap(bin)) & LEAF_SIZE_MASK;
    }
  }

  /* Returns the index of `bin`'s level3 */
  function level3Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + LEVEL_SIZE_BITS);
    }
  }

  /* Returns the position of `bin`'s leaf in `bin`'s level3 */
  function posInLevel3(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.leafIndex()) & LEVEL_SIZE_MASK;
    }
  }

  /* Returns the index of `bin`'s level2 */
  function level2Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + 2* LEVEL_SIZE_BITS);
    }
  }

  /* Returns the position of `bin`'s level3 in `bin`'s level2 */
  function posInLevel2(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level3Index()) & LEVEL_SIZE_MASK;
    }
  }

  /* Returns the index of `bin`'s level1 */
  function level1Index(Bin bin) internal pure returns (int) {
    unchecked {
      return Bin.unwrap(bin) >> (LEAF_SIZE_BITS + 3 * LEVEL_SIZE_BITS);
    }
  }

  /* Returns the position of `bin`'s level2 in `bin`'s level1 */
  function posInLevel1(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level2Index()) & LEVEL_SIZE_MASK;
    }
  }

  /* Returns the position of `bin`'s level1 in root */
  function posInRoot(Bin bin) internal pure returns (uint) {
    unchecked {
      return uint(bin.level1Index() + ROOT_SIZE / 2);
    }
  }

  /* `<`, typed for bin */
  function strictlyBetter(Bin bin1, Bin bin2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(bin1) < Bin.unwrap(bin2);
    }
  }

  /* `<=`, typed for bin */
  function better(Bin bin1, Bin bin2) internal pure returns (bool) {
    unchecked {
      return Bin.unwrap(bin1) <= Bin.unwrap(bin2);
    }
  }  

}

/* Globally enable `field.method(...)` */
type Field is uint;
using FieldLib for Field global;

/* Fields are bit fields. Each bit position of a field corresponds to a child of the node in the tick tree. The i-th bit of a field is set iff its child is the parent of at least one non-emtpy field.

Using bit fields market orders can locate the next bin containing an offer in constant time: once a leaf has been emptied, one must at most walk up along the branch of the current bin, up to the first 1 in a field, then go down to the of the tree, then go down the corresponding child to the nonempty bin found.
*/

/* In fields, positions are counted from the least significant bits */
library FieldLib {
  Field constant EMPTY = Field.wrap(uint(0));

  /* Checks if a field is dirty or not (see below for more on dirty fields). */
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

  function isEmpty(Field field) internal pure returns (bool) {
    unchecked {
      return Field.unwrap(field) == Field.unwrap(EMPTY);
    }
  }

  /* Flip the bit at the position of `bin`'s leaf */
  function flipBitAtLevel3(Field level3, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel3();
      level3 = Field.wrap(Field.unwrap(level3) ^ (1 << pos));
      return level3;
    }
  }

  /* Flip the bit at the position of `bin`'s level3 */
  function flipBitAtLevel2(Field level2, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel2();
      level2 = Field.wrap(Field.unwrap(level2) ^ (1 << pos));
      return level2;
    }
  }

  /* Flip the bit at the position of `bin`'s level2 */
  function flipBitAtLevel1(Field level1, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInLevel1();
      level1 = Field.wrap(Field.unwrap(level1) ^ (1 << pos));
      return level1;
    }
  }

  /* Flip the bit at the position of `bin`'s level1 */
  function flipBitAtRoot(Field root, Bin bin) internal pure returns (Field) {
    unchecked {
      uint pos = bin.posInRoot();
      root = Field.wrap(Field.unwrap(root) ^ (1 << pos));
      return root;
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level3 of `bin`. Erase contents of field up to (not including) bin. */
  function eraseBelowInLevel3(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel3() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level3 of `bin`. Erase contents of field from (not including) bin. */
  function eraseAboveInLevel3(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel3());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level2 of `bin`. Erase contents of field up to (not including) bin. */
  function eraseBelowInLevel2(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel2() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level2 of `bin`. Erase contents of field from (not including) bin. */
  function eraseAboveInLevel2(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel2());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level1 of `bin`. Erase contents of field up to (not including) bin. */
  function eraseBelowInLevel1(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInLevel1() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the level1 of `bin`. Erase contents of field from (not including) bin. */
  function eraseAboveInLevel1(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInLevel1());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the root of `bin`. Erase contents of field up to (not including) bin. */
  function eraseBelowInRoot(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ONES << (bin.posInRoot() + 1);
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._ 
  /* Assumes `field` is the root of `bin`. Erase contents of field from (not including) bin. */
  function eraseAboveInRoot(Field field, Bin bin) internal pure returns (Field) {
    unchecked {
      uint mask = ~(ONES << bin.posInRoot());
      return Field.wrap(Field.unwrap(field) & mask);
    }
  }

  /* Returns first nonzero position of `field`. Will return 64 if field is empty */
  function firstOnePosition(Field field) internal pure returns (uint) {
    unchecked {
      return BitLib.ctz64(Field.unwrap(field));
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._
  /* Returns last nonzero position of `field`. Will return 256 if field is empty */
  function lastOnePosition(Field field) internal pure returns (uint) {
    unchecked {
      return BitLib.fls(Field.unwrap(field));
    }
  }

  /* Return index of the first nonempty level1 below `root` (`root` should not be empty) */
  function firstLevel1Index(Field root) internal pure returns (int) {
    unchecked {
      return int(root.firstOnePosition()) - ROOT_SIZE / 2;
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._
  /* Return index of the last nonempty level1 below `root` (root should not be empty) */
  function lastLevel1Index(Field root) internal pure returns (int) {
    unchecked {
      return int(root.lastOnePosition()) - ROOT_SIZE / 2;
    }
  }

  /* Return index of the first nonempty level2 below `level1` assuming its index is `level1Index` (`level1` should not be empty). */
  function firstLevel2Index(Field level1, int level1Index) internal pure returns (int) {
    unchecked {
      return level1Index * LEVEL_SIZE + int(level1.firstOnePosition());
    }
  }
  // _This function is not used by Mangrove but is useful for MgvReader._
  /* Return index of the last nonempty level2 below `level1` assuming its index is `level1Index` (`level1` should not be empty). */
  function lastLevel2Index(Field level1, int level1Index) internal pure returns (int) {
    unchecked {
      return level1Index * LEVEL_SIZE + int(level1.lastOnePosition());
    }
  }

  /* Return index of the first nonempty level3 below `level2` assuming its index is `level2Index` (`level2` should not be empty). */
  function firstLevel3Index(Field level2, int level2Index) internal pure returns (int) {
    unchecked {
      return level2Index * LEVEL_SIZE + int(level2.firstOnePosition());
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._
  /* Return index of the last nonempty level3 below `level2` assuming its index is `level2Index` (`level2` should not be empty). */
  function lastLevel3Index(Field level2, int level2Index) internal pure returns (int) {
    unchecked {
      return level2Index * LEVEL_SIZE + int(level2.lastOnePosition());
    }
  }

  /* Return index of the first nonempty leaf below `level3` assuming its index is `level3Index` (`level3` should not be empty). */
  function firstLeafIndex(Field level3, int level3Index) internal pure returns (int) {
    unchecked {
      return level3Index * LEVEL_SIZE + int(level3.firstOnePosition());
    }
  }

  // _This function is not used by Mangrove but is useful for MgvReader._
  /* Return index of the last nonempty leaf below `level3` assuming its index is `level3Index` (`level3` should not be empty). */
  function lastLeafIndex(Field level3, int level3Index) internal pure returns (int) {
    unchecked {
      return level3Index * LEVEL_SIZE + int(level3.lastOnePosition());
    }
  }

 }

/* ## Clean/Dirty Fields and Leaves

To save gas, leaves and fields at never zeroed out but written with a dirty bit. This is especially helpful when the price oscillates quickly between two nodes.

Leaves don't have 'available bits' so an empty leaf is encoded as 1. This is not a valid leaf because for every offer pair in a leaf, either both are 0 (the bin is empty) or both are nonzero (they are the same if the bin has a single offer).
*/

/* Globally enable `dirtyLeaf.method(...)` */
type DirtyLeaf is uint;
using DirtyLeafLib for DirtyLeaf global;

library DirtyLeafLib {
  
  /* Return 0 if leaf is 1, leaf otherwise */
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

/* We use `TOPBIT` as the optimized in-storage value since 1 is a valid Field value */

/* For fields, it's simpler, since they do not use 64 bits we store the word with top bit at 1 and everything else at 0 to mark emptiness. */

/* Globally enable `dirtyField.method(...)` */
type DirtyField is uint;
using DirtyFieldLib for DirtyField global;

library DirtyFieldLib {
  DirtyField constant DIRTY_EMPTY = DirtyField.wrap(TOPBIT);
  DirtyField constant CLEAN_EMPTY = DirtyField.wrap(0);

  /* Return clean field with topbit set to 0 */
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

