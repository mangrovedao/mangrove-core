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

struct OfferDetailUnpacked {
  address maker;
  uint gasreq;
  uint offer_gasbase;
  uint gasprice;
}

//some type safety for each struct
type OfferDetailPacked is uint;
using Library for OfferDetailPacked global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

// number of bits in each field
uint constant maker_bits         = 160;
uint constant gasreq_bits        = 24;
uint constant offer_gasbase_bits = 24;
uint constant gasprice_bits      = 16;

// number of bits before each field
uint constant maker_before         = 0                    + 0;
uint constant gasreq_before        = maker_before         + maker_bits;
uint constant offer_gasbase_before = gasreq_before        + gasreq_bits;
uint constant gasprice_before      = offer_gasbase_before + offer_gasbase_bits;

// focus-mask: 1s at field location, 0s elsewhere
uint constant maker_mask_inv         = (ONES << 256 - maker_bits) >> maker_before;
uint constant gasreq_mask_inv        = (ONES << 256 - gasreq_bits) >> gasreq_before;
uint constant offer_gasbase_mask_inv = (ONES << 256 - offer_gasbase_bits) >> offer_gasbase_before;
uint constant gasprice_mask_inv      = (ONES << 256 - gasprice_bits) >> gasprice_before;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant maker_mask         = ~maker_mask_inv;
uint constant gasreq_mask        = ~gasreq_mask_inv;
uint constant offer_gasbase_mask = ~offer_gasbase_mask_inv;
uint constant gasprice_mask      = ~gasprice_mask_inv;

// cast-mask: 0s followed by |field| trailing 1s
uint constant maker_cast_mask         = ~(ONES << maker_bits);
uint constant gasreq_cast_mask        = ~(ONES << gasreq_bits);
uint constant offer_gasbase_cast_mask = ~(ONES << offer_gasbase_bits);
uint constant gasprice_cast_mask      = ~(ONES << gasprice_bits);

// size-related error message
string constant maker_size_error         = "mgv/config/maker/160bits";
string constant gasreq_size_error        = "mgv/config/gasreq/24bits";
string constant offer_gasbase_size_error = "mgv/config/offer_gasbase/24bits";
string constant gasprice_size_error      = "mgv/config/gasprice/16bits";

library Library {
  // from packed to in-memory struct
  function to_struct(OfferDetailPacked __packed) internal pure returns (OfferDetailUnpacked memory __s) { unchecked {
    __s.maker         = address(uint160(uint(OfferDetailPacked.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
    __s.gasreq        = uint(OfferDetailPacked.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
    __s.offer_gasbase = uint(OfferDetailPacked.unwrap(__packed) << offer_gasbase_before) >> (256 - offer_gasbase_bits);
    __s.gasprice      = uint(OfferDetailPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // equality checking
  function eq(OfferDetailPacked __packed1, OfferDetailPacked __packed2) internal pure returns (bool) { unchecked {
    return OfferDetailPacked.unwrap(__packed1) == OfferDetailPacked.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(OfferDetailPacked __packed) internal pure returns (address __maker, uint __gasreq, uint __offer_gasbase, uint __gasprice) { unchecked {
    __maker         = address(uint160(uint(OfferDetailPacked.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
    __gasreq        = uint(OfferDetailPacked.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
    __offer_gasbase = uint(OfferDetailPacked.unwrap(__packed) << offer_gasbase_before) >> (256 - offer_gasbase_bits);
    __gasprice      = uint(OfferDetailPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // getters
  function maker(OfferDetailPacked __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint(OfferDetailPacked.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
  }}

  // setters
  function maker(OfferDetailPacked __packed,address val) internal pure returns(OfferDetailPacked) { unchecked {
    return OfferDetailPacked.wrap((OfferDetailPacked.unwrap(__packed) & maker_mask) | (uint(uint160(val)) << (256 - maker_bits)) >> maker_before);
  }}
  
  function gasreq(OfferDetailPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetailPacked.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
  }}

  // setters
  function gasreq(OfferDetailPacked __packed,uint val) internal pure returns(OfferDetailPacked) { unchecked {
    return OfferDetailPacked.wrap((OfferDetailPacked.unwrap(__packed) & gasreq_mask) | (val << (256 - gasreq_bits)) >> gasreq_before);
  }}
  
  function offer_gasbase(OfferDetailPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetailPacked.unwrap(__packed) << offer_gasbase_before) >> (256 - offer_gasbase_bits);
  }}

  // setters
  function offer_gasbase(OfferDetailPacked __packed,uint val) internal pure returns(OfferDetailPacked) { unchecked {
    return OfferDetailPacked.wrap((OfferDetailPacked.unwrap(__packed) & offer_gasbase_mask) | (val << (256 - offer_gasbase_bits)) >> offer_gasbase_before);
  }}
  
  function gasprice(OfferDetailPacked __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetailPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // setters
  function gasprice(OfferDetailPacked __packed,uint val) internal pure returns(OfferDetailPacked) { unchecked {
    return OfferDetailPacked.wrap((OfferDetailPacked.unwrap(__packed) & gasprice_mask) | (val << (256 - gasprice_bits)) >> gasprice_before);
  }}
  
}

// from in-memory struct to packed
function t_of_struct(OfferDetailUnpacked memory __s) pure returns (OfferDetailPacked) { unchecked {
  return pack(__s.maker, __s.gasreq, __s.offer_gasbase, __s.gasprice);
}}

// from arguments to packed
function pack(address __maker, uint __gasreq, uint __offer_gasbase, uint __gasprice) pure returns (OfferDetailPacked) { unchecked {
  uint __packed;
  __packed |= (uint(uint160(__maker)) << (256 - maker_bits)) >> maker_before;
  __packed |= (__gasreq << (256 - gasreq_bits)) >> gasreq_before;
  __packed |= (__offer_gasbase << (256 - offer_gasbase_bits)) >> offer_gasbase_before;
  __packed |= (__gasprice << (256 - gasprice_bits)) >> gasprice_before;
  return OfferDetailPacked.wrap(__packed);
}}

// input checking
function maker_check(address __maker) pure returns (bool) { unchecked {
  return (uint(uint160(__maker)) & maker_cast_mask) == uint(uint160(__maker));
}}
function gasreq_check(uint __gasreq) pure returns (bool) { unchecked {
  return (__gasreq & gasreq_cast_mask) == __gasreq;
}}
function offer_gasbase_check(uint __offer_gasbase) pure returns (bool) { unchecked {
  return (__offer_gasbase & offer_gasbase_cast_mask) == __offer_gasbase;
}}
function gasprice_check(uint __gasprice) pure returns (bool) { unchecked {
  return (__gasprice & gasprice_cast_mask) == __gasprice;
}}

