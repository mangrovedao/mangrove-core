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

struct GlobalUnpacked {
  address monitor;
  bool useOracle;
  bool notify;
  uint gasprice;
  uint gasmax;
  bool dead;
  uint maxRecursionDepth;
  uint maxGasreqForFailingOffers;
}

//some type safety for each struct
type Global is uint;
using GlobalLib for Global global;

////////////// ADDITIONAL DEFINITIONS, IF ANY ////////////////

////////////// END OF ADDITIONAL DEFINITIONS /////////////////

library GlobalLib {

  // number of bits in each field
  uint constant monitor_bits                   = 160;
  uint constant useOracle_bits                 = 1;
  uint constant notify_bits                    = 1;
  uint constant gasprice_bits                  = 26;
  uint constant gasmax_bits                    = 24;
  uint constant dead_bits                      = 1;
  uint constant maxRecursionDepth_bits         = 8;
  uint constant maxGasreqForFailingOffers_bits = 32;

  // number of bits before each field
  uint constant monitor_before                   = 0                        + 0;
  uint constant useOracle_before                 = monitor_before           + monitor_bits;
  uint constant notify_before                    = useOracle_before         + useOracle_bits;
  uint constant gasprice_before                  = notify_before            + notify_bits;
  uint constant gasmax_before                    = gasprice_before          + gasprice_bits;
  uint constant dead_before                      = gasmax_before            + gasmax_bits;
  uint constant maxRecursionDepth_before         = dead_before              + dead_bits;
  uint constant maxGasreqForFailingOffers_before = maxRecursionDepth_before + maxRecursionDepth_bits;

  // focus-mask: 1s at field location, 0s elsewhere
  uint constant monitor_mask_inv                   = (ONES << 256 - monitor_bits) >> monitor_before;
  uint constant useOracle_mask_inv                 = (ONES << 256 - useOracle_bits) >> useOracle_before;
  uint constant notify_mask_inv                    = (ONES << 256 - notify_bits) >> notify_before;
  uint constant gasprice_mask_inv                  = (ONES << 256 - gasprice_bits) >> gasprice_before;
  uint constant gasmax_mask_inv                    = (ONES << 256 - gasmax_bits) >> gasmax_before;
  uint constant dead_mask_inv                      = (ONES << 256 - dead_bits) >> dead_before;
  uint constant maxRecursionDepth_mask_inv         = (ONES << 256 - maxRecursionDepth_bits) >> maxRecursionDepth_before;
  uint constant maxGasreqForFailingOffers_mask_inv = (ONES << 256 - maxGasreqForFailingOffers_bits) >> maxGasreqForFailingOffers_before;

  // cleanup-mask: 0s at field location, 1s elsewhere
  uint constant monitor_mask                   = ~monitor_mask_inv;
  uint constant useOracle_mask                 = ~useOracle_mask_inv;
  uint constant notify_mask                    = ~notify_mask_inv;
  uint constant gasprice_mask                  = ~gasprice_mask_inv;
  uint constant gasmax_mask                    = ~gasmax_mask_inv;
  uint constant dead_mask                      = ~dead_mask_inv;
  uint constant maxRecursionDepth_mask         = ~maxRecursionDepth_mask_inv;
  uint constant maxGasreqForFailingOffers_mask = ~maxGasreqForFailingOffers_mask_inv;

  // cast-mask: 0s followed by |field| trailing 1s
  uint constant monitor_cast_mask                   = ~(ONES << monitor_bits);
  uint constant useOracle_cast_mask                 = ~(ONES << useOracle_bits);
  uint constant notify_cast_mask                    = ~(ONES << notify_bits);
  uint constant gasprice_cast_mask                  = ~(ONES << gasprice_bits);
  uint constant gasmax_cast_mask                    = ~(ONES << gasmax_bits);
  uint constant dead_cast_mask                      = ~(ONES << dead_bits);
  uint constant maxRecursionDepth_cast_mask         = ~(ONES << maxRecursionDepth_bits);
  uint constant maxGasreqForFailingOffers_cast_mask = ~(ONES << maxGasreqForFailingOffers_bits);

  // size-related error message
  string constant monitor_size_error                   = "mgv/config/monitor/160bits";
  string constant useOracle_size_error                 = "mgv/config/useOracle/1bits";
  string constant notify_size_error                    = "mgv/config/notify/1bits";
  string constant gasprice_size_error                  = "mgv/config/gasprice/26bits";
  string constant gasmax_size_error                    = "mgv/config/gasmax/24bits";
  string constant dead_size_error                      = "mgv/config/dead/1bits";
  string constant maxRecursionDepth_size_error         = "mgv/config/maxRecursionDepth/8bits";
  string constant maxGasreqForFailingOffers_size_error = "mgv/config/maxGasreqForFailingOffers/32bits";

  // from packed to in-memory struct
  function to_struct(Global __packed) internal pure returns (GlobalUnpacked memory __s) { unchecked {
    __s.monitor                   = address(uint160(uint(Global.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __s.useOracle                 = ((Global.unwrap(__packed) & useOracle_mask_inv) > 0);
    __s.notify                    = ((Global.unwrap(__packed) & notify_mask_inv) > 0);
    __s.gasprice                  = uint(Global.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __s.gasmax                    = uint(Global.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __s.dead                      = ((Global.unwrap(__packed) & dead_mask_inv) > 0);
    __s.maxRecursionDepth         = uint(Global.unwrap(__packed) << maxRecursionDepth_before) >> (256 - maxRecursionDepth_bits);
    __s.maxGasreqForFailingOffers = uint(Global.unwrap(__packed) << maxGasreqForFailingOffers_before) >> (256 - maxGasreqForFailingOffers_bits);
  }}

  // equality checking
  function eq(Global __packed1, Global __packed2) internal pure returns (bool) { unchecked {
    return Global.unwrap(__packed1) == Global.unwrap(__packed2);
  }}

  // from packed to a tuple
  function unpack(Global __packed) internal pure returns (address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead, uint __maxRecursionDepth, uint __maxGasreqForFailingOffers) { unchecked {
    __monitor                   = address(uint160(uint(Global.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
    __useOracle                 = ((Global.unwrap(__packed) & useOracle_mask_inv) > 0);
    __notify                    = ((Global.unwrap(__packed) & notify_mask_inv) > 0);
    __gasprice                  = uint(Global.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
    __gasmax                    = uint(Global.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
    __dead                      = ((Global.unwrap(__packed) & dead_mask_inv) > 0);
    __maxRecursionDepth         = uint(Global.unwrap(__packed) << maxRecursionDepth_before) >> (256 - maxRecursionDepth_bits);
    __maxGasreqForFailingOffers = uint(Global.unwrap(__packed) << maxGasreqForFailingOffers_before) >> (256 - maxGasreqForFailingOffers_bits);
  }}

  // getters
  function monitor(Global __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint(Global.unwrap(__packed) << monitor_before) >> (256 - monitor_bits)));
  }}

  // setters
  function monitor(Global __packed,address val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & monitor_mask) | (uint(uint160(val)) << (256 - monitor_bits)) >> monitor_before);
  }}
  
  function useOracle(Global __packed) internal pure returns(bool) { unchecked {
    return ((Global.unwrap(__packed) & useOracle_mask_inv) > 0);
  }}

  // setters
  function useOracle(Global __packed,bool val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & useOracle_mask) | (uint_of_bool(val) << (256 - useOracle_bits)) >> useOracle_before);
  }}
  
  function notify(Global __packed) internal pure returns(bool) { unchecked {
    return ((Global.unwrap(__packed) & notify_mask_inv) > 0);
  }}

  // setters
  function notify(Global __packed,bool val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & notify_mask) | (uint_of_bool(val) << (256 - notify_bits)) >> notify_before);
  }}
  
  function gasprice(Global __packed) internal pure returns(uint) { unchecked {
    return uint(Global.unwrap(__packed) << gasprice_before) >> (256 - gasprice_bits);
  }}

  // setters
  function gasprice(Global __packed,uint val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & gasprice_mask) | (val << (256 - gasprice_bits)) >> gasprice_before);
  }}
  
  function gasmax(Global __packed) internal pure returns(uint) { unchecked {
    return uint(Global.unwrap(__packed) << gasmax_before) >> (256 - gasmax_bits);
  }}

  // setters
  function gasmax(Global __packed,uint val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & gasmax_mask) | (val << (256 - gasmax_bits)) >> gasmax_before);
  }}
  
  function dead(Global __packed) internal pure returns(bool) { unchecked {
    return ((Global.unwrap(__packed) & dead_mask_inv) > 0);
  }}

  // setters
  function dead(Global __packed,bool val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & dead_mask) | (uint_of_bool(val) << (256 - dead_bits)) >> dead_before);
  }}
  
  function maxRecursionDepth(Global __packed) internal pure returns(uint) { unchecked {
    return uint(Global.unwrap(__packed) << maxRecursionDepth_before) >> (256 - maxRecursionDepth_bits);
  }}

  // setters
  function maxRecursionDepth(Global __packed,uint val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & maxRecursionDepth_mask) | (val << (256 - maxRecursionDepth_bits)) >> maxRecursionDepth_before);
  }}
  
  function maxGasreqForFailingOffers(Global __packed) internal pure returns(uint) { unchecked {
    return uint(Global.unwrap(__packed) << maxGasreqForFailingOffers_before) >> (256 - maxGasreqForFailingOffers_bits);
  }}

  // setters
  function maxGasreqForFailingOffers(Global __packed,uint val) internal pure returns(Global) { unchecked {
    return Global.wrap((Global.unwrap(__packed) & maxGasreqForFailingOffers_mask) | (val << (256 - maxGasreqForFailingOffers_bits)) >> maxGasreqForFailingOffers_before);
  }}
  

  // from in-memory struct to packed
  function t_of_struct(GlobalUnpacked memory __s) internal pure returns (Global) { unchecked {
    return pack(__s.monitor, __s.useOracle, __s.notify, __s.gasprice, __s.gasmax, __s.dead, __s.maxRecursionDepth, __s.maxGasreqForFailingOffers);
  }}

  // from arguments to packed
  function pack(address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead, uint __maxRecursionDepth, uint __maxGasreqForFailingOffers) internal pure returns (Global) { unchecked {
    uint __packed;
    __packed |= (uint(uint160(__monitor)) << (256 - monitor_bits)) >> monitor_before;
    __packed |= (uint_of_bool(__useOracle) << (256 - useOracle_bits)) >> useOracle_before;
    __packed |= (uint_of_bool(__notify) << (256 - notify_bits)) >> notify_before;
    __packed |= (__gasprice << (256 - gasprice_bits)) >> gasprice_before;
    __packed |= (__gasmax << (256 - gasmax_bits)) >> gasmax_before;
    __packed |= (uint_of_bool(__dead) << (256 - dead_bits)) >> dead_before;
    __packed |= (__maxRecursionDepth << (256 - maxRecursionDepth_bits)) >> maxRecursionDepth_before;
    __packed |= (__maxGasreqForFailingOffers << (256 - maxGasreqForFailingOffers_bits)) >> maxGasreqForFailingOffers_before;
    return Global.wrap(__packed);
  }}

  // input checking
  function monitor_check(address __monitor) internal pure returns (bool) { unchecked {
    return (uint(uint160(__monitor)) & monitor_cast_mask) == uint(uint160(__monitor));
  }}
  function useOracle_check(bool __useOracle) internal pure returns (bool) { unchecked {
    return (uint_of_bool(__useOracle) & useOracle_cast_mask) == uint_of_bool(__useOracle);
  }}
  function notify_check(bool __notify) internal pure returns (bool) { unchecked {
    return (uint_of_bool(__notify) & notify_cast_mask) == uint_of_bool(__notify);
  }}
  function gasprice_check(uint __gasprice) internal pure returns (bool) { unchecked {
    return (__gasprice & gasprice_cast_mask) == __gasprice;
  }}
  function gasmax_check(uint __gasmax) internal pure returns (bool) { unchecked {
    return (__gasmax & gasmax_cast_mask) == __gasmax;
  }}
  function dead_check(bool __dead) internal pure returns (bool) { unchecked {
    return (uint_of_bool(__dead) & dead_cast_mask) == uint_of_bool(__dead);
  }}
  function maxRecursionDepth_check(uint __maxRecursionDepth) internal pure returns (bool) { unchecked {
    return (__maxRecursionDepth & maxRecursionDepth_cast_mask) == __maxRecursionDepth;
  }}
  function maxGasreqForFailingOffers_check(uint __maxGasreqForFailingOffers) internal pure returns (bool) { unchecked {
    return (__maxGasreqForFailingOffers & maxGasreqForFailingOffers_cast_mask) == __maxGasreqForFailingOffers;
  }}
}

