// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library BitLib {
  // - if x is a nonzero uint64: 
  //   return number of zeroes in x that do not have a 1 to their right
  // - otherwise:
  //    return 64
  function ctz64(uint x) internal pure returns (uint256 c) {
    unchecked {
      assembly ("memory-safe") {
        // clean
        x:= and(x,0xffffffffffffffff)

        // 7th bit
        c:= shl(6,iszero(x))

        // isolate lsb
        x := and(x, add(not(x), 1))

        // 6th bit
        c := or(c,shl(5, lt(0xffffffff, x)))

        // debruijn lookup
        c := or(c, byte(shr(251, mul(shr(c, x), shl(224, 0x077cb531))), 
            0x00011c021d0e18031e16140f191104081f1b0d17151310071a0c12060b050a09))
      }
    }
  }

  // The fls function below is general-purpose and used by tests but not by Mangrove itself
  // Function fls is MIT License. Copyright (c) 2022 Solady.
/// @dev find last set.
    /// Returns the index of the most significant bit of `x`,
    /// counting from the least significant bit position.
    /// If `x` is zero, returns 256.
    /// Equivalent to `log2(x)`, but without reverting for the zero case.
    function fls(uint256 x) internal pure returns (uint256 r) {
        assembly ("memory-safe") {
            r := shl(8, iszero(x))

            r := or(r, shl(7, lt(0xffffffffffffffffffffffffffffffff, x)))
            r := or(r, shl(6, lt(0xffffffffffffffff, shr(r, x))))
            r := or(r, shl(5, lt(0xffffffff, shr(r, x))))

            // For the remaining 32 bits, use a De Bruijn lookup.
            x := shr(r, x)
            x := or(x, shr(1, x))
            x := or(x, shr(2, x))
            x := or(x, shr(4, x))
            x := or(x, shr(8, x))
            x := or(x, shr(16, x))

            // forgefmt: disable-next-item
            r := or(r, byte(shr(251, mul(x, shl(224, 0x07c4acdd))),
                0x0009010a0d15021d0b0e10121619031e080c141c0f111807131b17061a05041f))
        }
    }
}
