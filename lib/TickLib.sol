// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Bin} from "mgv_lib/BinLib.sol";
import "mgv_lib/Constants.sol";
import "mgv_lib/TickConversionLib.sol";

library TickLib {

  function inRange(int tick) internal pure returns (bool) {
    return tick >= MIN_TICK && tick <= MAX_TICK;
  }
  function fromBin(Bin bin, uint tickSpacing) internal pure returns (int) {
    return Bin.unwrap(bin) * int(tickSpacing);
  }

  // bin underestimates the ratio, so we underestimate  inbound here, i.e. the inbound/outbound ratio will again be underestimated
  // no overflow if outboundAmt is on 104 bits
  // rounds down
  function inboundFromOutbound(int tick, uint outboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(tick);
    return (sig * outboundAmt) >> exp;
  }

  // no overflow if outboundAmt is on 104 bits
  // rounds up
  function inboundFromOutboundUp(int tick, uint outboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(tick);
      return divExpUp(sig*outboundAmt,exp);
    }
  }

  // bin underestimates the ratio, and we underestimate outbound here, so ratio will be overestimated here
  // no overflow if inboundAmt is on 104 bits
  // rounds down
  function outboundFromInbound(int tick, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(-tick);
    return (sig * inboundAmt) >> exp;
  }

  function outboundFromInboundUp(int tick, uint inboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = TickConversionLib.nonNormalizedRatioFromTick(-tick);
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
