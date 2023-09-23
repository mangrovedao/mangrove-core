// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Bin} from "mgv_lib/BinLib.sol";
import "mgv_lib/Constants.sol";
import "mgv_lib/TickConversionLib.sol";

type Tick is int;
using TickLib for Tick global;

library TickLib {

  function inRange(Tick tick) internal pure returns (bool) {
    return Tick.unwrap(tick) >= MIN_TICK && Tick.unwrap(tick) <= MAX_TICK;
  }

  function eq(Tick tick1, Tick tick2) internal pure returns (bool) {
    unchecked {
      return Tick.unwrap(tick1) == Tick.unwrap(tick2);
    }
  }

  // Returns the nearest, higher bin to the given tick at the given tickSpacing
  function nearestBin(Tick tick, uint tickSpacing) internal pure returns (Bin) {
    unchecked {
      // Do not force ticks to fit the tickSpacing (aka tick%tickSpacing==0)
      // Round maker ratios up such that maker is always paid at least what they asked for
      int bin = Tick.unwrap(tick) / int(tickSpacing);
      if (Tick.unwrap(tick) > 0 && Tick.unwrap(tick) % int(tickSpacing) != 0) {
        bin = bin + 1;
      }
      return Bin.wrap(bin);
    }
  }


  // Optimized conversion for ticks that are known to map exactly to a bin at the given tickSpacing,
  // eg for offers in the offer list which are always written with a tick-aligned tick
  function alignedToNearestBin(Tick tick, uint tickSpacing) internal pure returns (Bin) {
    return Bin.wrap(Tick.unwrap(tick) / int(tickSpacing));
  }

  // bin underestimates the ratio, so we underestimate  inbound here, i.e. the inbound/outbound ratio will again be underestimated
  // no overflow if outboundAmt is on 104 bits
  // rounds down
  function inboundFromOutbound(Tick tick, uint outboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(tick);
    return (sig * outboundAmt) >> exp;
  }

  // no overflow if outboundAmt is on 104 bits
  // rounds up
  function inboundFromOutboundUp(Tick tick, uint outboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(tick);
      return divExpUp(sig*outboundAmt,exp);
    }
  }

  // bin underestimates the ratio, and we underestimate outbound here, so ratio will be overestimated here
  // no overflow if inboundAmt is on 104 bits
  // rounds down
  function outboundFromInbound(Tick tick, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(Tick.wrap(-Tick.unwrap(tick)));
    return (sig * inboundAmt) >> exp;
  }

  function outboundFromInboundUp(Tick tick, uint inboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(Tick.wrap(-Tick.unwrap(tick)));
      return divExpUp(sig*inboundAmt,exp);
    }
  }
}

// Return a/2**e rounded up
function divExpUp(uint a, uint e) pure returns (uint) {
  unchecked {
    uint rem;
    /* 
    Let mask be (1<<e)-1, rem is 1 if a & mask > 0, and 0 otherwise.
    Explanation:
    * if a is 0 then rem must be 0. 0 & mask is 0.
    * else if e > 255 then 0 < a < 2^e, so rem must be 1. (1<<e)-1 is type(uint).max, so a & mask is a > 0.
    * else a & mask is a % 2**e
    */
    assembly("memory-safe") {
      rem := gt(and(a,sub(shl(e,1),1)),0)
    }
    return (a>>e) + rem;
  }
}
