// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly ("memory-safe") { u := b }
}
import "@mgv/lib/core/Constants.sol";

struct OfferUnpacked {
  uint prev;
  uint next;
  Tick tick;
  uint gives;
}

//some type safety for each struct
type Offer is uint;
using OfferLib for Offer global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////
import {Bin} from "@mgv/lib/core/TickTreeLib.sol";
import {Tick} from "@mgv/lib/core/TickLib.sol";
import {OfferExtra,OfferUnpackedExtra} from "@mgv/lib/core/OfferExtra.sol";

using OfferExtra for Offer global;
using OfferUnpackedExtra for OfferUnpacked global;

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

library OfferLib {

  // number of bits in each field
  uint constant prev_bits  = 32;
  uint constant next_bits  = 32;
  uint constant tick_bits  = 21;
  uint constant gives_bits = 127;

  // number of bits before each field
  uint constant prev_before  = 0           + 0;
  uint constant next_before  = prev_before + prev_bits;
  uint constant tick_before  = next_before + next_bits;
  uint constant gives_before = tick_before + tick_bits;

  // focus-mask: 1s at field location, 0s elsewhere
  uint constant prev_mask_inv  = (ONES << 256 - prev_bits) >> prev_before;
  uint constant next_mask_inv  = (ONES << 256 - next_bits) >> next_before;
  uint constant tick_mask_inv  = (ONES << 256 - tick_bits) >> tick_before;
  uint constant gives_mask_inv = (ONES << 256 - gives_bits) >> gives_before;

  // cleanup-mask: 0s at field location, 1s elsewhere
  uint constant prev_mask  = ~prev_mask_inv;
  uint constant next_mask  = ~next_mask_inv;
  uint constant tick_mask  = ~tick_mask_inv;
  uint constant gives_mask = ~gives_mask_inv;

  // cast-mask: 0s followed by |field| trailing 1s
  uint constant prev_cast_mask  = ~(ONES << prev_bits);
  uint constant next_cast_mask  = ~(ONES << next_bits);
  uint constant tick_cast_mask  = ~(ONES << tick_bits);
  uint constant gives_cast_mask = ~(ONES << gives_bits);

  // size-related error message
  string constant prev_size_error  = "mgv/config/prev/32bits";
  string constant next_size_error  = "mgv/config/next/32bits";
  string constant tick_size_error  = "mgv/config/tick/21bits";
  string constant gives_size_error = "mgv/config/gives/127bits";

  // from packed to in-memory struct
  function to_struct(Offer __packed) internal pure returns (OfferUnpacked memory __s) { unchecked {
    __s.prev  = uint(Offer.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __s.next  = uint(Offer.unwrap(__packed) << next_before) >> (256 - next_bits);
    __s.tick  = Tick.wrap(int(int(Offer.unwrap(__packed) << tick_before) >> (256 - tick_bits)));
    __s.gives = uint(Offer.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // equality checking
  function eq(Offer __packed1, Offer __packed2) internal pure returns (bool) { unchecked {
    return Offer.unwrap(__packed1) == Offer.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(Offer __packed) internal pure returns (uint __prev, uint __next, Tick __tick, uint __gives) { unchecked {
    __prev  = uint(Offer.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __next  = uint(Offer.unwrap(__packed) << next_before) >> (256 - next_bits);
    __tick  = Tick.wrap(int(int(Offer.unwrap(__packed) << tick_before) >> (256 - tick_bits)));
    __gives = uint(Offer.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // getters
  function prev(Offer __packed) internal pure returns(uint) { unchecked {
    return uint(Offer.unwrap(__packed) << prev_before) >> (256 - prev_bits);
  }}

  // setters
  function prev(Offer __packed,uint val) internal pure returns(Offer) { unchecked {
    return Offer.wrap((Offer.unwrap(__packed) & prev_mask) | (val << (256 - prev_bits)) >> prev_before);
  }}
  
  function next(Offer __packed) internal pure returns(uint) { unchecked {
    return uint(Offer.unwrap(__packed) << next_before) >> (256 - next_bits);
  }}

  // setters
  function next(Offer __packed,uint val) internal pure returns(Offer) { unchecked {
    return Offer.wrap((Offer.unwrap(__packed) & next_mask) | (val << (256 - next_bits)) >> next_before);
  }}
  
  function tick(Offer __packed) internal pure returns(Tick) { unchecked {
    return Tick.wrap(int(int(Offer.unwrap(__packed) << tick_before) >> (256 - tick_bits)));
  }}

  // setters
  function tick(Offer __packed,Tick val) internal pure returns(Offer) { unchecked {
    return Offer.wrap((Offer.unwrap(__packed) & tick_mask) | (uint(Tick.unwrap(val)) << (256 - tick_bits)) >> tick_before);
  }}
  
  function gives(Offer __packed) internal pure returns(uint) { unchecked {
    return uint(Offer.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // setters
  function gives(Offer __packed,uint val) internal pure returns(Offer) { unchecked {
    return Offer.wrap((Offer.unwrap(__packed) & gives_mask) | (val << (256 - gives_bits)) >> gives_before);
  }}
  

  // from in-memory struct to packed
  function t_of_struct(OfferUnpacked memory __s) internal pure returns (Offer) { unchecked {
    return pack(__s.prev, __s.next, __s.tick, __s.gives);
  }}

  // from arguments to packed
  function pack(uint __prev, uint __next, Tick __tick, uint __gives) internal pure returns (Offer) { unchecked {
    uint __packed;
    __packed |= (__prev << (256 - prev_bits)) >> prev_before;
    __packed |= (__next << (256 - next_bits)) >> next_before;
    __packed |= (uint(Tick.unwrap(__tick)) << (256 - tick_bits)) >> tick_before;
    __packed |= (__gives << (256 - gives_bits)) >> gives_before;
    return Offer.wrap(__packed);
  }}

  // input checking
  function prev_check(uint __prev) internal pure returns (bool) { unchecked {
    return (__prev & prev_cast_mask) == __prev;
  }}
  function next_check(uint __next) internal pure returns (bool) { unchecked {
    return (__next & next_cast_mask) == __next;
  }}
  function tick_check(Tick __tick) internal pure returns (bool) { unchecked {
    return (uint(Tick.unwrap(__tick)) & tick_cast_mask) == uint(Tick.unwrap(__tick));
  }}
  function gives_check(uint __gives) internal pure returns (bool) { unchecked {
    return (__gives & gives_cast_mask) == __gives;
  }}
}

