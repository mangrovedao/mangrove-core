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

struct OfferUnpacked {
  uint prev;
  uint next;
  uint wants;
  uint gives;
}

//some type safety for each struct
type OfferPacked is uint;
using Library for OfferPacked global;

// number of bits in each field
uint constant prev_bits  = 32;
uint constant next_bits  = 32;
uint constant wants_bits = 96;
uint constant gives_bits = 96;

// number of bits before each field
uint constant prev_before  = 0            + 0;
uint constant next_before  = prev_before  + prev_bits;
uint constant wants_before = next_before  + next_bits;
uint constant gives_before = wants_before + wants_bits;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant prev_mask  = ~((ONES << 256 - prev_bits) >> prev_before);
uint constant next_mask  = ~((ONES << 256 - next_bits) >> next_before);
uint constant wants_mask = ~((ONES << 256 - wants_bits) >> wants_before);
uint constant gives_mask = ~((ONES << 256 - gives_bits) >> gives_before);

library Library {
  function to_struct(OfferPacked __packed) internal pure returns (OfferUnpacked memory __s) { unchecked {
    __s.prev  = (OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __s.next  = (OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
    __s.wants = (OfferPacked.unwrap(__packed) << wants_before) >> (256 - wants_bits);
    __s.gives = (OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  function eq(OfferPacked __packed1, OfferPacked __packed2) internal pure returns (bool) { unchecked {
    return OfferPacked.unwrap(__packed1) == OfferPacked.unwrap(__packed2);
  }}

  function unpack(OfferPacked __packed) internal pure returns (uint __prev, uint __next, uint __wants, uint __gives) { unchecked {
    __prev  = (OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __next  = (OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
    __wants = (OfferPacked.unwrap(__packed) << wants_before) >> (256 - wants_bits);
    __gives = (OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  function prev(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
  }}

  function prev(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & prev_mask) | (val << (256 - prev_bits)) >> prev_before);
  }}
  
  function next(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
  }}

  function next(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & next_mask) | (val << (256 - next_bits)) >> next_before);
  }}
  
  function wants(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << wants_before) >> (256 - wants_bits);
  }}

  function wants(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & wants_mask) | (val << (256 - wants_bits)) >> wants_before);
  }}
  
  function gives(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  function gives(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & gives_mask) | (val << (256 - gives_bits)) >> gives_before);
  }}
  
}

function t_of_struct(OfferUnpacked memory __s) pure returns (OfferPacked) { unchecked {
  return pack(__s.prev, __s.next, __s.wants, __s.gives);
}}

function pack(uint __prev, uint __next, uint __wants, uint __gives) pure returns (OfferPacked) { unchecked {
  uint __packed;
  __packed |= (__prev << (256 - prev_bits)) >> prev_before;
  __packed |= (__next << (256 - next_bits)) >> next_before;
  __packed |= (__wants << (256 - wants_bits)) >> wants_before;
  __packed |= (__gives << (256 - gives_bits)) >> gives_before;
  return OfferPacked.wrap(__packed);
}}
