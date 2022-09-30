pragma solidity ^0.8.13;

// SPDX-License-Identifier: Unlicense

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

// fields are of the form [name,bits,type]

// struct_defs are of the form [name,obj]

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly { u := b }
}

struct OfferUnpacked {
  uint prev;
  uint next;
  uint wants;
  uint gives;
}

//some type safety for each struct
type OfferPacked is uint;
using Library for OfferPacked global;

uint constant prev_bits  = 32;
uint constant next_bits  = 32;
uint constant wants_bits = 96;
uint constant gives_bits = 96;

uint constant prev_before  = 0;
uint constant next_before  = prev_before  + prev_bits ;
uint constant wants_before = next_before  + next_bits ;
uint constant gives_before = wants_before + wants_bits;

uint constant prev_mask  = 0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
uint constant next_mask  = 0xffffffff00000000ffffffffffffffffffffffffffffffffffffffffffffffff;
uint constant wants_mask = 0xffffffffffffffff000000000000000000000000ffffffffffffffffffffffff;
uint constant gives_mask = 0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000;

library Library {
  function to_struct(OfferPacked __packed) internal pure returns (OfferUnpacked memory __s) { unchecked {
    __s.prev = (OfferPacked.unwrap(__packed) << prev_before) >> (256-prev_bits);
    __s.next = (OfferPacked.unwrap(__packed) << next_before) >> (256-next_bits);
    __s.wants = (OfferPacked.unwrap(__packed) << wants_before) >> (256-wants_bits);
    __s.gives = (OfferPacked.unwrap(__packed) << gives_before) >> (256-gives_bits);
  }}

  function eq(OfferPacked __packed1, OfferPacked __packed2) internal pure returns (bool) { unchecked {
    return OfferPacked.unwrap(__packed1) == OfferPacked.unwrap(__packed2);
  }}

  function unpack(OfferPacked __packed) internal pure returns (uint __prev, uint __next, uint __wants, uint __gives) { unchecked {
    __prev = (OfferPacked.unwrap(__packed) << prev_before) >> (256-prev_bits);
    __next = (OfferPacked.unwrap(__packed) << next_before) >> (256-next_bits);
    __wants = (OfferPacked.unwrap(__packed) << wants_before) >> (256-wants_bits);
    __gives = (OfferPacked.unwrap(__packed) << gives_before) >> (256-gives_bits);
  }}

  function prev(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << prev_before) >> (256-prev_bits);
  }}
  function prev(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & prev_mask)
                                | ((val << (256-prev_bits) >> prev_before)));
  }}
  function next(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << next_before) >> (256-next_bits);
  }}
  function next(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & next_mask)
                                | ((val << (256-next_bits) >> next_before)));
  }}
  function wants(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << wants_before) >> (256-wants_bits);
  }}
  function wants(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & wants_mask)
                                | ((val << (256-wants_bits) >> wants_before)));
  }}
  function gives(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return (OfferPacked.unwrap(__packed) << gives_before) >> (256-gives_bits);
  }}
  function gives(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & gives_mask)
                                | ((val << (256-gives_bits) >> gives_before)));
  }}
}

function t_of_struct(OfferUnpacked memory __s) pure returns (OfferPacked) { unchecked {
  return pack(__s.prev, __s.next, __s.wants, __s.gives);
}}

function pack(uint __prev, uint __next, uint __wants, uint __gives) pure returns (OfferPacked) { unchecked {
  return OfferPacked.wrap(((((0
                              | ((__prev << (256-prev_bits)) >> prev_before))
                              | ((__next << (256-next_bits)) >> next_before))
                              | ((__wants << (256-wants_bits)) >> wants_before))
                              | ((__gives << (256-gives_bits)) >> gives_before)));
}}