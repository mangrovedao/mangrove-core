// MgvGlobal.post.sol

// SPDX-License-Identifier: Unlicense

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

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

// cleanup-mask: 0s at field location, 1s elsewhere
uint constant monitor_mask   = ~((ONES << 256 - monitor_bits) >> monitor_before);
uint constant useOracle_mask = ~((ONES << 256 - useOracle_bits) >> useOracle_before);
uint constant notify_mask    = ~((ONES << 256 - notify_bits) >> notify_before);
uint constant gasprice_mask  = ~((ONES << 256 - gasprice_bits) >> gasprice_before);
uint constant gasmax_mask    = ~((ONES << 256 - gasmax_bits) >> gasmax_before);
uint constant dead_mask      = ~((ONES << 256 - dead_bits) >> dead_before);

library Library {
  function to_struct(GlobalPacked __packed) internal pure returns (GlobalUnpacked memory __s) { unchecked {
    __s.monitor   = address(uint160((GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __s.useOracle = (((GlobalPacked.unwrap(__packed) << useOracle_before) >> (256 - useOracle_bits)) > 0);
    __s.notify    = (((GlobalPacked.unwrap(__packed) << notify_before) >> (256 - notify_bits)) > 0);
    __s.gasprice  = (GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __s.gasmax    = (GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __s.dead      = (((GlobalPacked.unwrap(__packed) << dead_before) >> (256 - dead_bits)) > 0);
  }}

  function eq(GlobalPacked __packed1, GlobalPacked __packed2) internal pure returns (bool) { unchecked {
    return GlobalPacked.unwrap(__packed1) == GlobalPacked.unwrap(__packed2);
  }}

  function unpack(GlobalPacked __packed) internal pure returns (address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) { unchecked {
    __monitor   = address(uint160((GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __useOracle = (((GlobalPacked.unwrap(__packed) << useOracle_before) >> (256 - useOracle_bits)) > 0);
    __notify    = (((GlobalPacked.unwrap(__packed) << notify_before) >> (256 - notify_bits)) > 0);
    __gasprice  = (GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __gasmax    = (GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __dead      = (((GlobalPacked.unwrap(__packed) << dead_before) >> (256 - dead_bits)) > 0);
  }}

  function monitor(GlobalPacked __packed) internal pure returns(address) { unchecked {
    return address(uint160((GlobalPacked.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
  }}

  function monitor(GlobalPacked __packed,address val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & monitor_mask;
    uint __clean_field  = (uint(uint160(val)) << (256 - monitor_bits)) >> monitor_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
  }}
  
  function useOracle(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return (((GlobalPacked.unwrap(__packed) << useOracle_before) >> (256 - useOracle_bits)) > 0);
  }}

  function useOracle(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & useOracle_mask;
    uint __clean_field  = (uint_of_bool(val) << (256 - useOracle_bits)) >> useOracle_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
  }}
  
  function notify(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return (((GlobalPacked.unwrap(__packed) << notify_before) >> (256 - notify_bits)) > 0);
  }}

  function notify(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & notify_mask;
    uint __clean_field  = (uint_of_bool(val) << (256 - notify_bits)) >> notify_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
  }}
  
  function gasprice(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return (GlobalPacked.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  function gasprice(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & gasprice_mask;
    uint __clean_field  = (val << (256 - gasprice_bits)) >> gasprice_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
  }}
  
  function gasmax(GlobalPacked __packed) internal pure returns(uint) { unchecked {
    return (GlobalPacked.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
  }}

  function gasmax(GlobalPacked __packed,uint val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & gasmax_mask;
    uint __clean_field  = (val << (256 - gasmax_bits)) >> gasmax_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
  }}
  
  function dead(GlobalPacked __packed) internal pure returns(bool) { unchecked {
    return (((GlobalPacked.unwrap(__packed) << dead_before) >> (256 - dead_bits)) > 0);
  }}

  function dead(GlobalPacked __packed,bool val) internal pure returns(GlobalPacked) { unchecked {
    uint __clean_struct = GlobalPacked.unwrap(__packed) & dead_mask;
    uint __clean_field  = (uint_of_bool(val) << (256 - dead_bits)) >> dead_before;
    return GlobalPacked.wrap(__clean_struct | __clean_field);
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
