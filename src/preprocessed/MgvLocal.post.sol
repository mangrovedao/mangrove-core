// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly { u := b }
}

uint constant ONES = type(uint).max;

struct LocalUnpacked {
  bool active;
  uint fee;
  uint density;
  uint offer_gasbase;
  bool lock;
  uint best;
  uint last;
}

//some type safety for each struct
type LocalPacked is uint;
using Library for LocalPacked global;

// number of bits in each field
uint constant active_bits        = 1;
uint constant fee_bits           = 16;
uint constant density_bits       = 112;
uint constant offer_gasbase_bits = 24;
uint constant lock_bits          = 1;
uint constant best_bits          = 32;
uint constant last_bits          = 32;

// number of bits before each field
uint constant active_before        = 0                    + 0;
uint constant fee_before           = active_before        + active_bits;
uint constant density_before       = fee_before           + fee_bits;
uint constant offer_gasbase_before = density_before       + density_bits;
uint constant lock_before          = offer_gasbase_before + offer_gasbase_bits;
uint constant best_before          = lock_before          + lock_bits;
uint constant last_before          = best_before          + best_bits;

// focus-mask: 1s at field location, 0s elsewhere
uint constant active_mask_inv        = (ONES << 256 - active_bits) >> active_before;
uint constant fee_mask_inv           = (ONES << 256 - fee_bits) >> fee_before;
uint constant density_mask_inv       = (ONES << 256 - density_bits) >> density_before;
uint constant offer_gasbase_mask_inv = (ONES << 256 - offer_gasbase_bits) >> offer_gasbase_before;
uint constant lock_mask_inv          = (ONES << 256 - lock_bits) >> lock_before;
uint constant best_mask_inv          = (ONES << 256 - best_bits) >> best_before;
uint constant last_mask_inv          = (ONES << 256 - last_bits) >> last_before;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant active_mask        = ~active_mask_inv;
uint constant fee_mask           = ~fee_mask_inv;
uint constant density_mask       = ~density_mask_inv;
uint constant offer_gasbase_mask = ~offer_gasbase_mask_inv;
uint constant lock_mask          = ~lock_mask_inv;
uint constant best_mask          = ~best_mask_inv;
uint constant last_mask          = ~last_mask_inv;

library Library {
  function to_struct(LocalPacked __packed) internal pure returns (LocalUnpacked memory __s) { unchecked {
    __s.active        = ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
    __s.fee           = (LocalPacked.unwrap(__packed) & fee_mask_inv) >> (256 - fee_bits - fee_before);
    __s.density       = (LocalPacked.unwrap(__packed) & density_mask_inv) >> (256 - density_bits - density_before);
    __s.offer_gasbase = (LocalPacked.unwrap(__packed) & offer_gasbase_mask_inv) >> (256 - offer_gasbase_bits - offer_gasbase_before);
    __s.lock          = ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
    __s.best          = (LocalPacked.unwrap(__packed) & best_mask_inv) >> (256 - best_bits - best_before);
    __s.last          = (LocalPacked.unwrap(__packed) & last_mask_inv) >> (256 - last_bits - last_before);
  }}

  function eq(LocalPacked __packed1, LocalPacked __packed2) internal pure returns (bool) { unchecked {
    return LocalPacked.unwrap(__packed1) == LocalPacked.unwrap(__packed2);
  }}

  function unpack(LocalPacked __packed) internal pure returns (bool __active, uint __fee, uint __density, uint __offer_gasbase, bool __lock, uint __best, uint __last) { unchecked {
    __active        = ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
    __fee           = (LocalPacked.unwrap(__packed) & fee_mask_inv) >> (256 - fee_bits - fee_before);
    __density       = (LocalPacked.unwrap(__packed) & density_mask_inv) >> (256 - density_bits - density_before);
    __offer_gasbase = (LocalPacked.unwrap(__packed) & offer_gasbase_mask_inv) >> (256 - offer_gasbase_bits - offer_gasbase_before);
    __lock          = ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
    __best          = (LocalPacked.unwrap(__packed) & best_mask_inv) >> (256 - best_bits - best_before);
    __last          = (LocalPacked.unwrap(__packed) & last_mask_inv) >> (256 - last_bits - last_before);
  }}

  function active(LocalPacked __packed) internal pure returns(bool) { unchecked {
    return ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
  }}

  function active(LocalPacked __packed,bool val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & active_mask) | (uint_of_bool(val) << (256 - active_bits)) >> active_before);
  }}
  
  function fee(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return (LocalPacked.unwrap(__packed) & fee_mask_inv) >> (256 - fee_bits - fee_before);
  }}

  function fee(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & fee_mask) | (val << (256 - fee_bits)) >> fee_before);
  }}
  
  function density(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return (LocalPacked.unwrap(__packed) & density_mask_inv) >> (256 - density_bits - density_before);
  }}

  function density(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & density_mask) | (val << (256 - density_bits)) >> density_before);
  }}
  
  function offer_gasbase(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return (LocalPacked.unwrap(__packed) & offer_gasbase_mask_inv) >> (256 - offer_gasbase_bits - offer_gasbase_before);
  }}

  function offer_gasbase(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & offer_gasbase_mask) | (val << (256 - offer_gasbase_bits)) >> offer_gasbase_before);
  }}
  
  function lock(LocalPacked __packed) internal pure returns(bool) { unchecked {
    return ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
  }}

  function lock(LocalPacked __packed,bool val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & lock_mask) | (uint_of_bool(val) << (256 - lock_bits)) >> lock_before);
  }}
  
  function best(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return (LocalPacked.unwrap(__packed) & best_mask_inv) >> (256 - best_bits - best_before);
  }}

  function best(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & best_mask) | (val << (256 - best_bits)) >> best_before);
  }}
  
  function last(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return (LocalPacked.unwrap(__packed) & last_mask_inv) >> (256 - last_bits - last_before);
  }}

  function last(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & last_mask) | (val << (256 - last_bits)) >> last_before);
  }}
  
}

function t_of_struct(LocalUnpacked memory __s) pure returns (LocalPacked) { unchecked {
  return pack(__s.active, __s.fee, __s.density, __s.offer_gasbase, __s.lock, __s.best, __s.last);
}}

function pack(bool __active, uint __fee, uint __density, uint __offer_gasbase, bool __lock, uint __best, uint __last) pure returns (LocalPacked) { unchecked {
  uint __packed;
  __packed |= (uint_of_bool(__active) << (256 - active_bits)) >> active_before;
  __packed |= (__fee << (256 - fee_bits)) >> fee_before;
  __packed |= (__density << (256 - density_bits)) >> density_before;
  __packed |= (__offer_gasbase << (256 - offer_gasbase_bits)) >> offer_gasbase_before;
  __packed |= (uint_of_bool(__lock) << (256 - lock_bits)) >> lock_before;
  __packed |= (__best << (256 - best_bits)) >> best_before;
  __packed |= (__last << (256 - last_bits)) >> last_before;
  return LocalPacked.wrap(__packed);
}}
