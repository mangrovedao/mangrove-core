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

struct OfferDetailUnpacked {
  address maker;
  uint gasreq;
  uint kilo_offer_gasbase;
  uint gasprice;
}

//some type safety for each struct
type OfferDetail is uint;
using OfferDetailLib for OfferDetail global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////
import {OfferDetailExtra,OfferDetailUnpackedExtra} from "@mgv/lib/core/OfferDetailExtra.sol";
using OfferDetailExtra for OfferDetail global;
using OfferDetailUnpackedExtra for OfferDetailUnpacked global;

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

library OfferDetailLib {

  // number of bits in each field
  uint constant maker_bits              = 160;
  uint constant gasreq_bits             = 24;
  uint constant kilo_offer_gasbase_bits = 9;
  uint constant gasprice_bits           = 26;

  // number of bits before each field
  uint constant maker_before              = 0                         + 0;
  uint constant gasreq_before             = maker_before              + maker_bits;
  uint constant kilo_offer_gasbase_before = gasreq_before             + gasreq_bits;
  uint constant gasprice_before           = kilo_offer_gasbase_before + kilo_offer_gasbase_bits;

  // focus-mask: 1s at field location, 0s elsewhere
  uint constant maker_mask_inv              = (ONES << 256 - maker_bits) >> maker_before;
  uint constant gasreq_mask_inv             = (ONES << 256 - gasreq_bits) >> gasreq_before;
  uint constant kilo_offer_gasbase_mask_inv = (ONES << 256 - kilo_offer_gasbase_bits) >> kilo_offer_gasbase_before;
  uint constant gasprice_mask_inv           = (ONES << 256 - gasprice_bits) >> gasprice_before;

  // cleanup-mask: 0s at field location, 1s elsewhere
  uint constant maker_mask              = ~maker_mask_inv;
  uint constant gasreq_mask             = ~gasreq_mask_inv;
  uint constant kilo_offer_gasbase_mask = ~kilo_offer_gasbase_mask_inv;
  uint constant gasprice_mask           = ~gasprice_mask_inv;

  // cast-mask: 0s followed by |field| trailing 1s
  uint constant maker_cast_mask              = ~(ONES << maker_bits);
  uint constant gasreq_cast_mask             = ~(ONES << gasreq_bits);
  uint constant kilo_offer_gasbase_cast_mask = ~(ONES << kilo_offer_gasbase_bits);
  uint constant gasprice_cast_mask           = ~(ONES << gasprice_bits);

  // size-related error message
  string constant maker_size_error              = "mgv/config/maker/160bits";
  string constant gasreq_size_error             = "mgv/config/gasreq/24bits";
  string constant kilo_offer_gasbase_size_error = "mgv/config/kilo_offer_gasbase/9bits";
  string constant gasprice_size_error           = "mgv/config/gasprice/26bits";

  // from packed to in-memory struct
  function to_struct(OfferDetail __packed) internal pure returns (OfferDetailUnpacked memory __s) { unchecked {
    __s.maker              = address(uint160(uint(OfferDetail.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
    __s.gasreq             = uint(OfferDetail.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
    __s.kilo_offer_gasbase = uint(OfferDetail.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
    __s.gasprice           = uint(OfferDetail.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // equality checking
  function eq(OfferDetail __packed1, OfferDetail __packed2) internal pure returns (bool) { unchecked {
    return OfferDetail.unwrap(__packed1) == OfferDetail.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(OfferDetail __packed) internal pure returns (address __maker, uint __gasreq, uint __kilo_offer_gasbase, uint __gasprice) { unchecked {
    __maker              = address(uint160(uint(OfferDetail.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
    __gasreq             = uint(OfferDetail.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
    __kilo_offer_gasbase = uint(OfferDetail.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
    __gasprice           = uint(OfferDetail.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // getters
  function maker(OfferDetail __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint(OfferDetail.unwrap(__packed) << maker_before) >> (256 - maker_bits)));
  }}

  // setters
  function maker(OfferDetail __packed,address val) internal pure returns(OfferDetail) { unchecked {
    return OfferDetail.wrap((OfferDetail.unwrap(__packed) & maker_mask) | (uint(uint160(val)) << (256 - maker_bits)) >> maker_before);
  }}
  
  function gasreq(OfferDetail __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetail.unwrap(__packed) << gasreq_before) >> (256 - gasreq_bits);
  }}

  // setters
  function gasreq(OfferDetail __packed,uint val) internal pure returns(OfferDetail) { unchecked {
    return OfferDetail.wrap((OfferDetail.unwrap(__packed) & gasreq_mask) | (val << (256 - gasreq_bits)) >> gasreq_before);
  }}
  
  function kilo_offer_gasbase(OfferDetail __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetail.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
  }}

  // setters
  function kilo_offer_gasbase(OfferDetail __packed,uint val) internal pure returns(OfferDetail) { unchecked {
    return OfferDetail.wrap((OfferDetail.unwrap(__packed) & kilo_offer_gasbase_mask) | (val << (256 - kilo_offer_gasbase_bits)) >> kilo_offer_gasbase_before);
  }}
  
  function gasprice(OfferDetail __packed) internal pure returns(uint) { unchecked {
    return uint(OfferDetail.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // setters
  function gasprice(OfferDetail __packed,uint val) internal pure returns(OfferDetail) { unchecked {
    return OfferDetail.wrap((OfferDetail.unwrap(__packed) & gasprice_mask) | (val << (256 - gasprice_bits)) >> gasprice_before);
  }}
  

  // from in-memory struct to packed
  function t_of_struct(OfferDetailUnpacked memory __s) internal pure returns (OfferDetail) { unchecked {
    return pack(__s.maker, __s.gasreq, __s.kilo_offer_gasbase, __s.gasprice);
  }}

  // from arguments to packed
  function pack(address __maker, uint __gasreq, uint __kilo_offer_gasbase, uint __gasprice) internal pure returns (OfferDetail) { unchecked {
    uint __packed;
    __packed |= (uint(uint160(__maker)) << (256 - maker_bits)) >> maker_before;
    __packed |= (__gasreq << (256 - gasreq_bits)) >> gasreq_before;
    __packed |= (__kilo_offer_gasbase << (256 - kilo_offer_gasbase_bits)) >> kilo_offer_gasbase_before;
    __packed |= (__gasprice << (256 - gasprice_bits)) >> gasprice_before;
    return OfferDetail.wrap(__packed);
  }}

  // input checking
  function maker_check(address __maker) internal pure returns (bool) { unchecked {
    return (uint(uint160(__maker)) & maker_cast_mask) == uint(uint160(__maker));
  }}
  function gasreq_check(uint __gasreq) internal pure returns (bool) { unchecked {
    return (__gasreq & gasreq_cast_mask) == __gasreq;
  }}
  function kilo_offer_gasbase_check(uint __kilo_offer_gasbase) internal pure returns (bool) { unchecked {
    return (__kilo_offer_gasbase & kilo_offer_gasbase_cast_mask) == __kilo_offer_gasbase;
  }}
  function gasprice_check(uint __gasprice) internal pure returns (bool) { unchecked {
    return (__gasprice & gasprice_cast_mask) == __gasprice;
  }}
}

