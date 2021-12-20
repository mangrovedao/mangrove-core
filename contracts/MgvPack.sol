pragma solidity ^0.8.10;

// SPDX-License-Identifier: Unlicense

// MgvPack.sol

// This is free and unencumbered software released into the public domain.

// Anyone is free to copy, modify, publish, use, compile, sell, or distribute this software, either in source code form or as a compiled binary, for any purpose, commercial or non-commercial, and by any means.

// In jurisdictions that recognize copyright laws, the author or authors of this software dedicate any and all copyright interest in the software to the public domain. We make this dedication for the benefit of the public at large and to the detriment of our heirs and successors. We intend this dedication to be an overt act of relinquishment in perpetuity of all present and future rights to this software under copyright law.

// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

// For more information, please refer to <https://unlicense.org/>

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

/* since you can't convert bool to uint in an expression without conditionals,
 * we add a file-level function and rely on compiler optimization
 */
function uint_of_bool(bool b) pure returns (uint u) {
  assembly { u := b }
}

// fields are of the form [name,bits,type]

// Can't put all structs under a 'Structs' library due to bad variable shadowing rules in Solidity
// (would generate lots of spurious warnings about a nameclash between Structs.Offer and library Offer for instance)
// struct_defs are of the form [name,obj]
struct OfferStruct {
  uint prev;
  uint next;
  uint wants;
  uint gives;
}
struct OfferDetailStruct {
  address maker;
  uint gasreq;
  uint offer_gasbase;
  uint gasprice;
}
struct GlobalStruct {
  address monitor;
  bool useOracle;
  bool notify;
  uint gasprice;
  uint gasmax;
  bool dead;
}
struct LocalStruct {
  bool active;
  uint fee;
  uint density;
  uint offer_gasbase;
  bool lock;
  uint best;
  uint last;
}

library Offer {
  //some type safety for each struct
  type t is bytes32;

  function to_struct(t __packed) internal pure returns (OfferStruct memory __s) { unchecked {
    __s.prev = uint(uint((t.unwrap(__packed) << 0)) >> 224);
    __s.next = uint(uint((t.unwrap(__packed) << 32)) >> 224);
    __s.wants = uint(uint((t.unwrap(__packed) << 64)) >> 160);
    __s.gives = uint(uint((t.unwrap(__packed) << 160)) >> 160);
  }}

  function t_of_struct(OfferStruct memory __s) internal pure returns (t) { unchecked {
    return pack(__s.prev, __s.next, __s.wants, __s.gives);
  }}

  function eq(t __packed1, t __packed2) internal pure returns (bool) { unchecked {
    return t.unwrap(__packed1) == t.unwrap(__packed2);
  }}

  function pack(uint __prev, uint __next, uint __wants, uint __gives) internal pure returns (t) { unchecked {
    return t.wrap(((((bytes32(0) | bytes32((__prev << 224) >> 0)) | bytes32((__next << 224) >> 32)) | bytes32((__wants << 160) >> 64)) | bytes32((__gives << 160) >> 160)));
  }}

  function unpack(t __packed) internal pure returns (uint __prev, uint __next, uint __wants, uint __gives) { unchecked {
    __prev = uint(uint((t.unwrap(__packed) << 0)) >> 224);
    __next = uint(uint((t.unwrap(__packed) << 32)) >> 224);
    __wants = uint(uint((t.unwrap(__packed) << 64)) >> 160);
    __gives = uint(uint((t.unwrap(__packed) << 160)) >> 160);
  }}

  function prev(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 0)) >> 224);
  }}
  function prev(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0x00000000ffffffffffffffffffffffffffffffffffffffffffffffffffffffff) | bytes32((uint(val) << 224) >> 0)));
  }}
  function next(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 32)) >> 224);
  }}
  function next(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffff00000000ffffffffffffffffffffffffffffffffffffffffffffffff) | bytes32((uint(val) << 224) >> 32)));
  }}
  function wants(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 64)) >> 160);
  }}
  function wants(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffff000000000000000000000000ffffffffffffffffffffffff) | bytes32((uint(val) << 160) >> 64)));
  }}
  function gives(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 160)) >> 160);
  }}
  function gives(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffff000000000000000000000000) | bytes32((uint(val) << 160) >> 160)));
  }}
}

library OfferDetail {
  //some type safety for each struct
  type t is bytes32;

  function to_struct(t __packed) internal pure returns (OfferDetailStruct memory __s) { unchecked {
    __s.maker = address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
    __s.gasreq = uint(uint((t.unwrap(__packed) << 160)) >> 232);
    __s.offer_gasbase = uint(uint((t.unwrap(__packed) << 184)) >> 232);
    __s.gasprice = uint(uint((t.unwrap(__packed) << 208)) >> 240);
  }}

  function t_of_struct(OfferDetailStruct memory __s) internal pure returns (t) { unchecked {
    return pack(__s.maker, __s.gasreq, __s.offer_gasbase, __s.gasprice);
  }}

  function eq(t __packed1, t __packed2) internal pure returns (bool) { unchecked {
    return t.unwrap(__packed1) == t.unwrap(__packed2);
  }}

  function pack(address __maker, uint __gasreq, uint __offer_gasbase, uint __gasprice) internal pure returns (t) { unchecked {
    return t.wrap(((((bytes32(0) | bytes32((uint(uint160(__maker)) << 96) >> 0)) | bytes32((__gasreq << 232) >> 160)) | bytes32((__offer_gasbase << 232) >> 184)) | bytes32((__gasprice << 240) >> 208)));
  }}

  function unpack(t __packed) internal pure returns (address __maker, uint __gasreq, uint __offer_gasbase, uint __gasprice) { unchecked {
    __maker = address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
    __gasreq = uint(uint((t.unwrap(__packed) << 160)) >> 232);
    __offer_gasbase = uint(uint((t.unwrap(__packed) << 184)) >> 232);
    __gasprice = uint(uint((t.unwrap(__packed) << 208)) >> 240);
  }}

  function maker(t __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
  }}
  function maker(t __packed,address val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0x0000000000000000000000000000000000000000ffffffffffffffffffffffff) | bytes32((uint(uint(uint160(val))) << 96) >> 0)));
  }}
  function gasreq(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 160)) >> 232);
  }}
  function gasreq(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffff000000ffffffffffffffffff) | bytes32((uint(val) << 232) >> 160)));
  }}
  function offer_gasbase(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 184)) >> 232);
  }}
  function offer_gasbase(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffffff000000ffffffffffff) | bytes32((uint(val) << 232) >> 184)));
  }}
  function gasprice(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 208)) >> 240);
  }}
  function gasprice(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffff0000ffffffff) | bytes32((uint(val) << 240) >> 208)));
  }}
}

library Global {
  //some type safety for each struct
  type t is bytes32;

  function to_struct(t __packed) internal pure returns (GlobalStruct memory __s) { unchecked {
    __s.monitor = address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
    __s.useOracle = ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
    __s.notify = ((uint((t.unwrap(__packed) << 168)) >> 248) > 0);
    __s.gasprice = uint(uint((t.unwrap(__packed) << 176)) >> 240);
    __s.gasmax = uint(uint((t.unwrap(__packed) << 192)) >> 232);
    __s.dead = ((uint((t.unwrap(__packed) << 216)) >> 248) > 0);
  }}

  function t_of_struct(GlobalStruct memory __s) internal pure returns (t) { unchecked {
    return pack(__s.monitor, __s.useOracle, __s.notify, __s.gasprice, __s.gasmax, __s.dead);
  }}

  function eq(t __packed1, t __packed2) internal pure returns (bool) { unchecked {
    return t.unwrap(__packed1) == t.unwrap(__packed2);
  }}

  function pack(address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) internal pure returns (t) { unchecked {
    return t.wrap(((((((bytes32(0) | bytes32((uint(uint160(__monitor)) << 96) >> 0)) | bytes32((uint_of_bool(__useOracle) << 248) >> 160)) | bytes32((uint_of_bool(__notify) << 248) >> 168)) | bytes32((__gasprice << 240) >> 176)) | bytes32((__gasmax << 232) >> 192)) | bytes32((uint_of_bool(__dead) << 248) >> 216)));
  }}

  function unpack(t __packed) internal pure returns (address __monitor, bool __useOracle, bool __notify, uint __gasprice, uint __gasmax, bool __dead) { unchecked {
    __monitor = address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
    __useOracle = ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
    __notify = ((uint((t.unwrap(__packed) << 168)) >> 248) > 0);
    __gasprice = uint(uint((t.unwrap(__packed) << 176)) >> 240);
    __gasmax = uint(uint((t.unwrap(__packed) << 192)) >> 232);
    __dead = ((uint((t.unwrap(__packed) << 216)) >> 248) > 0);
  }}

  function monitor(t __packed) internal pure returns(address) { unchecked {
    return address(uint160(uint((t.unwrap(__packed) << 0)) >> 96));
  }}
  function monitor(t __packed,address val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0x0000000000000000000000000000000000000000ffffffffffffffffffffffff) | bytes32((uint(uint(uint160(val))) << 96) >> 0)));
  }}
  function useOracle(t __packed) internal pure returns(bool) { unchecked {
    return ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
  }}
  function useOracle(t __packed,bool val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffff00ffffffffffffffffffffff) | bytes32((uint(uint_of_bool(val)) << 248) >> 160)));
  }}
  function notify(t __packed) internal pure returns(bool) { unchecked {
    return ((uint((t.unwrap(__packed) << 168)) >> 248) > 0);
  }}
  function notify(t __packed,bool val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffff00ffffffffffffffffffff) | bytes32((uint(uint_of_bool(val)) << 248) >> 168)));
  }}
  function gasprice(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 176)) >> 240);
  }}
  function gasprice(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffff0000ffffffffffffffff) | bytes32((uint(val) << 240) >> 176)));
  }}
  function gasmax(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 192)) >> 232);
  }}
  function gasmax(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffff000000ffffffffff) | bytes32((uint(val) << 232) >> 192)));
  }}
  function dead(t __packed) internal pure returns(bool) { unchecked {
    return ((uint((t.unwrap(__packed) << 216)) >> 248) > 0);
  }}
  function dead(t __packed,bool val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffffffff00ffffffff) | bytes32((uint(uint_of_bool(val)) << 248) >> 216)));
  }}
}

library Local {
  //some type safety for each struct
  type t is bytes32;

  function to_struct(t __packed) internal pure returns (LocalStruct memory __s) { unchecked {
    __s.active = ((uint((t.unwrap(__packed) << 0)) >> 248) > 0);
    __s.fee = uint(uint((t.unwrap(__packed) << 8)) >> 240);
    __s.density = uint(uint((t.unwrap(__packed) << 24)) >> 144);
    __s.offer_gasbase = uint(uint((t.unwrap(__packed) << 136)) >> 232);
    __s.lock = ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
    __s.best = uint(uint((t.unwrap(__packed) << 168)) >> 224);
    __s.last = uint(uint((t.unwrap(__packed) << 200)) >> 224);
  }}

  function t_of_struct(LocalStruct memory __s) internal pure returns (t) { unchecked {
    return pack(__s.active, __s.fee, __s.density, __s.offer_gasbase, __s.lock, __s.best, __s.last);
  }}

  function eq(t __packed1, t __packed2) internal pure returns (bool) { unchecked {
    return t.unwrap(__packed1) == t.unwrap(__packed2);
  }}

  function pack(bool __active, uint __fee, uint __density, uint __offer_gasbase, bool __lock, uint __best, uint __last) internal pure returns (t) { unchecked {
    return t.wrap((((((((bytes32(0) | bytes32((uint_of_bool(__active) << 248) >> 0)) | bytes32((__fee << 240) >> 8)) | bytes32((__density << 144) >> 24)) | bytes32((__offer_gasbase << 232) >> 136)) | bytes32((uint_of_bool(__lock) << 248) >> 160)) | bytes32((__best << 224) >> 168)) | bytes32((__last << 224) >> 200)));
  }}

  function unpack(t __packed) internal pure returns (bool __active, uint __fee, uint __density, uint __offer_gasbase, bool __lock, uint __best, uint __last) { unchecked {
    __active = ((uint((t.unwrap(__packed) << 0)) >> 248) > 0);
    __fee = uint(uint((t.unwrap(__packed) << 8)) >> 240);
    __density = uint(uint((t.unwrap(__packed) << 24)) >> 144);
    __offer_gasbase = uint(uint((t.unwrap(__packed) << 136)) >> 232);
    __lock = ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
    __best = uint(uint((t.unwrap(__packed) << 168)) >> 224);
    __last = uint(uint((t.unwrap(__packed) << 200)) >> 224);
  }}

  function active(t __packed) internal pure returns(bool) { unchecked {
    return ((uint((t.unwrap(__packed) << 0)) >> 248) > 0);
  }}
  function active(t __packed,bool val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) | bytes32((uint(uint_of_bool(val)) << 248) >> 0)));
  }}
  function fee(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 8)) >> 240);
  }}
  function fee(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xff0000ffffffffffffffffffffffffffffffffffffffffffffffffffffffffff) | bytes32((uint(val) << 240) >> 8)));
  }}
  function density(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 24)) >> 144);
  }}
  function density(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffff0000000000000000000000000000ffffffffffffffffffffffffffffff) | bytes32((uint(val) << 144) >> 24)));
  }}
  function offer_gasbase(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 136)) >> 232);
  }}
  function offer_gasbase(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffff000000ffffffffffffffffffffffff) | bytes32((uint(val) << 232) >> 136)));
  }}
  function lock(t __packed) internal pure returns(bool) { unchecked {
    return ((uint((t.unwrap(__packed) << 160)) >> 248) > 0);
  }}
  function lock(t __packed,bool val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffff00ffffffffffffffffffffff) | bytes32((uint(uint_of_bool(val)) << 248) >> 160)));
  }}
  function best(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 168)) >> 224);
  }}
  function best(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffff00000000ffffffffffffff) | bytes32((uint(val) << 224) >> 168)));
  }}
  function last(t __packed) internal pure returns(uint) { unchecked {
    return uint(uint((t.unwrap(__packed) << 200)) >> 224);
  }}
  function last(t __packed,uint val) internal pure returns(t) { unchecked {
    return t.wrap((t.unwrap(__packed) & bytes32(0xffffffffffffffffffffffffffffffffffffffffffffffffff00000000ffffff) | bytes32((uint(val) << 224) >> 200)));
  }}
}
