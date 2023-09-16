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
import "mgv_lib/Constants.sol";

struct OfferUnpacked {
  uint prev;
  uint next;
  int logPrice;
  uint gives;
}

//some type safety for each struct
type OfferPacked is uint;
using Library for OfferPacked global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////
import "mgv_lib/TickLib.sol";
import "mgv_lib/LogPriceLib.sol";
import "mgv_lib/LogPriceConversionLib.sol";

using OfferPackedExtra for OfferPacked global;
using OfferUnpackedExtra for OfferUnpacked global;

// cleanup-mask: 0s at location of fields to hide from maker, 1s elsewhere
uint constant HIDE_FIELDS_FROM_MAKER_MASK = ~(prev_mask_inv | next_mask_inv);

library OfferPackedExtra {
  // Compute wants from tick and gives
  function wants(OfferPacked offer) internal pure returns (uint) {
    return LogPriceLib.inboundFromOutbound(offer.logPrice(),offer.gives());
  }
  // Sugar to test offer liveness
  function isLive(OfferPacked offer) internal pure returns (bool resp) {
    uint gives = offer.gives();
    assembly {
      resp := iszero(iszero(gives))
    }
  }
  function tick(OfferPacked offer, uint tickScale) internal pure returns (Tick) {
    // Offers are always stored with a logPrice that corresponds exactly to a tick
    return TickLib.fromTickAlignedLogPrice(offer.logPrice(), tickScale);
  }
  function clearFieldsForMaker(OfferPacked offer) internal pure returns (OfferPacked) {
    unchecked {
      return OfferPacked.wrap(
        OfferPacked.unwrap(offer)
        & HIDE_FIELDS_FROM_MAKER_MASK);
    }
  }
}

library OfferUnpackedExtra {
  // Compute wants from tick and gives
  function wants(OfferUnpacked memory offer) internal pure returns (uint) {
    return LogPriceLib.inboundFromOutbound(offer.logPrice,offer.gives);
  }
  // Sugar to test offer liveness
  function isLive(OfferUnpacked memory offer) internal pure returns (bool resp) {
    uint gives = offer.gives;
    assembly {
      resp := iszero(iszero(gives))
    }
  }
  function tick(OfferUnpacked memory offer, uint tickScale) internal pure returns (Tick) {
    // Offers are always stored with a logPrice that corresponds exactly to a tick
    return TickLib.fromTickAlignedLogPrice(offer.logPrice, tickScale);
  }

}

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

// number of bits in each field
uint constant prev_bits     = 32;
uint constant next_bits     = 32;
uint constant logPrice_bits = 24;
uint constant gives_bits    = 96;

// number of bits before each field
uint constant prev_before     = 0               + 0;
uint constant next_before     = prev_before     + prev_bits;
uint constant logPrice_before = next_before     + next_bits;
uint constant gives_before    = logPrice_before + logPrice_bits;

// focus-mask: 1s at field location, 0s elsewhere
uint constant prev_mask_inv     = (ONES << 256 - prev_bits) >> prev_before;
uint constant next_mask_inv     = (ONES << 256 - next_bits) >> next_before;
uint constant logPrice_mask_inv = (ONES << 256 - logPrice_bits) >> logPrice_before;
uint constant gives_mask_inv    = (ONES << 256 - gives_bits) >> gives_before;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant prev_mask     = ~prev_mask_inv;
uint constant next_mask     = ~next_mask_inv;
uint constant logPrice_mask = ~logPrice_mask_inv;
uint constant gives_mask    = ~gives_mask_inv;

// cast-mask: 0s followed by |field| trailing 1s
uint constant prev_cast_mask     = ~(ONES << prev_bits);
uint constant next_cast_mask     = ~(ONES << next_bits);
uint constant logPrice_cast_mask = ~(ONES << logPrice_bits);
uint constant gives_cast_mask    = ~(ONES << gives_bits);

// size-related error message
string constant prev_size_error     = "mgv/config/prev/32bits";
string constant next_size_error     = "mgv/config/next/32bits";
string constant logPrice_size_error = "mgv/config/logPrice/24bits";
string constant gives_size_error    = "mgv/config/gives/96bits";

library Library {
  // from packed to in-memory struct
  function to_struct(OfferPacked __packed) internal pure returns (OfferUnpacked memory __s) { unchecked {
    __s.prev     = uint(OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __s.next     = uint(OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
    __s.logPrice = int(int(OfferPacked.unwrap(__packed) << logPrice_before) >> (256 - logPrice_bits));
    __s.gives    = uint(OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // equality checking
  function eq(OfferPacked __packed1, OfferPacked __packed2) internal pure returns (bool) { unchecked {
    return OfferPacked.unwrap(__packed1) == OfferPacked.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(OfferPacked __packed) internal pure returns (uint __prev, uint __next, int __logPrice, uint __gives) { unchecked {
    __prev     = uint(OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
    __next     = uint(OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
    __logPrice = int(int(OfferPacked.unwrap(__packed) << logPrice_before) >> (256 - logPrice_bits));
    __gives    = uint(OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // getters
  function prev(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferPacked.unwrap(__packed) << prev_before) >> (256 - prev_bits);
  }}

  // setters
  function prev(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & prev_mask) | (val << (256 - prev_bits)) >> prev_before);
  }}
  
  function next(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferPacked.unwrap(__packed) << next_before) >> (256 - next_bits);
  }}

  // setters
  function next(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & next_mask) | (val << (256 - next_bits)) >> next_before);
  }}
  
  function logPrice(OfferPacked __packed) internal pure returns(int) { unchecked {
    return int(int(OfferPacked.unwrap(__packed) << logPrice_before) >> (256 - logPrice_bits));
  }}

  // setters
  function logPrice(OfferPacked __packed,int val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & logPrice_mask) | (uint(val) << (256 - logPrice_bits)) >> logPrice_before);
  }}
  
  function gives(OfferPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferPacked.unwrap(__packed) << gives_before) >> (256 - gives_bits);
  }}

  // setters
  function gives(OfferPacked __packed,uint val) internal pure returns(OfferPacked) { unchecked {
    return OfferPacked.wrap((OfferPacked.unwrap(__packed) & gives_mask) | (val << (256 - gives_bits)) >> gives_before);
  }}
  
}

// from in-memory struct to packed
function t_of_struct(OfferUnpacked memory __s) pure returns (OfferPacked) { unchecked {
  return pack(__s.prev, __s.next, __s.logPrice, __s.gives);
}}

// from arguments to packed
function pack(uint __prev, uint __next, int __logPrice, uint __gives) pure returns (OfferPacked) { unchecked {
  uint __packed;
  __packed |= (__prev << (256 - prev_bits)) >> prev_before;
  __packed |= (__next << (256 - next_bits)) >> next_before;
  __packed |= (uint(__logPrice) << (256 - logPrice_bits)) >> logPrice_before;
  __packed |= (__gives << (256 - gives_bits)) >> gives_before;
  return OfferPacked.wrap(__packed);
}}

// input checking
function prev_check(uint __prev) pure returns (bool) { unchecked {
  return (__prev & prev_cast_mask) == __prev;
}}
function next_check(uint __next) pure returns (bool) { unchecked {
  return (__next & next_cast_mask) == __next;
}}
function logPrice_check(int __logPrice) pure returns (bool) { unchecked {
  return (uint(__logPrice) & logPrice_cast_mask) == uint(__logPrice);
}}
function gives_check(uint __gives) pure returns (bool) { unchecked {
  return (__gives & gives_cast_mask) == __gives;
}}

