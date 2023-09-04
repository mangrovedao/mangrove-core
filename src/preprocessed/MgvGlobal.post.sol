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

struct GlobalUnpacked {
  address monitor;
  bool useOracle;
  bool notify;
  uint gasprice;
  uint gasmax;
  bool dead;
}

//some type safety for each struct
type GlobalPacked is uint;
using Library for GlobalPacked global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

// number of bits in each field
uint constant monitor_bits   = 160;
uint constant useOracle_bits = 1;
uint constant notify_bits    = 1;
uint constant gasprice_bits  = 16;
uint constant gasmax_bits    = 24;
uint constant dead_bits      = 1;

// number of bits before each field
uint constant monitor_before   = 0                + 0;
uint constant useOracle_before = monitor_before   + monitor_bits;
uint constant notify_before    = useOracle_before + useOracle_bits;
uint constant gasprice_before  = notify_before    + notify_bits;
uint constant gasmax_before    = gasprice_before  + gasprice_bits;
uint constant dead_before      = gasmax_before    + gasmax_bits;

// focus-mask: 1s at field location, 0s elsewhere
uint constant monitor_mask_inv   = (ONES << 256 - monitor_bits) >> monitor_before;
uint constant useOracle_mask_inv = (ONES << 256 - useOracle_bits) >> useOracle_before;
uint constant notify_mask_inv    = (ONES << 256 - notify_bits) >> notify_before;
uint constant gasprice_mask_inv  = (ONES << 256 - gasprice_bits) >> gasprice_before;
uint constant gasmax_mask_inv    = (ONES << 256 - gasmax_bits) >> gasmax_before;
uint constant dead_mask_inv      = (ONES << 256 - dead_bits) >> dead_before;

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant monitor_mask   = ~monitor_mask_inv;
uint constant useOracle_mask = ~useOracle_mask_inv;
uint constant notify_mask    = ~notify_mask_inv;
uint constant gasprice_mask  = ~gasprice_mask_inv;
uint constant gasmax_mask    = ~gasmax_mask_inv;
uint constant dead_mask      = ~dead_mask_inv;

// cast-mask: 0s followed by |field| trailing 1s
uint constant monitor_cast_mask   = ~(ONES << monitor_bits);
uint constant useOracle_cast_mask = ~(ONES << useOracle_bits);
uint constant notify_cast_mask    = ~(ONES << notify_bits);
uint constant gasprice_cast_mask  = ~(ONES << gasprice_bits);
uint constant gasmax_cast_mask    = ~(ONES << gasmax_bits);
uint constant dead_cast_mask      = ~(ONES << dead_bits);

// size-related error message
string constant monitor_size_error   = "mgv/config/monitor/160bits";
string constant useOracle_size_error = "mgv/config/useOracle/1bits";
string constant notify_size_error    = "mgv/config/notify/1bits";
string constant gasprice_size_error  = "mgv/config/gasprice/16bits";
string constant gasmax_size_error    = "mgv/config/gasmax/24bits";
string constant dead_size_error      = "mgv/config/dead/1bits";

library Library {
  // from packed to in-memory struct
  function to_struct(GlobalPacked __packed) internal pure returns (GlobalUnpacked memory __s) { unchecked {
    __s.monitor   = address(uint160(uint(GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __s.useOracle = ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
    __s.notify    = ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
    __s.gasprice  = uint(GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __s.gasmax    = uint(GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __s.dead      = ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  // equality checking
  function eq(GlobalPacked __packed1, GlobalPacked __packed2) internal pure returns (bool) { unchecked {
    return GlobalPacked.unwrap(__packed1) == GlobalPacked.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(GlobalPacked __packed) internal pure returns (address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) { unchecked {
    __monitor   = address(uint160(uint(GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __useOracle = ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
    __notify    = ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
    __gasprice  = uint(GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __gasmax    = uint(GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __dead      = ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  // getters
  function monitor(GlobalPacked __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint(GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
  }}

  // setters
  function monitor(GlobalPacked __packed,address val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & monitor_mask) | (uint(uint160(val)) << (256 - monitor_bits)) >> monitor_before);
  }}
  
  function useOracle(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
  }}

  // setters
  function useOracle(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & useOracle_mask) | (uint_of_bool(val) << (256 - useOracle_bits)) >> useOracle_before);
  }}
  
  function notify(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
  }}

  // setters
  function notify(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & notify_mask) | (uint_of_bool(val) << (256 - notify_bits)) >> notify_before);
  }}
  
  function gasprice(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // setters
  function gasprice(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & gasprice_mask) | (val << (256 - gasprice_bits)) >> gasprice_before);
  }}
  
  function gasmax(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return uint(GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
  }}

  // setters
  function gasmax(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & gasmax_mask) | (val << (256 - gasmax_bits)) >> gasmax_before);
  }}
  
  function dead(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  // setters
  function dead(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & dead_mask) | (uint_of_bool(val) << (256 - dead_bits)) >> dead_before);
  }}
  
}

// from in-memory struct to packed
function t_of_struct(GlobalUnpacked memory __s) pure returns (GlobalPacked) { unchecked {
  return pack(__s.monitor, __s.useOracle, __s.notify, __s.gasprice, __s.gasmax, __s.dead);
}}

// from arguments to packed
function pack(address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) pure returns (GlobalPacked) { unchecked {
  uint __packed;
  __packed |= (uint(uint160(__monitor)) << (256 - monitor_bits)) >> monitor_before;
  __packed |= (uint_of_bool(__useOracle) << (256 - useOracle_bits)) >> useOracle_before;
  __packed |= (uint_of_bool(__notify) << (256 - notify_bits)) >> notify_before;
  __packed |= (__gasprice << (256 - gasprice_bits)) >> gasprice_before;
  __packed |= (__gasmax << (256 - gasmax_bits)) >> gasmax_before;
  __packed |= (uint_of_bool(__dead) << (256 - dead_bits)) >> dead_before;
  return GlobalPacked.wrap(__packed);
}}

// input checking
function monitor_check(address __monitor) pure returns (bool) { unchecked {
  return (uint(uint160(__monitor)) & monitor_cast_mask) == uint(uint160(__monitor));
}}
function useOracle_check(bool __useOracle) pure returns (bool) { unchecked {
  return (uint_of_bool(__useOracle) & useOracle_cast_mask) == uint_of_bool(__useOracle);
}}
function notify_check(bool __notify) pure returns (bool) { unchecked {
  return (uint_of_bool(__notify) & notify_cast_mask) == uint_of_bool(__notify);
}}
function gasprice_check(uint __gasprice) pure returns (bool) { unchecked {
  return (__gasprice & gasprice_cast_mask) == __gasprice;
}}
function gasmax_check(uint __gasmax) pure returns (bool) { unchecked {
  return (__gasmax & gasmax_cast_mask) == __gasmax;
}}
function dead_check(bool __dead) pure returns (bool) { unchecked {
  return (uint_of_bool(__dead) & dead_cast_mask) == uint_of_bool(__dead);
}}

