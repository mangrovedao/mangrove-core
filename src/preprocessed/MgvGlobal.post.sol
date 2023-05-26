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

library Library {
  function to_struct(GlobalPacked __packed) internal pure returns (GlobalUnpacked memory __s) { unchecked {
    __s.monitor   = address(uint160((GlobalPacked.unwrap(__packed) & monitor_mask_inv) >> (256 - monitor_bits - monitor_before)));
    __s.useOracle = ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
    __s.notify    = ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
    __s.gasprice  = (GlobalPacked.unwrap(__packed) & gasprice_mask_inv) >> (256 - gasprice_bits - gasprice_before);
    __s.gasmax    = (GlobalPacked.unwrap(__packed) & gasmax_mask_inv) >> (256 - gasmax_bits - gasmax_before);
    __s.dead      = ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  function eq(GlobalPacked __packed1, GlobalPacked __packed2) internal pure returns (bool) { unchecked {
    return GlobalPacked.unwrap(__packed1) == GlobalPacked.unwrap(__packed2);
  }}

  function unpack(GlobalPacked __packed) internal pure returns (address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) { unchecked {
    __monitor   = address(uint160((GlobalPacked.unwrap(__packed) & monitor_mask_inv) >> (256 - monitor_bits - monitor_before)));
    __useOracle = ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
    __notify    = ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
    __gasprice  = (GlobalPacked.unwrap(__packed) & gasprice_mask_inv) >> (256 - gasprice_bits - gasprice_before);
    __gasmax    = (GlobalPacked.unwrap(__packed) & gasmax_mask_inv) >> (256 - gasmax_bits - gasmax_before);
    __dead      = ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  function monitor(GlobalPacked __packed) internal pure returns(address) { unchecked {
    return address(uint160((GlobalPacked.unwrap(__packed) & monitor_mask_inv) >> (256 - monitor_bits - monitor_before)));
  }}

  function monitor(GlobalPacked __packed,address val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & monitor_mask) | (uint(uint160(val)) << (256 - monitor_bits)) >> monitor_before);
  }}
  
  function useOracle(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & useOracle_mask_inv) > 0);
  }}

  function useOracle(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & useOracle_mask) | (uint_of_bool(val) << (256 - useOracle_bits)) >> useOracle_before);
  }}
  
  function notify(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & notify_mask_inv) > 0);
  }}

  function notify(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & notify_mask) | (uint_of_bool(val) << (256 - notify_bits)) >> notify_before);
  }}
  
  function gasprice(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return (GlobalPacked.unwrap(__packed) & gasprice_mask_inv) >> (256 - gasprice_bits - gasprice_before);
  }}

  function gasprice(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & gasprice_mask) | (val << (256 - gasprice_bits)) >> gasprice_before);
  }}
  
  function gasmax(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return (GlobalPacked.unwrap(__packed) & gasmax_mask_inv) >> (256 - gasmax_bits - gasmax_before);
  }}

  function gasmax(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & gasmax_mask) | (val << (256 - gasmax_bits)) >> gasmax_before);
  }}
  
  function dead(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return ((GlobalPacked.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  function dead(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    return GlobalPacked.wrap((GlobalPacked.unwrap(__packed) & dead_mask) | (uint_of_bool(val) << (256 - dead_bits)) >> dead_before);
  }}
  
}

function t_of_struct(GlobalUnpacked memory __s) pure returns (GlobalPacked) { unchecked {
  return pack(__s.monitor, __s.useOracle, __s.notify, __s.gasprice, __s.gasmax, __s.dead);
}}

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
