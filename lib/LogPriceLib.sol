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
  // FIXME ensure that you only called tick*tickScale if you previously stored the tick as a result of logPrice/tickScale. Otherwise you may go beyond the MAX/MIN.
  function fromTick(Tick tick, uint tickScale, int tickShift) internal pure returns (int) {
    return (Tick.unwrap(tick) + tickShift) * int(tickScale);
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
    (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(logPrice);
    uint prod = sig*outboundAmt;
    return (prod>>exp) + (prod%(1<<exp)==0 ? 0 : 1);
  }

  // temporarily commenting this out because it's used in commented out tests
  // function inboundFromOutboundUpTick(Tick tick, uint outboundAmt) internal pure returns (uint) {
  //   uint nextPrice_e18 = Tick.wrap(Tick.unwrap(tick)+1).priceFromTick_e18();
  //   uint prod = nextPrice_e18 * outboundAmt;
  //   prod = prod/1e18;
  //   if (prod == 0) {
  //     return 0;
  //   }
  //   return prod-1;
  // }  

  // tick underestimates the price, and we underestimate outbound here, so price will be overestimated here
  // no overflow if inboundAmt is on 104 bits
  // rounds down
  function outboundFromInbound(int logPrice, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(-logPrice);
    return (sig * inboundAmt) >> exp;
  }

  function outboundFromInboundUp(int logPrice, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = LogPriceConversionLib.nonNormalizedPriceFromLogPrice(-logPrice);
    uint prod = sig*inboundAmt;
    return (prod>>exp) + (prod%(1<<exp)==0 ? 0 : 1);
  }



}
