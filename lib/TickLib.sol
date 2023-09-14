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

type Tick is int;

using TickLib for Tick global;

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
    return Leaf.unwrap(leaf1) == Leaf.unwrap(leaf2);
  }

  // Does not accept 1 as an empty value
  function isEmpty(Leaf leaf) internal pure returns (bool) {
    return Leaf.unwrap(leaf) == Leaf.unwrap(EMPTY);
  }

  function uint_of_bool(bool b) internal pure returns (uint u) {
    assembly {
      u := b
    }
  }

  // Set either tick's first (at index*size) or last (at index*size + 1)
  function setIndexFirstOrLast(Leaf leaf, uint index, uint id, bool last) internal pure returns (Leaf) {
    uint before = OFFER_BITS * ((index * 2) + uint_of_bool(last));

    // cleanup necessary?
    uint cleanupMask = ~(OFFER_MASK << (256 - OFFER_BITS - before));

    uint shiftedId = id << (256 - OFFER_BITS - before);
    uint newLeaf = Leaf.unwrap(leaf) & cleanupMask | shiftedId;
    return Leaf.wrap(newLeaf);
  }

  function setTickFirst(Leaf leaf, Tick tick, uint id) internal pure returns (Leaf) {
    uint posInLeaf = TickLib.posInLeaf(tick);
    return setIndexFirstOrLast(leaf, posInLeaf, id, false);
  }

  function setTickLast(Leaf leaf, Tick tick, uint id) internal pure returns (Leaf) {
    uint posInLeaf = TickLib.posInLeaf(tick);
    return setIndexFirstOrLast(leaf, posInLeaf, id, true);
  }

  // useful for quickly accessing the next tick even when the current offer is not the best
  // not for onchain use
  function eraseToTick(Leaf leaf, Tick tick) internal pure returns (Leaf) {
    uint mask = ONES >> ((tick.posInLeaf() + 1) * OFFER_BITS * 2);
    return Leaf.wrap(Leaf.unwrap(leaf) & mask);
  }

  function eraseFromTick(Leaf leaf, Tick tick) internal pure returns (Leaf) {
    uint mask = ~(ONES >> (tick.posInLeaf() * OFFER_BITS * 2));
    return Leaf.wrap(Leaf.unwrap(leaf) & mask);
  }

  function firstOfTick(Leaf leaf, Tick tick) internal pure returns (uint) {
    return firstOfIndex(leaf, TickLib.posInLeaf(tick));
  }

  function lastOfTick(Leaf leaf, Tick tick) internal pure returns (uint) {
    return lastOfIndex(leaf, TickLib.posInLeaf(tick));
  }

  function firstOfIndex(Leaf leaf, uint index) internal pure returns (uint) {
    uint raw = Leaf.unwrap(leaf);
    return uint(raw << (index * OFFER_BITS * 2) >> (256 - OFFER_BITS));
  }

  function lastOfIndex(Leaf leaf, uint index) internal pure returns (uint) {
    uint raw = Leaf.unwrap(leaf);
    return uint(raw << (OFFER_BITS * ((index * 2) + 1)) >> (256 - OFFER_BITS));
  }

  // Will check for the first position (0,1,2 or 3) that has a nonzero first-of-tick or a nonzero last-of-tick offer. Leafs where only one of those is nonzero are invalid anyway.
  function firstOfferPosition(Leaf leaf) internal pure returns (uint ret) {
    assembly("memory-safe") {
      ret := shl(1,gt(0xffffffffffffffffffffffffffffffff,leaf))
      ret := or(ret,gt(0xffffffffffffffff,shr(shl(7,iszero(ret)),leaf)))
    }
  }

  function getNextOfferId(Leaf leaf) internal pure returns (uint offerId) {
    return firstOfIndex(leaf,firstOfferPosition(leaf));
  }
}


library TickLib {

  function eq(Tick tick1, Tick tick2) internal pure returns (bool) {
    return Tick.unwrap(tick1) == Tick.unwrap(tick2);
  }

  function inRange(Tick tick) internal pure returns (bool) {
    return Tick.unwrap(tick) >= MIN_TICK && Tick.unwrap(tick) <= MAX_TICK;
  }

  function fromLogPrice(int logPrice, uint tickScale) internal pure returns (Tick) {
    // Do not force logPrices to fit the tickScale (aka logPrice%tickScale==0)
    // Round all prices down (aka cheaper for taker)
    int tick = logPrice / int(tickScale);
    if (logPrice < 0 && logPrice % int(tickScale) != 0) {
      tick = tick - 1;
    }
    return Tick.wrap(tick);
  }

  // Utility for tests&unpacked structs, less gas-optimal
  function tickFromBranch(uint tickPosInLeaf,Field level0, Field level1, Field level2, Field level3) internal pure returns (Tick) {
    LocalPacked local;
    local = local.tickPosInLeaf(tickPosInLeaf).level0(level0).level1(level1).level2(level2).level3(level3);
    return tickFromLocal(local);
  }

  function tickFromLocal(LocalPacked local) internal pure returns (Tick) {
    unchecked {
      uint utick = local.tickPosInLeaf() |
        ((BitLib.ctz64(Field.unwrap(local.level0())) |
          (BitLib.ctz64(Field.unwrap(local.level1())) |
            (BitLib.ctz64(Field.unwrap(local.level2())) |
              uint(
                (int(BitLib.ctz64(Field.unwrap(local.level3())))-LEVEL3_SIZE/2) << LEVEL2_SIZE_BITS)) 
              << LEVEL1_SIZE_BITS)
            << LEVEL0_SIZE_BITS)
          << LEAF_SIZE_BITS);
      return Tick.wrap(int(utick));
    }
  }

  // returns log_(1.0001)(wants/gives)
  // with wants/gives on 96 bits, tick will be < 24bits
  // never overstimates tick (but takes the highest tick that avoids doing so)
  // wants will be adjusted down from the original
  // FIXME use unchecked math but specify precise bounds on what inputs do not overflow
  // function tickFromVolumes(uint inboundAmt, uint outboundAmt, uint tickScale) internal pure returns (Tick) {
  //   return Tick.wrap(logPriceFromVolumes(inboundAmt,outboundAmt) * int(tickScale));
  // }

  // I could revert to indices being uints if I do (+ BIG_NUMBER) systematically,
  // then / something. More gas costly (a little) but
  // a) clearer
  // b) allows non-power-of-two sizes for "offers_per_leaf"
  function leafIndex(Tick tick) internal pure returns (int) {
    return Tick.unwrap(tick) >> LEAF_SIZE_BITS;
  }

  // ok because 2^TICK_BITS%TICKS_PER_LEAF=0
  // note "posIn*"
  // could instead write uint(tick) / a % b
  // but it's less explicit why it works:
  // works because sizes are powers of two, otherwise will have to do
  // tick+(MIN_OFFER/TICKS_PER_LEAF * TICKS_PER_LEAF), so that we are in positive range and have not changed modulo TICKS_PER_LEAF
  // otherwise if you mod negative numbers you get signed modulo defined as
  // a%b = sign(a) abs(a)%abs(b), e.g. -1%6=-1 when we would like -1%6=5
  // I could also do like uintX(intX(a%x)) but the method below means I don't need to edit all the code when I change mask sizes
  function posInLeaf(Tick tick) internal pure returns (uint) {
    return uint(Tick.unwrap(tick)) & LEAF_SIZE_MASK;
  }

  function level0Index(Tick tick) internal pure returns (int) {
    return Tick.unwrap(tick) >> (LEAF_SIZE_BITS + LEVEL0_SIZE_BITS);
  }

  // see note posIn*
  function posInLevel0(Tick tick) internal pure returns (uint) {
    return uint(tick.leafIndex()) & LEVEL0_SIZE_MASK;
  }

  function level1Index(Tick tick) internal pure returns (int) {
    return Tick.unwrap(tick) >> (LEAF_SIZE_BITS + LEVEL0_SIZE_BITS + LEVEL1_SIZE_BITS);
  }

  function level2Index(Tick tick) internal pure returns (int) {
    return Tick.unwrap(tick) >> (LEAF_SIZE_BITS + LEVEL0_SIZE_BITS + LEVEL1_SIZE_BITS + LEVEL2_SIZE_BITS);
  }

  // see note posIn*
  function posInLevel1(Tick tick) internal pure returns (uint) {
    return uint(tick.level0Index()) & LEVEL1_SIZE_MASK;
  }

  function posInLevel2(Tick tick) internal pure returns (uint) {
    return uint(tick.level1Index()) & LEVEL2_SIZE_MASK;
  }

  // see note posIn*
  // note with int24 tick we only use 2 bits in level3
  //   level 3 single node
  // <--------------------->
  //  1                  0
  //  ^initial level2
  // so we can immediately add 32 to that
  // and there is no need to take a modulo
  function posInLevel3(Tick tick) internal pure returns (uint) {
    return uint(tick.level2Index() + LEVEL3_SIZE / 2);
  }

  function strictlyBetter(Tick tick1, Tick tick2) internal pure returns (bool) {
    return Tick.unwrap(tick1) < Tick.unwrap(tick2);
  }

  function better(Tick tick1, Tick tick2) internal pure returns (bool) {
    return Tick.unwrap(tick1) <= Tick.unwrap(tick2);
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
    return Field.unwrap(field1) == Field.unwrap(field2);
  }

  // Does not accept TOPBIT as an empty value
  function isEmpty(Field field) internal pure returns (bool) {
    return Field.unwrap(field) == Field.unwrap(EMPTY);
  }

  // function unsetBitAtTick(Field field, Tick tick, uint level) internal pure returns (Field) {
  //   uint index =
  //     uint(Tick.unwrap(tick)) % (level == 0 ? TICKS_PER_LEVEL0 : level == 1 ? TICKS_PER_LEVEL1 : TICKS_PER_LEVEL2);
  //   return Field.wrap(Field.unwrap(field) & ~(1 << (256 - index)));
  // }

  function flipBitAtLevel0(Field level0, Tick tick) internal pure returns (Field) {
    uint pos = tick.posInLevel0();
    level0 = Field.wrap(Field.unwrap(level0) ^ (1 << pos));
    return level0;
  }

  function flipBitAtLevel1(Field level1, Tick tick) internal pure returns (Field) {
    uint pos = tick.posInLevel1();
    level1 = Field.wrap(Field.unwrap(level1) ^ (1 << pos));
    return level1;
  }

  function flipBitAtLevel2(Field level2, Tick tick) internal pure returns (Field) {
    uint pos = tick.posInLevel2();
    level2 = Field.wrap(Field.unwrap(level2) ^ (1 << pos));
    return level2;
  }

  function flipBitAtLevel3(Field level3, Tick tick) internal pure returns (Field) {
    uint pos = tick.posInLevel3();
    level3 = Field.wrap(Field.unwrap(level3) ^ (1 << pos));
    return level3;
  }

  // utility fn
  function eraseToTick0(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ONES << (tick.posInLevel0() + 1);
    return Field.wrap(Field.unwrap(field) & mask);
  }

  function eraseFromTick0(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ~(ONES << tick.posInLevel0());
    return Field.wrap(Field.unwrap(field) & mask);
  }

  // utility fn
  function eraseToTick1(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ONES << (tick.posInLevel1() + 1);
    return Field.wrap(Field.unwrap(field) & mask);
  }

  function eraseFromTick1(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ~(ONES << tick.posInLevel1());
    return Field.wrap(Field.unwrap(field) & mask);
  }

  // utility fn
  function eraseToTick2(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ONES << (tick.posInLevel2() + 1);
    return Field.wrap(Field.unwrap(field) & mask);
  }

  function eraseFromTick2(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ~(ONES << tick.posInLevel2());
    return Field.wrap(Field.unwrap(field) & mask);
  }

  // utility fn
  function eraseToTick3(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ONES << (tick.posInLevel3() + 1);
    return Field.wrap(Field.unwrap(field) & mask);
  }

  function eraseFromTick3(Field field, Tick tick) internal pure returns (Field) {
    uint mask = ~(ONES << tick.posInLevel3());
    return Field.wrap(Field.unwrap(field) & mask);
  }

  // Will throw if field is empty
  function firstOnePosition(Field field) internal pure returns (uint) {
    // FIXME stop checking for 0 or integrate it into ctz function in assembly
    require(!field.isEmpty(),"field is 0");
    unchecked {
      return BitLib.ctz64(Field.unwrap(field));
    }
  }

  // Will throw if field is empty
  function lastOnePosition(Field field) internal pure returns (uint) {
    // FIXME stop checking for 0 or integrate it into ctz function in assembly
    require(!field.isEmpty(), "field is 0");
    return BitLib.fls(Field.unwrap(field));
  }

  // Get the index of the first level(i) of a level(i+1)
  function firstLevel2Index(Field level3) internal pure returns (int) {
    return int(level3.firstOnePosition()) - LEVEL3_SIZE / 2;
  }
  function lastLevel2Index(Field level3) internal pure returns (int) {
    return int(level3.lastOnePosition()) - LEVEL3_SIZE / 2;
  }
  function firstLevel1Index(Field level2, int level2Index) internal pure returns (int) {
    return level2Index * LEVEL2_SIZE + int(level2.firstOnePosition());
  }
  function lastLevel1Index(Field level2, int level2Index) internal pure returns (int) {
    return level2Index * LEVEL2_SIZE + int(level2.lastOnePosition());
  }
  function firstLevel0Index(Field level1, int level1Index) internal pure returns (int) {
    return level1Index * LEVEL1_SIZE + int(level1.firstOnePosition());
  }
  function lastLevel0Index(Field level1, int level1Index) internal pure returns (int) {
    return level1Index * LEVEL1_SIZE + int(level1.lastOnePosition());
  }
  function firstLeafIndex(Field level0, int level0Index) internal pure returns (int) {
    return level0Index * LEVEL0_SIZE + int(level0.firstOnePosition());
  }
  function lastLeafIndex(Field level0, int level0Index) internal pure returns (int) {
    return level0Index * LEVEL0_SIZE + int(level0.lastOnePosition());
  }

 }
