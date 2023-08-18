// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import {Tick,Field} from "mgv_lib/TickLib.sol";

import {BitLib} from "mgv_lib/BitLib.sol";

/* Density

The density of a semibook is the number of outbound tokens per gas required. An offer must a respect a semibook's density.

Density can be < 1.

The density of a semibook is stored as a 9 bits float. For convenience, governance functions read density as a 96x32 fixed point number. The functions below give conversion utilities between the two formats

As a guideline, fixed-point densities should be uints and should use hungarian notation (for instance `uint densityFixed`). Floating-point densities should use the Density user-defined type.
*/

// FIXME: optimize more (assembly), operate on single stack value to avoid double-work with Local bit manipulation.

/* 
the float <-> fixed conversion is format agnostic but the expectation is that fixed points are 96x32, and floats are 2-bit mantissa, 7bit exponent with bias 32. 

The encoding is nonstandard so the code can be simpler.

There are no subnormal floats in this encoding, [mantissa][exp] means:

  if exp is 0 or 1: 0bmantissa     * 2^-32
  otherwise:        0b1.mantissa * 2^(exp-32)

so the small values have some holes:

   coeff       exponent   available     |       coeff       exponent   available
  ------------------------------------------------------------------------------
  0b0.00                                |      0b1.10         -31
  0b1.00         -32                    |      0b1.11         -31         no
  0b1.01         -32         no         |      0b1.00         -30
  0b1.10         -32         no         |      0b1.01         -30
  0b1.11         -32         no         |      0b1.10         -30
  0b1.00         -31                    |      0b1.11         -30
  0b1.01         -31         no         |      0b1.00         -29
*/

type Density is uint;
using DensityLib for Density global;

uint constant ONES = type(uint).max;

library DensityLib {
  // Numbers in this file assume that density is 9 bits in structs.ts
  uint constant BITS = 9; // must match structs.ts
  uint constant MANTISSA_BITS = 2;
  uint constant SUBNORMAL_LIMIT = ~(ONES << (MANTISSA_BITS+1));
  uint constant MANTISSA_MASK = ~(ONES << MANTISSA_BITS);
  uint constant MASK = ~(ONES << BITS);
  uint constant MANTISSA_INTEGER = 1 << MANTISSA_BITS;
  uint constant EXPONENT_BITS = BITS - MANTISSA_BITS;
  uint constant FIXED_INTEGER_BITS = 96;
  uint constant FIXED_FRACTIONAL_BITS = 32;
  uint constant FIXED_BITS = FIXED_INTEGER_BITS + FIXED_FRACTIONAL_BITS;
  uint constant FIXED_MASK = ~(ONES << FIXED_BITS);

  // Check the size of a fixed-point formatted density
  function checkFixedDensity(uint densityFixed) internal pure returns (bool) { unchecked {
    return densityFixed & FIXED_MASK == densityFixed;
  }}

  // fixed-point -> float conversion
  // Warning: no bit cleaning (expected to be done by Local's code), no checking that the input is on 128 bits.
  // floats with [exp=1] are not in the image of fromFixed. They are considered noncanonical.
  function fromFixed(uint densityFixed) internal pure returns (Density) { unchecked {
    if (densityFixed <= MANTISSA_MASK) {
      return Density.wrap(densityFixed);
    }
    // invariant: exp >= 2 (so not 0)
    uint exp = BitLib.fls(densityFixed);
    return make(densityFixed >> (exp-MANTISSA_BITS),exp);
  }}

  // float -> fixed-point conversion
  function toFixed(Density density) internal pure returns (uint) { unchecked {
    // also accepts floats not generated by fixedToFloat, i.e. with exp=1
    if (Density.unwrap(density) <= SUBNORMAL_LIMIT) {
      return Density.unwrap(density) & MANTISSA_MASK;
    }
    // invariant: exp >= 2
    // assumes exp is on the right number of bits
    uint shift = (Density.unwrap(density) >> MANTISSA_BITS) - MANTISSA_BITS;
    return ((Density.unwrap(density) & MANTISSA_MASK) | MANTISSA_INTEGER) << shift;
  }}

  function mantissa(Density density) internal pure returns (uint) { unchecked {
    return Density.unwrap(density) & MANTISSA_MASK;
  }}

  function exponent(Density density) internal pure returns (uint) { unchecked {
    return Density.unwrap(density) >> MANTISSA_BITS;
  }}

  // Make a float from a mantissa and an exponent. May make a noncanonical float.
  // Warning: no checks
  function make(uint _mantissa, uint _exponent) internal pure returns (Density) { unchecked {
    return Density.wrap((_exponent << MANTISSA_BITS) | (_mantissa & MANTISSA_MASK));
  }}

  /* None of the functions below will overflow if m is 96bit wide.
     Density being a 96.32 number is useful because:
     - Most of its range is reprensetable with the 9-bits float format chosen
     - It does not overflow when multiplied with a 96bit number, which is the size chosen to represent token amounts in Mangrove.
     - Densities below 2^-32 need > 4B gasreq to force gives > 0, which is not realistic
  */
  // Multiply the density with m, rounded towards zero.
  // May overflow if |m|>96
  function multiply(Density density, uint m) internal pure returns (uint) { unchecked {
    return (m * density.toFixed())>>FIXED_FRACTIONAL_BITS;
  }}
  // Multiply the density with m, rounded towards +infinity.
  // May overflow if |m|>96
  function multiplyUp(Density density, uint m) internal pure returns (uint) { unchecked {
    uint part = m * density.toFixed();
    return (part >> FIXED_FRACTIONAL_BITS) + (part%(2<<FIXED_FRACTIONAL_BITS) == 0 ? 0 : 1);
  }}

  // Convenience function: get a fixed-point density from the given parameters. Computes the price of gas in outbound base tokens, then multiplies by cover_factor.
  // Warning: multiply input prices by 100
  // not supposed to be gas optimized
  function fixedFromParams(
    uint outbound_decimals, 
    uint gasprice_in_gwei, 
    uint eth_in_usdx100, 
    uint outbound_display_in_usdx100, 
    uint cover_factor
  ) internal pure returns (uint) {
    require(uint8(outbound_decimals) == outbound_decimals,"DensityLib: decimals must be uint8");
    uint num = cover_factor * gasprice_in_gwei * (10**outbound_decimals) * eth_in_usdx100;
    // use * instead of << to trigger overflow check
    return (num * (1 << FIXED_FRACTIONAL_BITS)) / (outbound_display_in_usdx100 * 1e9);
  }

  function fixedFromParams(
    uint outbound_decimals, 
    uint gasprice_in_gwei, 
    uint outbound_display_in_gwei, 
    uint cover_factor
  ) internal pure returns (uint) {
    require(uint8(outbound_decimals) == outbound_decimals,"DensityLib: decimals must be uint8");
    uint num = cover_factor * gasprice_in_gwei * (10**outbound_decimals);
    // use * instead of << to trigger overflow check
    return (num * (1 << FIXED_FRACTIONAL_BITS)) / outbound_display_in_gwei;
  }
}