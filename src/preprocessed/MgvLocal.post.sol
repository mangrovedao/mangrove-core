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

struct LocalUnpacked {
  bool active;
  uint fee;
  Density density;
  uint tickPosInLeaf;
  Field level0;
  Field level1;
  Field level2;
  uint kilo_offer_gasbase;
  bool lock;
  uint last;
}

//some type safety for each struct
type LocalPacked is uint;
using Library for LocalPacked global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////

import {Tick,TickLib,Field} from "mgv_lib/TickLib.sol";
import {Density, DensityLib} from "mgv_lib/DensityLib.sol";

using LocalPackedExtra for LocalPacked global;
using LocalUnpackedExtra for LocalUnpacked global;

library LocalPackedExtra {
  function densityFromFixed(LocalPacked local, uint densityFixed) internal pure returns (LocalPacked) { unchecked {
    return local.density(DensityLib.fromFixed(densityFixed));
  }}
  function offer_gasbase(LocalPacked local) internal pure returns (uint) { unchecked {
    return local.kilo_offer_gasbase() * 1e3;
  }}
  function offer_gasbase(LocalPacked local,uint val) internal pure returns (LocalPacked) { unchecked {
    return local.kilo_offer_gasbase(val/1e3);
  }}
  function tick(LocalPacked local) internal pure returns (Tick) {
    return TickLib.tickFromBranch(local.tickPosInLeaf(),local.level0(),local.level1(),local.level2());
  }
}

library LocalUnpackedExtra {
  function densityFromFixed(LocalUnpacked memory local, uint densityFixed) internal pure { unchecked {
    local.density = DensityLib.fromFixed(densityFixed);
  }}
  function offer_gasbase(LocalUnpacked memory local) internal pure returns (uint) { unchecked {
    return local.kilo_offer_gasbase * 1e3;
  }}
  function offer_gasbase(LocalUnpacked memory local,uint val) internal pure { unchecked {
    local.kilo_offer_gasbase = val/1e3;
  }}
  function tick(LocalUnpacked memory local) internal pure returns (Tick) {
    return TickLib.tickFromBranch(local.tickPosInLeaf,local.level0,local.level1,local.level2);
  }
}

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

// number of bits in each field
uint constant active_bits             = 1;
uint constant fee_bits                = 8;
uint constant density_bits            = 9;
uint constant tickPosInLeaf_bits      = 2;
uint constant level0_bits             = 64;
uint constant level1_bits             = 64;
uint constant level2_bits             = 64;
uint constant kilo_offer_gasbase_bits = 10;
uint constant lock_bits               = 1;
uint constant last_bits               = 32;

// number of bits before each field
uint constant active_before             = 0                         + 0;
uint constant fee_before                = active_before             + active_bits;
uint constant density_before            = fee_before                + fee_bits;
uint constant tickPosInLeaf_before      = density_before            + density_bits;
uint constant level0_before             = tickPosInLeaf_before      + tickPosInLeaf_bits;
uint constant level1_before             = level0_before             + level0_bits;
uint constant level2_before             = level1_before             + level1_bits;
uint constant kilo_offer_gasbase_before = level2_before             + level2_bits;
uint constant lock_before               = kilo_offer_gasbase_before + kilo_offer_gasbase_bits;
uint constant last_before               = lock_before               + lock_bits;

// focus-mask: 1s at field location, 0s elsewhere
uint constant active_mask_inv             = (ONES << 256 - active_bits) >> active_before;
uint constant fee_mask_inv                = (ONES << 256 - fee_bits) >> fee_before;
uint constant density_mask_inv            = (ONES << 256 - density_bits) >> density_before;
uint constant tickPosInLeaf_mask_inv      = (ONES << 256 - tickPosInLeaf_bits) >> tickPosInLeaf_before;
uint constant level0_mask_inv             = (ONES << 256 - level0_bits) >> level0_before;
uint constant level1_mask_inv             = (ONES << 256 - level1_bits) >> level1_before;
uint constant level2_mask_inv             = (ONES << 256 - level2_bits) >> level2_before;
uint constant kilo_offer_gasbase_mask_inv = (ONES << 256 - kilo_offer_gasbase_bits) >> kilo_offer_gasbase_before;
uint constant lock_mask_inv               = (ONES << 256 - lock_bits) >> lock_before;
uint constant last_mask_inv               = (ONES << 256 - last_bits) >> last_before;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant active_mask             = ~active_mask_inv;
uint constant fee_mask                = ~fee_mask_inv;
uint constant density_mask            = ~density_mask_inv;
uint constant tickPosInLeaf_mask      = ~tickPosInLeaf_mask_inv;
uint constant level0_mask             = ~level0_mask_inv;
uint constant level1_mask             = ~level1_mask_inv;
uint constant level2_mask             = ~level2_mask_inv;
uint constant kilo_offer_gasbase_mask = ~kilo_offer_gasbase_mask_inv;
uint constant lock_mask               = ~lock_mask_inv;
uint constant last_mask               = ~last_mask_inv;

// cast-mask: 0s followed by |field| trailing 1s
uint constant active_cast_mask             = ~(ONES << active_bits);
uint constant fee_cast_mask                = ~(ONES << fee_bits);
uint constant density_cast_mask            = ~(ONES << density_bits);
uint constant tickPosInLeaf_cast_mask      = ~(ONES << tickPosInLeaf_bits);
uint constant level0_cast_mask             = ~(ONES << level0_bits);
uint constant level1_cast_mask             = ~(ONES << level1_bits);
uint constant level2_cast_mask             = ~(ONES << level2_bits);
uint constant kilo_offer_gasbase_cast_mask = ~(ONES << kilo_offer_gasbase_bits);
uint constant lock_cast_mask               = ~(ONES << lock_bits);
uint constant last_cast_mask               = ~(ONES << last_bits);

// size-related error message
string constant active_size_error             = "mgv/config/active/1bits";
string constant fee_size_error                = "mgv/config/fee/8bits";
string constant density_size_error            = "mgv/config/density/9bits";
string constant tickPosInLeaf_size_error      = "mgv/config/tickPosInLeaf/2bits";
string constant level0_size_error             = "mgv/config/level0/64bits";
string constant level1_size_error             = "mgv/config/level1/64bits";
string constant level2_size_error             = "mgv/config/level2/64bits";
string constant kilo_offer_gasbase_size_error = "mgv/config/kilo_offer_gasbase/10bits";
string constant lock_size_error               = "mgv/config/lock/1bits";
string constant last_size_error               = "mgv/config/last/32bits";

library Library {
  // from packed to in-memory struct
  function to_struct(LocalPacked __packed) internal pure returns (LocalUnpacked memory __s) { unchecked {
    __s.active             = ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
    __s.fee                = uint(LocalPacked.unwrap(__packed) << fee_before) >> (256 - fee_bits);
    __s.density            = Density.wrap(uint(LocalPacked.unwrap(__packed) << density_before) >> (256 - density_bits));
    __s.tickPosInLeaf      = uint(LocalPacked.unwrap(__packed) << tickPosInLeaf_before) >> (256 - tickPosInLeaf_bits);
    __s.level0             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level0_before) >> (256 - level0_bits));
    __s.level1             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level1_before) >> (256 - level1_bits));
    __s.level2             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level2_before) >> (256 - level2_bits));
    __s.kilo_offer_gasbase = uint(LocalPacked.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
    __s.lock               = ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
    __s.last               = uint(LocalPacked.unwrap(__packed) << last_before) >> (256 - last_bits);
  }}

  // equality checking
  function eq(LocalPacked __packed1, LocalPacked __packed2) internal pure returns (bool) { unchecked {
    return LocalPacked.unwrap(__packed1) == LocalPacked.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(LocalPacked __packed) internal pure returns (bool __active, uint __fee, Density __density, uint __tickPosInLeaf, Field __level0, Field __level1, Field __level2, uint __kilo_offer_gasbase, bool __lock, uint __last) { unchecked {
    __active             = ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
    __fee                = uint(LocalPacked.unwrap(__packed) << fee_before) >> (256 - fee_bits);
    __density            = Density.wrap(uint(LocalPacked.unwrap(__packed) << density_before) >> (256 - density_bits));
    __tickPosInLeaf      = uint(LocalPacked.unwrap(__packed) << tickPosInLeaf_before) >> (256 - tickPosInLeaf_bits);
    __level0             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level0_before) >> (256 - level0_bits));
    __level1             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level1_before) >> (256 - level1_bits));
    __level2             = Field.wrap(uint(LocalPacked.unwrap(__packed) << level2_before) >> (256 - level2_bits));
    __kilo_offer_gasbase = uint(LocalPacked.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
    __lock               = ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
    __last               = uint(LocalPacked.unwrap(__packed) << last_before) >> (256 - last_bits);
  }}

  // getters
  function active(LocalPacked __packed) internal pure returns(bool) { unchecked {
    return ((LocalPacked.unwrap(__packed) & active_mask_inv) > 0);
  }}

  // setters
  function active(LocalPacked __packed,bool val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & active_mask) | (uint_of_bool(val) << (256 - active_bits)) >> active_before);
  }}
  
  function fee(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(LocalPacked.unwrap(__packed) << fee_before) >> (256 - fee_bits);
  }}

  // setters
  function fee(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & fee_mask) | (val << (256 - fee_bits)) >> fee_before);
  }}
  
  function density(LocalPacked __packed) internal pure returns(Density) { unchecked {
    return Density.wrap(uint(LocalPacked.unwrap(__packed) << density_before) >> (256 - density_bits));
  }}

  // setters
  function density(LocalPacked __packed,Density val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & density_mask) | (Density.unwrap(val) << (256 - density_bits)) >> density_before);
  }}
  
  function tickPosInLeaf(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(LocalPacked.unwrap(__packed) << tickPosInLeaf_before) >> (256 - tickPosInLeaf_bits);
  }}

  // setters
  function tickPosInLeaf(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & tickPosInLeaf_mask) | (val << (256 - tickPosInLeaf_bits)) >> tickPosInLeaf_before);
  }}
  
  function level0(LocalPacked __packed) internal pure returns(Field) { unchecked {
    return Field.wrap(uint(LocalPacked.unwrap(__packed) << level0_before) >> (256 - level0_bits));
  }}

  // setters
  function level0(LocalPacked __packed,Field val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & level0_mask) | (Field.unwrap(val) << (256 - level0_bits)) >> level0_before);
  }}
  
  function level1(LocalPacked __packed) internal pure returns(Field) { unchecked {
    return Field.wrap(uint(LocalPacked.unwrap(__packed) << level1_before) >> (256 - level1_bits));
  }}

  // setters
  function level1(LocalPacked __packed,Field val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & level1_mask) | (Field.unwrap(val) << (256 - level1_bits)) >> level1_before);
  }}
  
  function level2(LocalPacked __packed) internal pure returns(Field) { unchecked {
    return Field.wrap(uint(LocalPacked.unwrap(__packed) << level2_before) >> (256 - level2_bits));
  }}

  // setters
  function level2(LocalPacked __packed,Field val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & level2_mask) | (Field.unwrap(val) << (256 - level2_bits)) >> level2_before);
  }}
  
  function kilo_offer_gasbase(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(LocalPacked.unwrap(__packed) << kilo_offer_gasbase_before) >> (256 - kilo_offer_gasbase_bits);
  }}

  // setters
  function kilo_offer_gasbase(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & kilo_offer_gasbase_mask) | (val << (256 - kilo_offer_gasbase_bits)) >> kilo_offer_gasbase_before);
  }}
  
  function lock(LocalPacked __packed) internal pure returns(bool) { unchecked {
    return ((LocalPacked.unwrap(__packed) & lock_mask_inv) > 0);
  }}

  // setters
  function lock(LocalPacked __packed,bool val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & lock_mask) | (uint_of_bool(val) << (256 - lock_bits)) >> lock_before);
  }}
  
  function last(LocalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(LocalPacked.unwrap(__packed) << last_before) >> (256 - last_bits);
  }}

  // setters
  function last(LocalPacked __packed,uint val) internal pure returns(LocalPacked) { unchecked {
    return LocalPacked.wrap((LocalPacked.unwrap(__packed) & last_mask) | (val << (256 - last_bits)) >> last_before);
  }}
  
}

// from in-memory struct to packed
function t_of_struct(LocalUnpacked memory __s) pure returns (LocalPacked) { unchecked {
  return pack(__s.active, __s.fee, __s.density, __s.tickPosInLeaf, __s.level0, __s.level1, __s.level2, __s.kilo_offer_gasbase, __s.lock, __s.last);
}}

// from arguments to packed
function pack(bool __active, uint __fee, Density __density, uint __tickPosInLeaf, Field __level0, Field __level1, Field __level2, uint __kilo_offer_gasbase, bool __lock, uint __last) pure returns (LocalPacked) { unchecked {
  uint __packed;
  __packed |= (uint_of_bool(__active) << (256 - active_bits)) >> active_before;
  __packed |= (__fee << (256 - fee_bits)) >> fee_before;
  __packed |= (Density.unwrap(__density) << (256 - density_bits)) >> density_before;
  __packed |= (__tickPosInLeaf << (256 - tickPosInLeaf_bits)) >> tickPosInLeaf_before;
  __packed |= (Field.unwrap(__level0) << (256 - level0_bits)) >> level0_before;
  __packed |= (Field.unwrap(__level1) << (256 - level1_bits)) >> level1_before;
  __packed |= (Field.unwrap(__level2) << (256 - level2_bits)) >> level2_before;
  __packed |= (__kilo_offer_gasbase << (256 - kilo_offer_gasbase_bits)) >> kilo_offer_gasbase_before;
  __packed |= (uint_of_bool(__lock) << (256 - lock_bits)) >> lock_before;
  __packed |= (__last << (256 - last_bits)) >> last_before;
  return LocalPacked.wrap(__packed);
}}

// input checking
function active_check(bool __active) pure returns (bool) { unchecked {
  return (uint_of_bool(__active) & active_cast_mask) == uint_of_bool(__active);
}}
function fee_check(uint __fee) pure returns (bool) { unchecked {
  return (__fee & fee_cast_mask) == __fee;
}}
function density_check(Density __density) pure returns (bool) { unchecked {
  return (Density.unwrap(__density) & density_cast_mask) == Density.unwrap(__density);
}}
function tickPosInLeaf_check(uint __tickPosInLeaf) pure returns (bool) { unchecked {
  return (__tickPosInLeaf & tickPosInLeaf_cast_mask) == __tickPosInLeaf;
}}
function level0_check(Field __level0) pure returns (bool) { unchecked {
  return (Field.unwrap(__level0) & level0_cast_mask) == Field.unwrap(__level0);
}}
function level1_check(Field __level1) pure returns (bool) { unchecked {
  return (Field.unwrap(__level1) & level1_cast_mask) == Field.unwrap(__level1);
}}
function level2_check(Field __level2) pure returns (bool) { unchecked {
  return (Field.unwrap(__level2) & level2_cast_mask) == Field.unwrap(__level2);
}}
function kilo_offer_gasbase_check(uint __kilo_offer_gasbase) pure returns (bool) { unchecked {
  return (__kilo_offer_gasbase & kilo_offer_gasbase_cast_mask) == __kilo_offer_gasbase;
}}
function lock_check(bool __lock) pure returns (bool) { unchecked {
  return (uint_of_bool(__lock) & lock_cast_mask) == uint_of_bool(__lock);
}}
function last_check(uint __last) pure returns (bool) { unchecked {
  return (__last & last_cast_mask) == __last;
}}

