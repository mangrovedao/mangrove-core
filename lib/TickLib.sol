// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {BitLib} from "mgv_lib/BitLib.sol";

import {FixedPointMathLib as FP} from "solady/utils/FixedPointMathLib.sol";
uint constant ONES = type(uint).max;
uint constant TOPBIT = 1 << 255;

// MIN_TICK and MAX_TICK should be inside the addressable range defined by the sizes of LEAF, LEVEL0, LEVEL1, LEVEL2
//FIXME: This should be -524288 to match a 20 bit signed int
int constant MIN_TICK = -524288;
// int constant MIN_TICK = -524287;
int constant MAX_TICK = -MIN_TICK - 1;
// int constant MAX_TICK = -MIN_TICK;

// sizes must match field sizes in structs.ts where relevant
uint constant TICK_BITS = 24; //FIXME: We only use 20 bit ticks currently?
uint constant OFFER_BITS = 32;

// only power-of-two sizes are supported for LEAF_SIZE and LEVEL*_SIZE
uint constant LEAF_SIZE_BITS = 2; 
uint constant LEVEL0_SIZE_BITS = 6;
uint constant LEVEL1_SIZE_BITS = 6;
uint constant LEVEL2_SIZE_BITS = 6;

int constant LEAF_SIZE = int(2 ** (LEAF_SIZE_BITS));
int constant LEVEL0_SIZE = int(2 ** (LEVEL0_SIZE_BITS));
int constant LEVEL1_SIZE = int(2 ** (LEVEL1_SIZE_BITS));
int constant LEVEL2_SIZE = int(2 ** (LEVEL2_SIZE_BITS));

uint constant LEAF_SIZE_MASK = ~(ONES << LEAF_SIZE_BITS);
uint constant LEVEL0_SIZE_MASK = ~(ONES << LEVEL0_SIZE_BITS);
uint constant LEVEL1_SIZE_MASK = ~(ONES << LEVEL1_SIZE_BITS);
uint constant LEVEL2_SIZE_MASK = ~(ONES << LEVEL2_SIZE_BITS);

int constant NUM_LEVEL1 = int(LEVEL2_SIZE);
int constant NUM_LEVEL0 = NUM_LEVEL1 * LEVEL1_SIZE;
int constant NUM_LEAFS = NUM_LEVEL0 * LEVEL0_SIZE;
int constant NUM_TICKS = NUM_LEAFS * LEAF_SIZE;

// FIXME: Should these be here or placed somewhere else? Besides being useful in tests, they serve as documentation for the datastructure
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

uint constant OFFER_MASK = ONES >> (256 - OFFER_BITS);

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
  // returns the 0 offer if empty
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

library LogPriceLib {
  // Could have an INVALID tick that is > 24 bits? But in `local` how do I write "empty"?
  int constant BP = 1.0001 * 1e18;
  // FP.lnWad(BP)
  uint constant lnBP = 99995000333308;
  // FIXME should depend on the min and max prices 
  // FIXME: And on the tick datastructure limits
  // int constant MIN_LOG_PRICE = -524287;
  int constant MIN_LOG_PRICE = -524288;
  // int constant MAX_LOG_PRICE = -MIN_LOG_PRICE;
  int constant MAX_LOG_PRICE = -MIN_LOG_PRICE - 1;

  function inRange(int logPrice) internal pure returns (bool) {
    return logPrice >= MIN_LOG_PRICE && logPrice <= MAX_LOG_PRICE;
  }
  function logPriceFromPrice_e18(uint price_e18) internal pure returns (int) {
    return logPriceFromVolumes(price_e18, 1 ether);
  }

  // tick to price, price must not exceed max
  // if tickscale is 1 maxtick is maxprice
  // the only way there is a general max tickscale is if I cant have as many ticks as I want?
  // 
  // FIXME ensure that you only called tick*tickScale if you previously stored the tick as a result of logPrice/tickScale. Otherwise you may go beyond the MAX/MIN.
  function fromTick(Tick tick, uint tickScale) internal pure returns (int) {
    return Tick.unwrap(tick) * int(tickScale);
  }


  function logPriceFromTakerVolumes(uint takerGives, uint takerWants) internal pure returns (int) {
    if (takerGives == 0 || takerWants == 0) {
      // If inboundAmt is 0 then the price is irrelevant for taker
      return MAX_LOG_PRICE;
    }
    return logPriceFromVolumes(takerGives, takerWants);
  }

  function logPriceFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (int logPrice) {
    (uint num, uint den) = (inboundAmt,outboundAmt);
    if (inboundAmt < outboundAmt) {
      (num,den) = (den,num);
    } else {
    }
    int lnPrice = FP.lnWad(int(num * 1e18/den));
    // why is univ3 not doing that? Because they start from a ratio < 1 ?
    int lbpPrice = int(FP.divWad(uint(lnPrice),lnBP)/1e18);
    // note this implies the lowest tick will never be used! (could use for something else?)
    if (inboundAmt < outboundAmt) {
      lbpPrice = - lbpPrice;
    }

    uint pr = priceFromLogPrice_e18(lbpPrice);
    if (pr > inboundAmt * 1e18 / outboundAmt) {
      lbpPrice = lbpPrice - 1;
    } else {
    }

    return lbpPrice;
  }

  // priceFromTick_e18(Tick.wrap(MAX_TICK));
  uint constant MAX_PRICE_E18 = 58661978243588296630604521258702056828566;
  // priceFromTick_e18(Tick.wrap(MIN_TICK));
  // FIXME: added 1 since it's currently 0, which is not a valid price
  uint constant MIN_PRICE_E18 = 1;

  // returns 1.0001^tick*1e18
  // TODO: returned an even more scaled up price, as much as possible
  //max pow before overflow when computing with fixedpointlib, and when overflow when multiplying 
  /*
    To avoid having to do a full-width mulDiv (or reducing the tick precision) when computing amounts from prices, we choose the following values:
    - max tick is 694605 (a litte more than 1.3 * 2^19)
    - min tick is -694605 (a litte more than 1.3 * 2^19)
    - priceFromTick_e18 returns 1.0001^tick * 1e18
    - with volumes on 96 bits, and a tick in range, there is no overflow doing bp^tick * 1e18 * volume / 1e18
    */
  function priceFromLogPrice_e18(int logPrice) internal pure returns (uint) {
    require(inRange(logPrice),"mgv/priceFromLogPrice/outOfRange");
    // FIXME this must round up so tick(price(tick)) = tick
    // FIXME add a test for this
    // Right now e.g. priceFromTick(1) is too low, and tickFromVolumes(1 ether,Tick(1).outboundFromInbound(1 ether)) is 0 (should be 1)
    return uint(FP.powWad(BP, logPrice * 1e18));
  }

  // tick underestimates the price, so we underestimate  inbound here, i.e. the inbound/outbound price will again be underestimated
  function inboundFromOutbound(int logPrice, uint outboundAmt) internal pure returns (uint) {
    return priceFromLogPrice_e18(logPrice) * outboundAmt/1e18;
  }

  function inboundFromOutboundUp(int logPrice, uint outboundAmt) internal pure returns (uint) {
    uint prod = priceFromLogPrice_e18(logPrice) * outboundAmt;
    return prod/1e18 + (prod%1e18==0 ? 0 : 1);
  }

  function inboundFromOutboundUpTick(int logPrice, uint outboundAmt) internal pure returns (uint) {
    uint nextPrice_e18 = priceFromLogPrice_e18(logPrice+1);
    uint prod = nextPrice_e18 * outboundAmt;
    prod = prod/1e18;
    if (prod == 0) {
      return 0;
    }
    return prod-1;
  }  

  // tick underestimates the price, and we udnerestimate outbound here, so price will be overestimated here
  function outboundFromInbound(int logPrice, uint inboundAmt) internal pure returns (uint) {
    return inboundAmt * 1e18/priceFromLogPrice_e18(logPrice);
  }

  function outboundFromInboundUp(int logPrice, uint inboundAmt) internal pure returns (uint) {
    uint prod = inboundAmt * 1e18;
    uint price = priceFromLogPrice_e18(logPrice);
    return prod/price + (prod%price==0?0:1);
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
// FIXME: This is a non-standard way of writing bit positions, normally they're numbered right-to-left
// FIXME: Also, the highest position in a field is 63 and is used for the highest tick in the level.
//        This feels like it's conflicting with the stmt in the Excalidraw that says "ticks go right (cheap) to left (expensive)"
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
