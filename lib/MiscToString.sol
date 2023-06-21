// SPDX-License-Identifier: Unlicense

pragma solidity ^0.8.13;

import "./TickLib.sol";

address constant VM_ADDRESS = address(uint160(uint(keccak256("hevm cheat code"))));
import {Vm} from "forge-std/Vm.sol";
Vm constant vm = Vm(VM_ADDRESS);

function toString(Tick tick) pure returns (string memory ret) {
  string memory suffix;
  if (MIN_TICK > Tick.unwrap(tick) || Tick.unwrap(tick) > MAX_TICK) {
    suffix = "out of range";
  } else {
    suffix = toFixed(tick.priceFromTick_e18(),18);
  }

  ret = string.concat(unicode"「", vm.toString(Tick.unwrap(tick))," (" ,suffix,unicode")」");
}

function toString(Leaf leaf) pure returns (string memory ret) {
  for (uint i = 0; i < 4; i++) {
    ret = string.concat(
      ret, string.concat("[", vm.toString(leaf.firstOfIndex(i)), ",", vm.toString(leaf.lastOfIndex(i)), "]")
    );
  }
}

function toString(Field field) pure returns (string memory res) {
  for (uint i = 0; i < 256; i++) {
    if (Field.unwrap(field) & (1 << (255-i)) > 0) {
      string memory sep = bytes(res).length == 0 ?  unicode"【" : ", ";
      res = string.concat(res,sep,vm.toString(i));
    }
  }
  res = string.concat(bytes(res).length==0?unicode"【empty":res, unicode"】");
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
