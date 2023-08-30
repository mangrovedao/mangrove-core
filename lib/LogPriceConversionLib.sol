// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;

import "mgv_lib/Constants.sol";
import "mgv_lib/BitLib.sol";

library LogPriceConversionLib {
  // returns a normalized price
  // outbound constraint is for consistency, could be higher
  function priceFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (uint mantissa, uint exp) {
    require(inboundAmt <= MAX_SAFE_VOLUME, "priceFromVolumes/inbound/tooBig");
    require(outboundAmt <= MAX_SAFE_VOLUME, "priceFromVolumes/outbound/tooBig");
    require(outboundAmt != 0, "priceFromVolumes/outbound/0");
    require(inboundAmt != 0, "priceFromVolumes/inbound/0");
    uint ratio = (inboundAmt << MANTISSA_BITS) / outboundAmt; 
    // ratio cannot be 0 as long as (1<<MANTISSA_BITS)/MAX_SAFE_VOLUME > 0
    uint log2 = BitLib.fls(ratio);
    if (log2 > MANTISSA_BITS_MINUS_ONE) {
      uint diff = log2 - MANTISSA_BITS_MINUS_ONE;
      return (ratio >> diff, MANTISSA_BITS - diff);
    } else {
      uint diff = MANTISSA_BITS_MINUS_ONE - log2;
      return (ratio << diff, MANTISSA_BITS + diff);
    }
  }

  function logPriceFromVolumes(uint inboundAmt, uint outboundAmt) internal pure returns (int24 logPrice) {
    (uint man, uint exp) = priceFromVolumes(inboundAmt, outboundAmt);
    return logPriceFromNormalizedPrice(man,exp);
  }

  // expects a normalized price float
  function logPriceFromPrice(uint mantissa, int exp) internal pure returns (int24) {
    uint normalized_exp;
    (mantissa, normalized_exp) = normalizePrice(mantissa, exp);
    return logPriceFromNormalizedPrice(mantissa,normalized_exp);
  }

  // return greatest logPrice t such that price(logPrice) <= input price
  // does not expect a normalized price float
  function logPriceFromNormalizedPrice(uint mantissa, uint exp) internal pure returns (int24 logPrice) {
    if (floatLt(mantissa, int(exp), MIN_PRICE_MANTISSA, MIN_PRICE_EXP)) {
      revert("mgv/price/tooLow");
    }
    if (floatLt(MAX_PRICE_MANTISSA, MAX_PRICE_EXP, mantissa, int(exp))) {
      revert("mgv/price/tooHigh");
    }
    int log2price = int(MANTISSA_BITS_MINUS_ONE) - int(exp) << 64;
    uint mpow = mantissa >> MANTISSA_BITS_MINUS_ONE - 127; // give 129 bits of room left

    assembly ("memory-safe") {
      // 13 bits of precision
      mpow := shr(127, mul(mpow, mpow))
      let highbit := shr(128, mpow)
      log2price := or(log2price, shl(63, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(62, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(61, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(60, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(59, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(58, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(57, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(56, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(55, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(54, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(53, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(52, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(51, highbit))
      mpow := shr(highbit, mpow)

      mpow := shr(127, mul(mpow, mpow))
      highbit := shr(128, mpow)
      log2price := or(log2price, shl(50, highbit))
    }

    int log_bp_price = log2price * 127869479499801913173570;

    int24 logPriceLow = int24((log_bp_price - 1701479891078076505009565712080972645) >> 128);
    int24 logPriceHigh = int24((log_bp_price + 290040965921304576580754310682015830659) >> 128);

    (uint mantissaHigh, uint expHigh) = priceFromLogPrice(logPriceHigh);

    bool priceHighGt = floatLt(mantissa, int(exp), mantissaHigh, int(expHigh));
    if (logPriceLow == logPriceHigh || priceHighGt) {
      logPrice = logPriceLow;
    } else { 
      logPrice = logPriceHigh;
    }
  }

  // normalized float comparison
  function floatLt(uint mantissa_a, int exp_a, uint mantissa_b, int exp_b) internal pure returns (bool) {
    return (exp_a > exp_b || (exp_a == exp_b && mantissa_a < mantissa_b));
  }

  // return price from logPrice, as a non-normalized float (meaning the leftmost set bit is not always in the  same position)
  // first return value is the mantissa, second value is the opposite of the exponent
  function nonNormalizedPriceFromLogPrice(int logPrice) internal pure returns (uint man, uint exp) {
    uint absLogPrice = logPrice < 0 ? uint(-int(logPrice)) : uint(logPrice);
    require(absLogPrice <= uint(MAX_LOG_PRICE), "absLogPrice/outOfBounds");

    // each 1.0001^(2^i) below is shifted 128+(an additional shift value)
    int extra_shift;
    if (absLogPrice & 0x1 != 0) {
      man = 0xfff97272373d413259a46990580e2139;
    } else {
      man = 0x100000000000000000000000000000000;
    }
    if (absLogPrice & 0x2 != 0) {
      man = (man * 0xfff2e50f5f656932ef12357cf3c7fdcb) >> 128;
    }
    if (absLogPrice & 0x4 != 0) {
      man = (man * 0xffe5caca7e10e4e61c3624eaa0941ccf) >> 128;
    }
    if (absLogPrice & 0x8 != 0) {
      man = (man * 0xffcb9843d60f6159c9db58835c926643) >> 128;
    }
    if (absLogPrice & 0x10 != 0) {
      man = (man * 0xff973b41fa98c081472e6896dfb254bf) >> 128;
    }
    if (absLogPrice & 0x20 != 0) {
      man = (man * 0xff2ea16466c96a3843ec78b326b52860) >> 128;
    }
    if (absLogPrice & 0x40 != 0) {
      man = (man * 0xfe5dee046a99a2a811c461f1969c3052) >> 128;
    }
    if (absLogPrice & 0x80 != 0) {
      man = (man * 0xfcbe86c7900a88aedcffc83b479aa3a3) >> 128;
    }
    if (absLogPrice & 0x100 != 0) {
      man = (man * 0xf987a7253ac413176f2b074cf7815e53) >> 128;
    }
    if (absLogPrice & 0x200 != 0) {
      man = (man * 0xf3392b0822b70005940c7a398e4b70f2) >> 128;
    }
    if (absLogPrice & 0x400 != 0) {
      man = (man * 0xe7159475a2c29b7443b29c7fa6e889d8) >> 128;
    }
    if (absLogPrice & 0x800 != 0) {
      man = (man * 0xd097f3bdfd2022b8845ad8f792aa5825) >> 128;
    }
    if (absLogPrice & 0x1000 != 0) {
      man = (man * 0xa9f746462d870fdf8a65dc1f90e061e4) >> 128;
    }
    if (absLogPrice & 0x2000 != 0) {
      man = (man * 0xe1b0d342ada5437121767bec575e65ed) >> 128;
      extra_shift += 1;
    }
    if (absLogPrice & 0x4000 != 0) {
      man = (man * 0xc6f84d7e5f423f66048c541550bf3e96) >> 128;
      extra_shift += 2;
    }
    if (absLogPrice & 0x8000 != 0) {
      man = (man * 0x9aa508b5b7a84e1c677de54f3e99bc8f) >> 128;
      extra_shift += 4;
    }
    if (absLogPrice & 0x10000 != 0) {
      man = (man * 0xbad5f1bdb70232cd33865244bdcc089c) >> 128;
      extra_shift += 9;
    }
    if (absLogPrice & 0x20000 != 0) {
      man = (man * 0x885b9613d7e87aa498106fb7fa5edd37) >> 128;
      extra_shift += 18;
    }
    if (absLogPrice & 0x40000 != 0) {
      man = (man * 0x9142e0723efb884889d1f447715afacd) >> 128;
      extra_shift += 37;
    }
    if (absLogPrice & 0x80000 != 0) {
      man = (man * 0xa4d9a773d61316918f140bd96e8e6814) >> 128;
      extra_shift += 75;
    }
    if (logPrice > 0) {
      man = type(uint).max / man;
      extra_shift = -extra_shift;
    }
    // 18 ensures exp>= 0
    man = man << 18;
    exp = uint(128 + 18 + extra_shift);
  }

  // return price from logPrice, as a normalized float
  // first return value is the mantissa, second value is -exp
  function priceFromLogPrice(int logPrice) internal pure returns (uint man, uint exp) {
    (man, exp) = nonNormalizedPriceFromLogPrice(logPrice);

    uint log_bp_2X232 = 47841652135324370225811382070797757678017615758549045118126590952295589692;
    // log_1.0001(price) * log_2(1.0001)
    int log2price = (int(logPrice) << 232) / int(log_bp_2X232);
    // floor(log) towards negative infinity
    if (logPrice < 0 && int(logPrice) << 232 % log_bp_2X232 != 0) {
      log2price = log2price - 1;
    }
    // MANTISSA_BITS was chosen so that diff cannot be <0 
    uint diff = uint(int(MANTISSA_BITS_MINUS_ONE) - int(exp) - log2price);
    man = man << diff;
    exp = exp + diff;
  }

  // normalize a price float
  // normalizes a representation of mantissa * 2^-exp
  // examples:
  // 1 ether:1 -> normalizePrice(1 ether, 0)
  // 1: 1 ether -> normalizePrice(1,?)
  // 1:1 -> normalizePrice(1,0)
  // 1:2 -> normalizePrice(1,1)
  function normalizePrice(uint mantissa, int exp) internal pure returns (uint, uint) {
    require(mantissa != 0,"normalizePrice/mantissaIs0");
    uint log2price = BitLib.fls(mantissa);
    int shift = int(MANTISSA_BITS_MINUS_ONE) - int(log2price);
    if (shift < 0) {
      mantissa = mantissa >> uint(-shift);
    } else {
      mantissa = mantissa << uint(shift);
    }
    log2price = BitLib.fls(mantissa);
    exp = exp + shift;
    if (exp < 0) {
      revert("mgv/normalizePrice/lowExp");
    }
    return (mantissa,uint(exp));
  }
}