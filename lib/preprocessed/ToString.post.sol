// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

/* ************************************************** *
            GENERATED FILE. DO NOT EDIT.
 * ************************************************** */

// Debugging utilities
address constant VM_ADDRESS = address(uint160(uint(keccak256("hevm cheat code"))));
import {Vm} from "forge-std/Vm.sol";
Vm constant vm = Vm(VM_ADDRESS);

// Manual user-defined types
import "mgv_lib/TickTreeIndexLib.sol";
import "mgv_lib/LogPriceLib.sol";
import "mgv_lib/LogPriceConversionLib.sol";
import {Density,DensityLib} from "mgv_lib/DensityLib.sol";
import {OLKey} from "mgv_src/MgvLib.sol";



import {OfferPacked, OfferUnpacked} from "mgv_src/preprocessed/MgvOffer.post.sol";
function toString(OfferPacked __packed) pure returns (string memory) {
  return toString(__packed.to_struct());
}

function toString(OfferUnpacked memory __unpacked) pure returns (string memory) {
  return string.concat("Offer{","prev: ", vm.toString(__unpacked.prev), ", ", "next: ", vm.toString(__unpacked.next), ", ", "logPrice: ", vm.toString(__unpacked.logPrice), ", ", "gives: ", vm.toString(__unpacked.gives),"}");
}

import {OfferDetailPacked, OfferDetailUnpacked} from "mgv_src/preprocessed/MgvOfferDetail.post.sol";
function toString(OfferDetailPacked __packed) pure returns (string memory) {
  return toString(__packed.to_struct());
}

function toString(OfferDetailUnpacked memory __unpacked) pure returns (string memory) {
  return string.concat("OfferDetail{","maker: ", vm.toString(__unpacked.maker), ", ", "gasreq: ", vm.toString(__unpacked.gasreq), ", ", "kilo_offer_gasbase: ", vm.toString(__unpacked.kilo_offer_gasbase), ", ", "gasprice: ", vm.toString(__unpacked.gasprice),"}");
}

import {GlobalPacked, GlobalUnpacked} from "mgv_src/preprocessed/MgvGlobal.post.sol";
function toString(GlobalPacked __packed) pure returns (string memory) {
  return toString(__packed.to_struct());
}

function toString(GlobalUnpacked memory __unpacked) pure returns (string memory) {
  return string.concat("Global{","monitor: ", vm.toString(__unpacked.monitor), ", ", "useOracle: ", vm.toString(__unpacked.useOracle), ", ", "notify: ", vm.toString(__unpacked.notify), ", ", "gasprice: ", vm.toString(__unpacked.gasprice), ", ", "gasmax: ", vm.toString(__unpacked.gasmax), ", ", "dead: ", vm.toString(__unpacked.dead), ", ", "maxRecursionDepth: ", vm.toString(__unpacked.maxRecursionDepth), ", ", "maxGasreqForFailingOffers: ", vm.toString(__unpacked.maxGasreqForFailingOffers),"}");
}

import {LocalPacked, LocalUnpacked} from "mgv_src/preprocessed/MgvLocal.post.sol";
function toString(LocalPacked __packed) pure returns (string memory) {
  return toString(__packed.to_struct());
}

function toString(LocalUnpacked memory __unpacked) pure returns (string memory) {
  return string.concat("Local{","active: ", vm.toString(__unpacked.active), ", ", "fee: ", vm.toString(__unpacked.fee), ", ", "density: ", toString(__unpacked.density), ", ", "tickTreeIndexPosInLeaf: ", vm.toString(__unpacked.tickTreeIndexPosInLeaf), ", ", "level0: ", toString(__unpacked.level0), ", ", "level1: ", toString(__unpacked.level1), ", ", "level2: ", toString(__unpacked.level2), ", ", "root: ", toString(__unpacked.root), ", ", "kilo_offer_gasbase: ", vm.toString(__unpacked.kilo_offer_gasbase), ", ", "lock: ", vm.toString(__unpacked.lock), ", ", "last: ", vm.toString(__unpacked.last),"}");
}

function tickTreeIndexBranchToString(TickTreeIndex tick) pure returns (string memory) {
  return string.concat(vm.toString(tick.posInRoot()), "->", vm.toString(tick.posInLevel2()), "[", vm.toString(tick.level2Index()), "]->", vm.toString(tick.posInLevel1()), "[", vm.toString(tick.level1Index()), "]->", vm.toString(tick.posInLevel0()), "[", vm.toString(tick.level0Index()), "]->", vm.toString(tick.posInLeaf()), "[", vm.toString(tick.leafIndex()), "]");
}

function toString(TickTreeIndex tick) pure returns (string memory ret) {
  string memory suffix;
  if (MIN_TICK_TREE_INDEX > TickTreeIndex.unwrap(tick) || TickTreeIndex.unwrap(tick) > MAX_TICK_TREE_INDEX) {
    suffix = "out of range";
  } else if (MIN_TICK_TREE_INDEX_ALLOWED > TickTreeIndex.unwrap(tick) || TickTreeIndex.unwrap(tick) > MAX_TICK_TREE_INDEX_ALLOWED) {
    suffix = "out of logPrice range";
  } else {
    suffix = logPriceToString(LogPriceLib.fromTickTreeIndex(tick,1));
  }

  ret = string.concat(unicode"「", vm.toString(TickTreeIndex.unwrap(tick))," (default: " ,suffix, ") {tree branch: ", tickTreeIndexBranchToString(tick), "}", unicode"」");
}

function logPriceToString(int logPrice) pure returns (string memory ret) {
  (uint man, uint exp)  = LogPriceConversionLib.ratioFromLogPrice(logPrice);
  string memory str = toFixed(man,exp);

  ret = string.concat(unicode"⦗ ",vm.toString(logPrice),"|", str,unicode":1 ⦘");
}

function toString(Leaf leaf) pure returns (string memory ret) {
  for (uint i = 0; i < 4; i++) {
    ret = string.concat(
      ret, string.concat("[", vm.toString(leaf.firstOfPos(i)), ",", vm.toString(leaf.lastOfPos(i)), "]")
    );
  }
}

function toString(DirtyLeaf leaf) pure returns (string memory ret) {
  return string.concat("<dirty[",leaf.isDirty() ? "yes" : "no","]",toString(leaf.clean()),">");
}

function toString(Field field) pure returns (string memory res) {
  for (uint i = 0; i < 256; i++) {
    if (Field.unwrap(field) & (1 << i) > 0) {
      string memory sep = bytes(res).length == 0 ?  unicode"【" : ", ";
      res = string.concat(res,sep,vm.toString(i));
    }
  }
  res = string.concat(bytes(res).length==0?unicode"【empty":res, unicode"】");
}

function toString(DirtyField field) pure returns (string memory ret) {
  return string.concat("<dirty[",field.isDirty() ? "yes" : "no","]",toString(field.clean()),">");
}

function toString(OLKey memory olKey) pure returns (string memory res) {
  res = string.concat("OLKey{out: ",vm.toString(olKey.outbound),", in: ",vm.toString(olKey.inbound)," sc: ",vm.toString(olKey.tickSpacing),"}");
}

/* *** Unit conversion *** */

/* Return amt as a fractional representation of amt/10^unit, with dp decimal points
*/
function toFixed(uint amt, uint unit) pure returns (string memory) {
  return toFixed(amt,unit,78/*max num of digits*/);
}
/* This full version will show at most dp digits in the fractional part. */
function toFixed(uint amt, uint unit, uint dp) pure returns (string memory str) {
  uint power; // current power of ten of amt being looked at
  uint digit; // factor of the current power of ten
  bool truncated; // whether we had to truncate due to dp
  bool nonNull; // have we seen a nonzero factor so far
  // number -> string conversion, avoids polluting traces with vm.toString
  string[10] memory digitStrings = ["0","1","2","3","4","5","6","7","8","9"];
  // prepend at least `unit` digits or until amt has been exhausted
  while (power < unit || amt > 0) {
    digit = amt % 10;
    nonNull = nonNull || digit != 0;
    // if still in the frac part and still 0 so far, don't write
    if (nonNull || power >= unit) {
      // write if shifting dp to the left puts us out of the fractional part
      if (dp + power >= unit) {
        str = string.concat(digitStrings[digit], str);
      } else {
        truncated = true;
      }
    }

    // if frac part is nonzero, mark it as we move to integral
    if (nonNull && power + 1 == unit) {
      str = string.concat(".", str);
    }
    power++;
    amt = amt / 10;
  }
  // prepend with 0 if integral part empty
  if (unit >= power) {
    str = string.concat("0", str);
  }
  // if number was truncated, mark it
  if (truncated) {
    str = string.concat(str,unicode"…");
  }
}

function toString(Density density) pure returns (string memory) {
  if (Density.unwrap(density) & DensityLib.MASK != Density.unwrap(density)) {
    revert("Given density is too big");
  }
  uint mantissa = density.mantissa();
  uint exp = density.exponent();
  if (exp == 1) {
    revert("Invalid density, value not canonical");
  }
  if (exp < 2) {
    return string.concat(vm.toString(exp)," * 2^-32");
  }
  int unbiasedExp = int(exp) - 32;
  string memory mant = mantissa == 0 ? "1" : mantissa == 1 ? "1.25" : mantissa == 2 ? "1.5" : "1.75";
  return string.concat(mant," * 2^",vm.toString(unbiasedExp));
}

