// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Bin} from "mgv_lib/BinLib.sol";
import "mgv_lib/BitLib.sol";
import "mgv_lib/Constants.sol";

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
  function nearestBin(Tick tick, uint tickSpacing) internal pure returns (Bin bin) {
    // Do not force ticks to fit the tickSpacing (aka tick%tickSpacing==0)
    // Round maker ratios up such that maker is always paid at least what they asked for
    unchecked {
      assembly("memory-safe") {
        bin := sdiv(tick,tickSpacing)
        bin := add(bin,sgt(smod(tick,tickSpacing),0))
      }
    }
  }

  // bin underestimates the ratio, so we underestimate  inbound here, i.e. the inbound/outbound ratio will again be underestimated
  // no overflow if outboundAmt is on 104 bits
  // rounds down
  function inboundFromOutbound(Tick tick, uint outboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = ratioFromTick(tick);
    return (sig * outboundAmt) >> exp;
  }

  // no overflow if outboundAmt is on 104 bits
  // rounds up
  function inboundFromOutboundUp(Tick tick, uint outboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = ratioFromTick(tick);
      return divExpUp(sig*outboundAmt,exp);
    }
  }

  // bin underestimates the ratio, and we underestimate outbound here, so ratio will be overestimated here
  // no overflow if inboundAmt is on 104 bits
  // rounds down
  function outboundFromInbound(Tick tick, uint inboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = ratioFromTick(Tick.wrap(-Tick.unwrap(tick)));
    return (sig * inboundAmt) >> exp;
  }

  function outboundFromInboundUp(Tick tick, uint inboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = ratioFromTick(Tick.wrap(-Tick.unwrap(tick)));
      return divExpUp(sig*inboundAmt,exp);
    }
  }

  // returns a normalized ratio within the max/min ratio range
  // returns max_ratio if at least outboundAmt==0
  // returns min_ratio if only inboundAmt==0
  function ratioFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (uint mantissa, uint exp) {
    require(inboundAmt <= MAX_SAFE_VOLUME, "ratioFromVolumes/inbound/tooBig");
    require(outboundAmt <= MAX_SAFE_VOLUME, "ratioFromVolumes/outbound/tooBig");
    if (outboundAmt == 0) {
      return (MAX_RATIO_MANTISSA,uint(MAX_RATIO_EXP));
    } else if (inboundAmt == 0) {
      return (MIN_RATIO_MANTISSA,uint(MIN_RATIO_EXP));
    }
    uint ratio = (inboundAmt << MANTISSA_BITS) / outboundAmt; 
    // ratio cannot be 0 as long as (1<<MANTISSA_BITS)/MAX_SAFE_VOLUME > 0
    uint log2 = BitLib.fls(ratio);
    require(ratio != 0,"ratioFromVolumes/zeroRatio");
    if (log2 > MANTISSA_BITS_MINUS_ONE) {
      uint diff = log2 - MANTISSA_BITS_MINUS_ONE;
      return (ratio >> diff, MANTISSA_BITS - diff);
    } else {
      uint diff = MANTISSA_BITS_MINUS_ONE - log2;
      return (ratio << diff, MANTISSA_BITS + diff);
    }
  }

  function tickFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (Tick tick) {
    (uint man, uint exp) = ratioFromVolumes(inboundAmt, outboundAmt);
    return tickFromNormalizedRatio(man,exp);
  }

  // expects a normalized ratio float
  function tickFromRatio(uint mantissa, int exp) internal pure returns (Tick) {
    uint normalized_exp;
    (mantissa, normalized_exp) = normalizeRatio(mantissa, exp);
    return tickFromNormalizedRatio(mantissa,normalized_exp);
  }

  // return greatest tick t such that ratio(tick) <= input ratio
  // does not expect a normalized ratio float
  function tickFromNormalizedRatio(uint mantissa, uint exp) internal pure returns (Tick tick) {
    if (floatLt(mantissa, int(exp), MIN_RATIO_MANTISSA, MIN_RATIO_EXP)) {
      revert("mgv/ratio/tooLow");
    }
    if (floatLt(MAX_RATIO_MANTISSA, MAX_RATIO_EXP, mantissa, int(exp))) {
      revert("mgv/ratio/tooHigh");
    }
    int log2ratio = int(MANTISSA_BITS_MINUS_ONE) - int(exp) << 64;
    uint mpow = mantissa >> MANTISSA_BITS_MINUS_ONE - 127; // give 129 bits of room left

    assembly ("memory-safe") {
      // 13 bits of precision
      mpow := shr(127, mul(mpow, mpow))
      let highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(63, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(62, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(61, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(60, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(59, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(58, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(57, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(56, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(55, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(54, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(53, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(52, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(51, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2ratio := or(log2ratio, shl(50, highbit))
    }

    int log_bp_ratio = log2ratio * 127869479499801913173570;

    int tickLow = int((log_bp_ratio - 1701479891078076505009565712080972645) >> 128);
    int tickHigh = int((log_bp_ratio + 290040965921304576580754310682015830659) >> 128);

    (uint mantissaHigh, uint expHigh) = ratioFromTick(Tick.wrap(tickHigh));

    bool ratioHighGt = floatLt(mantissa, int(exp), mantissaHigh, int(expHigh));
    if (tickLow == tickHigh || ratioHighGt) {
      tick = Tick.wrap(tickLow);
    } else { 
      tick = Tick.wrap(tickHigh);
    }
  }

  // normalized float comparison
  function floatLt(uint mantissa_a, int exp_a, uint mantissa_b, int exp_b) internal pure returns (bool) {
    return (exp_a > exp_b || (exp_a == exp_b && mantissa_a < mantissa_b));
  }

  // return ratio from tick, as a non-normalized float (meaning the leftmost set bit is not always in the  same position)
  // first return value is the mantissa, second value is the opposite of the exponent
  // This functions works on all ticks that hold on 21 bits but applies the MAX_TICK constraint.
  function nonNormalizedRatioFromTick(Tick tick) internal pure returns (uint man, uint exp) {
    uint absTick = Tick.unwrap(tick) < 0 ? uint(-int(Tick.unwrap(tick))) : uint(Tick.unwrap(tick));
    require(absTick <= uint(MAX_TICK), "absTick/outOfBounds");

    // each 1.0001^(2^i) below is shifted 128+(an additional shift value)
    int extra_shift;
    if (absTick & 0x1 != 0) {
      man = 0xfff97272373d413259a46990580e2139;
    } else {
      man = 0x100000000000000000000000000000000;
    }
    if (absTick & 0x2 != 0) {
      man = (man * 0xfff2e50f5f656932ef12357cf3c7fdcb) >> 128;
    }
    if (absTick & 0x4 != 0) {
      man = (man * 0xffe5caca7e10e4e61c3624eaa0941ccf) >> 128;
    }
    if (absTick & 0x8 != 0) {
      man = (man * 0xffcb9843d60f6159c9db58835c926643) >> 128;
    }
    if (absTick & 0x10 != 0) {
      man = (man * 0xff973b41fa98c081472e6896dfb254bf) >> 128;
    }
    if (absTick & 0x20 != 0) {
      man = (man * 0xff2ea16466c96a3843ec78b326b52860) >> 128;
    }
    if (absTick & 0x40 != 0) {
      man = (man * 0xfe5dee046a99a2a811c461f1969c3052) >> 128;
    }
    if (absTick & 0x80 != 0) {
      man = (man * 0xfcbe86c7900a88aedcffc83b479aa3a3) >> 128;
    }
    if (absTick & 0x100 != 0) {
      man = (man * 0xf987a7253ac413176f2b074cf7815e53) >> 128;
    }
    if (absTick & 0x200 != 0) {
      man = (man * 0xf3392b0822b70005940c7a398e4b70f2) >> 128;
    }
    if (absTick & 0x400 != 0) {
      man = (man * 0xe7159475a2c29b7443b29c7fa6e889d8) >> 128;
    }
    if (absTick & 0x800 != 0) {
      man = (man * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    }
    if (absTick & 0x1000 != 0) {
      man = (man * 0xa9f746462d870fdf8a65dc1f90e061e4) >> 128;
    }
    if (absTick & 0x2000 != 0) {
      man = (man * 0xe1b0d342ada5437121767bec575e65ed) >> 128;
      extra_shift += 1;
    }
    if (absTick & 0x4000 != 0) {
      man = (man * 0xc6f84d7e5f423f66048c541550bf3e96) >> 128;
      extra_shift += 2;
    }
    if (absTick & 0x8000 != 0) {
      man = (man * 0x9aa508b5b7a84e1c677de54f3e99bc8f) >> 128;
      extra_shift += 4;
    }
    if (absTick & 0x10000 != 0) {
      man = (man * 0xbad5f1bdb70232cd33865244bdcc089c) >> 128;
      extra_shift += 9;
    }
    if (absTick & 0x20000 != 0) {
      man = (man * 0x885b9613d7e87aa498106fb7fa5edd37) >> 128;
      extra_shift += 18;
    }
    if (absTick & 0x40000 != 0) {
      man = (man * 0x9142e0723efb884889d1f447715afacd) >> 128;
      extra_shift += 37;
    }
    if (absTick & 0x80000 != 0) {
      man = (man * 0xa4d9a773d61316918f140bd96e8e6814) >> 128;
      extra_shift += 75;
    }
    if (Tick.unwrap(tick) > 0) {
      man = type(uint).max / man;
      extra_shift = -extra_shift;
    }
    exp = uint(128 + extra_shift);

  }

  // return ratio from tick, as a normalized float
  // first return value is the mantissa, second value is -exp
  function ratioFromTick(Tick tick) internal pure returns (uint man, uint exp) {
    unchecked {
    (man, exp) = nonNormalizedRatioFromTick(tick);
    int shiftedTick = Tick.unwrap(tick) << LOG_BP_SHIFT;
    int log2ratio;
    // floor log2 of ratio towards negative infinity
    assembly ("memory-safe") {
      log2ratio := sdiv(shiftedTick,LOG_BP_2X235)
      log2ratio := sub(log2ratio,slt(smod(shiftedTick,LOG_BP_2X235),0))
    }
    int diff = log2ratio+int(exp)-int(MANTISSA_BITS_MINUS_ONE);
    if (diff > 0) {
      // For |tick| <= 887272, this drops at most 5 bits of precision
      man = man >> uint(diff);
    } else {
      man = man << uint(-diff);
    }
    // For |tick| << 887272, log2ratio <= 127
    exp = uint(int(MANTISSA_BITS_MINUS_ONE)-log2ratio);
    }
  }

  // normalize a ratio float
  // normalizes a representation of mantissa * 2^-exp
  // examples:
  // 1 ether:1 -> normalizeRatio(1 ether, 0)
  // 1: 1 ether -> normalizeRatio(1,?)
  // 1:1 -> normalizeRatio(1,0)
  // 1:2 -> normalizeRatio(1,1)
  function normalizeRatio(uint mantissa, int exp) internal pure returns (uint, uint) {
    require(mantissa != 0,"normalizeRatio/mantissaIs0");
    uint log2ratio = BitLib.fls(mantissa);
    int shift = int(MANTISSA_BITS_MINUS_ONE) - int(log2ratio);
    if (shift < 0) {
      mantissa = mantissa >> uint(-shift);
    } else {
      mantissa = mantissa << uint(shift);
    }
    exp = exp + shift;
    if (exp < 0) {
      revert("mgv/normalizeRatio/lowExp");
    }
    return (mantissa,uint(exp));
  }

  // Return a/2**e rounded up
  function divExpUp(uint a, uint e) internal pure returns (uint) {
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
}