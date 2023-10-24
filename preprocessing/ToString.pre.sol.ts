import { format } from "./lib/format";


export const template = ({ preamble, structs }) => {
  return format`// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

${preamble}

// Debugging utilities
address constant VM_ADDRESS = address(uint160(uint(keccak256("hevm cheat code"))));
import {Vm} from "@mgv/forge-std/Vm.sol";
Vm constant vm = Vm(VM_ADDRESS);

// Manual user-defined types
import "@mgv/lib/core/TickTreeLib.sol";
import "@mgv/lib/core/TickLib.sol";
import {Density,DensityLib} from "@mgv/lib/core/DensityLib.sol";
import "@mgv/src/core/MgvLib.sol";


${structs.map(s => {

  const fields = s.fields.map(f => {
    if (f.userDefined) {
      return `"${f.name}: ", toString(__unpacked.${f.name})`;
    } else {
      return `"${f.name}: ", vm.toString(__unpacked.${f.name})`;
    }
  });
  const elements = `"${s.Name}{",${fields.join(', ", ", ')},"}"`;

  return `
import {${s.Packed}, ${s.Unpacked}} from "@mgv/src/preprocessed/${s.filenames.src}";
function toString(${s.Packed} __packed) pure returns (string memory) {
  return toString(__packed.to_struct());
}

function toString(${s.Unpacked} memory __unpacked) pure returns (string memory) {
  return string.concat(${elements});
}`;
})}

function binBranchToString(Bin tick) pure returns (string memory) {
  return string.concat(vm.toString(tick.posInRoot()), "->", vm.toString(tick.posInLevel1()), "[", vm.toString(tick.level1Index()), "]->", vm.toString(tick.posInLevel2()), "[", vm.toString(tick.level2Index()), "]->", vm.toString(tick.posInLevel3()), "[", vm.toString(tick.level3Index()), "]->", vm.toString(tick.posInLeaf()), "[", vm.toString(tick.leafIndex()), "]");
}

function toString(Bin bin) pure returns (string memory ret) {
  string memory suffix;
  if (MIN_BIN > Bin.unwrap(bin) || Bin.unwrap(bin) > MAX_BIN) {
    suffix = "out of range";
  } else {
    suffix = toString(bin.tick(1));
  }

  ret = string.concat(unicode"「", vm.toString(Bin.unwrap(bin))," (default: " ,suffix, ") {tree branch: ", binBranchToString(bin), "}", unicode"」");
}

function toString(Tick tick) pure returns (string memory ret) {
  if (!tick.inRange()) {
    ret = unicode"⦗out of range⦘";
  } else {
    (uint man, uint exp)  = TickLib.ratioFromTick(tick);
    string memory str = toFixed(man,exp);

    ret = string.concat(unicode"⦗ ",vm.toString(Tick.unwrap(tick)),"|", str,unicode":1 ⦘");
  }
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
  res = string.concat("OLKey{out: ",vm.toString(olKey.outbound_tkn),", in: ",vm.toString(olKey.inbound_tkn)," sc: ",vm.toString(olKey.tickSpacing),"}");
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
  // prepend at least \`unit\` digits or until amt has been exhausted
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

`;
}
