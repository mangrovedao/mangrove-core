// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import {Bin} from "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/lib/core/BitLib.sol";
import "@mgv/lib/core/Constants.sol";

/* This file is inspired by Uniswap's approach to ticks, with the following notable changes:
- directly compute ticks base 1.0001 (not base `sqrt(1.0001)`)
- directly compute ratios (not `sqrt(ratio)`) (simpler code elsewhere when dealing with actual ratios and logs of ratios)
- ratios are floating-point numbers, not fixed-point numbers (increases precision when computing amounts)
*/


/* # TickLib

The `TickLib` file contains tick math-related code and utilities for manipulating ticks. It also holds functions related to ratios, which are represented as (mantissa,exponent) pairs. */

/* Globally enable `tick.method(...)` */
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

  /* Returns the nearest, higher bin to the given `tick` at the given `tickSpacing`
    
    We do not force ticks to fit the tickSpacing (aka `tick%tickSpacing==0`). Ratios are rounded up that the maker is always paid at least what they asked for
  */
  function nearestBin(Tick tick, uint tickSpacing) internal pure returns (Bin bin) {
    unchecked {
      // By default division rounds towards 0. Since `smod` is signed we get the sign of `tick` and `tick%tickSpacing` in a single instruction.
      assembly("memory-safe") {
        bin := sdiv(tick,tickSpacing)
        bin := add(bin,sgt(smod(tick,tickSpacing),0))
      }
    }
  }

  /* ## Conversion functions */

  /* ### (inbound,tick) → outbound 
  `inboundFromOutbound[Up]` converts an outbound amount (i.e. an `offer.gives` or a `takerWants`), to an inbound amount, following the price induced by `tick`. There's a rounding-up and a rounding-down variant.

  `outboundAmt` should not exceed 127 bits.
  */
  function inboundFromOutbound(Tick tick, uint outboundAmt) internal pure returns (uint) {
    (uint sig, uint exp) = ratioFromTick(tick);
    return (sig * outboundAmt) >> exp;
  }

  function inboundFromOutboundUp(Tick tick, uint outboundAmt) internal pure returns (uint) {
    unchecked {
      (uint sig, uint exp) = ratioFromTick(tick);
      return divExpUp(sig*outboundAmt,exp);
    }
  }

  /* ### (outbound,tick) → inbound */
  /* `outboundFromInbound[Up]` converts an inbound amount (i.e. an `offer.wants` or a `takerGives`), to an outbound amount, following the price induced by `tick`. There's a rounding-up and a rounding-down variant.

  `inboundAmt` should not exceed 127 bits.
  */
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

  /* ## Ratio representation

  Ratios are represented as a (mantissa,exponent) pair which represents the number `mantissa * 2**-exponent`.

  The exponent is negated so that, for ratios in the accepted range, the exponent is `>= 0`. This simplifies the code.

  Floats are normalized so that the mantissa uses exactly 128 bits. It enables easy comparison between floats and ensures they can be multiplied by amounts without overflow.

  The accepted ratio range is between `ratioFromTick(MIN_TICK)` and `ratioFromTick(MAX_TICK)` (inclusive).
  */
  

  /* ### (outbound,inbound) → ratio */

  /* `ratioFromVolumes` converts a pair of (inbound,outbound) volumes to a floating-point, normalized ratio.
  * `outboundAmt = 0` has a special meaning and the highest possible price will be returned.
  * `inboundAmt = 0` has a special meaning if `outboundAmt != 0` and the lowest possible price will be returned.
  */
  function ratioFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (uint mantissa, uint exp) {
    unchecked {
      require(inboundAmt <= MAX_SAFE_VOLUME, "mgv/ratioFromVol/inbound/tooBig");
      require(outboundAmt <= MAX_SAFE_VOLUME, "mgv/ratioFromVol/outbound/tooBig");
      if (outboundAmt == 0) {
        return (MAX_RATIO_MANTISSA,uint(MAX_RATIO_EXP));
      } else if (inboundAmt == 0) {
        return (MIN_RATIO_MANTISSA,uint(MIN_RATIO_EXP));
      }
      uint ratio = (inboundAmt << MANTISSA_BITS) / outboundAmt; 
      uint log2 = BitLib.fls(ratio);
      require(ratio != 0,"mgv/ratioFromVolumes/zeroRatio");
      if (log2 > MANTISSA_BITS_MINUS_ONE) {
        uint diff = log2 - MANTISSA_BITS_MINUS_ONE;
        return (ratio >> diff, MANTISSA_BITS - diff);
      } else {
        uint diff = MANTISSA_BITS_MINUS_ONE - log2;
        return (ratio << diff, MANTISSA_BITS + diff);
      }
    }
  }

  /* ### (outbound,inbound) → ratio */
  function tickFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (Tick tick) {
    (uint man, uint exp) = ratioFromVolumes(inboundAmt, outboundAmt);
    return tickFromNormalizedRatio(man,exp);
  }

  /* ### ratio → tick */
  /* Does not require a normalized ratio. */
  function tickFromRatio(uint mantissa, int exp) internal pure returns (Tick) {
    uint normalized_exp;
    (mantissa, normalized_exp) = normalizeRatio(mantissa, exp);
    return tickFromNormalizedRatio(mantissa,normalized_exp);
  }

  /* ### low-level ratio → tick */
  /* Given `ratio`, return greatest tick `t` such that `ratioFromTick(t) <= ratio`. 
  * Input ratio must be within the maximum and minimum ratios returned by the available ticks. 
  * Does _not_ expected a normalized float.
  
  The function works as follows:
  * Approximate log2(ratio) to the 13th fractional digit.
  * Following <a href="https://hackmd.io/@mangrovedao/HJvl21zla">https://hackmd.io/@mangrovedao/HJvl21zla</a>, obtain `tickLow` and `tickHigh` such that $\log_{1.0001}(ratio)$ is between them
  * Return the highest one that yields a ratio below the input ratio.
  */
  function tickFromNormalizedRatio(uint mantissa, uint exp) internal pure returns (Tick tick) {
    if (floatLt(mantissa, exp, MIN_RATIO_MANTISSA, uint(MIN_RATIO_EXP))) {
      revert("mgv/tickFromRatio/tooLow");
    }
    if (floatLt(MAX_RATIO_MANTISSA, uint(MAX_RATIO_EXP), mantissa, exp)) {
      revert("mgv/tickFromRatio/tooHigh");
    }
    int log2ratio = int(MANTISSA_BITS_MINUS_ONE) - int(exp) << 64;
    uint mpow = mantissa >> MANTISSA_BITS_MINUS_ONE - 127; // give 129 bits of room left

    /* How the fractional digits of the log are computed: 
    * for a given `n` compute $n^2$. 
    * If $\lfloor\log_2(n^2)\rfloor = 2\lfloor\log_2(n)\rfloor$ then the fractional part of $\log_2(n^2)$ was $< 0.5$ (first digit is 0). 
    * If $\lfloor\log_2(n^2)\rfloor = 1 + 2\lfloor\log_2(n)\rfloor$ then the fractional part of $\log_2(n^2)$ was $\geq 0.5$ (first digit is 1).
    * Apply starting with `n=mpow` repeatedly by keeping `n` on 127 bits through right-shifts (has no impact on high fractional bits).
    */

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
    }

    // Convert log base 2 to log base 1.0001 (multiply by `log2(1.0001)^-1 << 64`), since log2ratio is x64 this yields a x128 number.
    int log_bp_ratio = log2ratio * 127869479499801913173571;

    // tickLow is approx - maximum error
    int tickLow = int((log_bp_ratio - 1701496478404567508395759362389778998) >> 128);
    // tickHigh is approx + minimum error
    int tickHigh = int((log_bp_ratio + 289637967442836606107396900709005211253) >> 128);

    (uint mantissaHigh, uint expHigh) = ratioFromTick(Tick.wrap(tickHigh));

    bool ratioHighGt = floatLt(mantissa, exp, mantissaHigh, expHigh);
    if (tickLow == tickHigh || ratioHighGt) {
      tick = Tick.wrap(tickLow);
    } else { 
      tick = Tick.wrap(tickHigh);
    }
  }

  /* ### tick → ratio conversion function */
  /* Returns a normalized (man,exp) ratio floating-point number. The mantissa is on 128 bits to avoid overflow when mulitplying with token amounts. The exponent has no bias. for easy comparison. */
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

  /* ### low-level tick → ratio conversion */
  /* Compute 1.0001^tick and returns it as a (mantissa,exponent) pair. Works by checking each set bit of `|tick|` multiplying by `1.0001^(-2**i)<<128` if the ith bit of tick is set. Since we inspect the absolute value of `tick`, `-1048576` is not a valid tick. If the tick is positive this computes `1.0001^-tick`, and we take the inverse at the end. For maximum precision some powers of 1.0001 are shifted until they occupy 128 bits. The `extra_shift` is recorded and added to the exponent.

  Since the resulting mantissa is left-shifted by 128 bits, if tick was positive, we divide `2**256` by the mantissa to get the 128-bit left-shifted inverse of the mantissa.
  */
  function nonNormalizedRatioFromTick(Tick tick) internal pure returns (uint man, uint exp) {
    uint absTick = Tick.unwrap(tick) < 0 ? uint(-Tick.unwrap(tick)) : uint(Tick.unwrap(tick));
    require(absTick <= uint(MAX_TICK), "mgv/absTick/outOfBounds");

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
      /* We use [Remco Bloemen's trick](https://xn--2-umb.com/17/512-bit-division/#divide-2-256-by-a-given-number) to divide `2**256` by `man`: */
      assembly("memory-safe") {
        man := add(div(sub(0, man), man), 1)
      }
      extra_shift = -extra_shift;
    }
    exp = uint(128 + extra_shift);

  }

  /* Shift mantissa so it occupies exactly `MANTISSA_BITS` and adjust `exp` in consequence.
  
  A float is normalized when its mantissa occupies exactly 128 bits. All in-range normalized floats have `exp >= 0`, so we can use a `uint` for exponents everywhere we expect a normalized float.

  When a non-normalized float is expected/used, `exp` can be negative since there is no constraint on the size of the mantissa.
  
   */
  function normalizeRatio(uint mantissa, int exp) internal pure returns (uint, uint) {
    require(mantissa != 0,"mgv/normalizeRatio/mantissaIs0");
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

  /* Return `a/(2**e)` rounded up */
  function divExpUp(uint a, uint e) internal pure returns (uint) {
    unchecked {
      uint rem;
      /* 
      Let mask be `(1<<e)-1`, `rem` is 1 if `a & mask > 0`, and 0 otherwise.
      Explanation:
      * if a is 0 then `rem` must be 0. `0 & mask` is 0.
      * else if `e > 255` then `0 < a < 2^e`, so `rem` must be 1. `(1<<e)-1` is `type(uint).max`, so `a & mask is a > 0`.
      * else `a & mask` is `a % 2**e`
      */
      assembly("memory-safe") {
        rem := gt(and(a,sub(shl(e,1),1)),0)
      }
      return (a>>e) + rem;
    }
  }

  /* Floats are normalized to 128 bits to ensure no overflow when multiplying with amounts, and for easier comparisons. Normalized in-range floats have `exp>=0`. */
  function floatLt(uint mantissa_a, uint exp_a, uint mantissa_b, uint exp_b) internal pure returns (bool) {
    /* Exponents are negated (so that exponents of ratios within the accepted range as >= 0, which simplifies the code), which explains the direction of the `exp_a > exp_b` comparison. */ 
    return (exp_a > exp_b || (exp_a == exp_b && mantissa_a < mantissa_b));
  }

}