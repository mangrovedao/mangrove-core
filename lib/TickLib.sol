// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "mgv_lib/Constants.sol";
import {BitLib} from "mgv_lib/BitLib.sol";

type Leaf is uint;

using LeafLib for Leaf global;

type Field is uint;

using FieldLib for Field global;

type Tick is int;

using TickLib for Tick global;

library LeafLib {
  Leaf constant EMPTY = Leaf.wrap(uint(0));

  function eq(Leaf leaf1, Leaf leaf2) internal pure returns (bool) {
    return Leaf.unwrap(leaf1) == Leaf.unwrap(leaf2);
  }

  function isEmpty(Leaf leaf) internal pure returns (bool) {
    return leaf.eq(EMPTY);
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

  // TODO optimize with a hashmap
  function firstOfferPosition(Leaf leaf) internal pure returns (uint ret) {
    uint offerId = Leaf.unwrap(leaf) >> (OFFER_BITS * 7);
    if (offerId != 0) {
      ret = 0;
    } else {
      offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 2) >> (OFFER_BITS * 7);
      if (offerId != 0) {
        ret = 1;
      } else {
        offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 4) >> (OFFER_BITS * 7);
        if (offerId != 0) {
          ret = 2;
        } else {
          offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 6) >> (OFFER_BITS * 7);
          if (offerId != 0) {
            ret = 3;
          }
        }
      }
    }
  }

  // TODO: a debruijn hashtable would be less gasexpensive?
  // returns the 0 offer if empty (relied on by the code)
  // FIXME find a version with way fewer jumps
  function getNextOfferId(Leaf leaf) internal pure returns (uint offerId) {
    offerId = Leaf.unwrap(leaf) >> (OFFER_BITS * 7);
    if (offerId == 0) {
      offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 2) >> (OFFER_BITS * 7);
      if (offerId == 0) {
        offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 4) >> (OFFER_BITS * 7);
        if (offerId == 0) {
          offerId = Leaf.unwrap(leaf) << (OFFER_BITS * 6) >> (OFFER_BITS * 7);
        }
      }
    }
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
    if (logPrice < 0 && tick % int(tickScale) != 0) {
      tick = tick - 1;
    }
    return Tick.wrap(tick);
  }

  function tickFromBranch(uint tickPosInLeaf,Field level0, Field level1, Field level2) internal pure returns (Tick) {
    unchecked {
      uint utick = tickPosInLeaf |
        ((BitLib.ctz(Field.unwrap(level0)) |
          (BitLib.ctz(Field.unwrap(level1)) |
            uint((int(BitLib.ctz(Field.unwrap(level2)))-LEVEL2_SIZE/2) << LEVEL1_SIZE_BITS)) 
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

  // see note posIn*
  function posInLevel1(Tick tick) internal pure returns (uint) {
    return uint(tick.level0Index()) & LEVEL1_SIZE_MASK;
  }

  // see note posIn*
  // note with int24 tick we only use 64 bits of level2 (64*256*256*4 is 2**24)
  // the goal is that have the bit positions in {} used:

  //   level 2 single node
  // <--------------------->
  // {0.......63}64......255

  // we could start from the "normally-calculated" indices:

  //    level 2 node 0       level 2 node 1
  //  <----------------->  <--------------->
  //  0......31{32.....63  0.....31}32...255

  // then add 32 to get the bit positions, but we optimize:
  // level 1 indices are

  // lowest level 1 node              highest level 1 node
  //        -32.............-1 0...............31

  // so we can immediately add 32 to that
  // and there is no need to take a modulo
  function posInLevel2(Tick tick) internal pure returns (uint) {
    return uint(tick.level1Index() + LEVEL2_SIZE / 2);
  }

  function strictlyBetter(Tick tick1, Tick tick2) internal pure returns (bool) {
    return Tick.unwrap(tick1) < Tick.unwrap(tick2);
  }

  function better(Tick tick1, Tick tick2) internal pure returns (bool) {
    return Tick.unwrap(tick1) <= Tick.unwrap(tick2);
  }  

}

// In fields, positions are counted from the right
library FieldLib {
  Field constant EMPTY = Field.wrap(uint(0));
  function eq(Field field1, Field field2) internal pure returns (bool) {
    return Field.unwrap(field1) == Field.unwrap(field2);
  }

  function isEmpty(Field field) internal pure returns (bool) {
    return field.eq(EMPTY);
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

  // Will throw with "field is 0" if field is empty
  function firstOnePosition(Field field) internal pure returns (uint) {
    // FIXME stop checking for 0 or integrate it into ctz function in assembly
    require(!field.isEmpty(),"field is 0");
    unchecked {
      return BitLib.ctz(Field.unwrap(field));
    }
  }

  // Will throw with "field is 0" if field is empty
  function lastOnePosition(Field field) internal pure returns (uint) {
    // FIXME stop checking for 0 or integrate it into ctz function in assembly
    require(!field.isEmpty(),"field is 0");
    return BitLib.fls(Field.unwrap(field));
  }

  // Get the index of the first level1 of a level2
  function firstLevel1Index(Field level2) internal pure returns (int) {
    return int(level2.firstOnePosition()) - LEVEL2_SIZE / 2;
  }
  function lastLevel1Index(Field level2) internal pure returns (int) {
    return int(level2.lastOnePosition()) - LEVEL2_SIZE / 2;
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