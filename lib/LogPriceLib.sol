// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Tick} from "mgv_lib/TickLib.sol";
import "mgv_lib/Constants.sol";
import "mgv_lib/LogPriceConversionLib.sol";

library LogPriceLib {

  function inRange(int logPrice) internal pure returns (bool) {
    return logPrice >= MIN_LOG_PRICE && logPrice <= MAX_LOG_PRICE;
  }
  // 
  function fromTick(Tick tick, uint tickScale) internal pure returns (int) {
    return Tick.unwrap(tick) * int(tickScale);
  }

  // tick underestimates the price, so we underestimate  inbound here, i.e. the inbound/outbound price will again be underestimated
  // no overflow if outboundAmt is on 104 bits
  // rounds down
  function inboundFromOutbound(int logPrice, uint outboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(logPrice);
    return (sig * outboundAmt) >> exp;
  }

  // no overflow if outboundAmt is on 104 bits
  // rounds up
  function inboundFromOutboundUp(int logPrice, uint outboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(logPrice);
      return divExpUp(sig*outboundAmt,exp);
    }
  }

  // tick underestimates the price, and we underestimate outbound here, so price will be overestimated here
  // no overflow if inboundAmt is on 104 bits
  // rounds down
  function outboundFromInbound(int logPrice, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(-logPrice);
    return (sig * inboundAmt) >> exp;
  }

  function outboundFromInboundUp(int logPrice, uint inboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(-logPrice);
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
