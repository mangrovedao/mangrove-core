// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

library BitLib {
  // Returns the number of zeroes in x that do not have a 1 to their right, eg ctz(0)=256, ctz(1)=0
  function ctz(uint x) internal pure returns (uint c) {
    assembly ("memory-safe") {
      // Isolate the least significant bit
      x := and(x, add(not(x), 1))

      // Get first 3 bits of c, this is the unusual part
      c := shl(5,shr(252,shl(shl(2,shr(250,mul(x, 0xb6db6db6ddddddddd34d34d349249249210842108c6318c639ce739cffffffff))),0x8040405543005266443200005020610674053026020000107506200176117077)))

      // Get last 5 bits of c
      c := or(c, byte(shr(251, mul(shr(c, x), shl(224, 0x077cb531))), 
          0x00011c021d0e18031e16140f191104081f1b0d17151310071a0c12060b050a09))
    }
  }

  // Function fls is MIT License. Copyright (c) 2022 Solady.
/// @dev find last set.
    /// Returns the index of the most significant bit of `x`,
    /// counting from the least significant bit position.
    /// If `x` is zero, returns 256.
    /// Equivalent to `log2(x)`, but without reverting for the zero case.
    function fls(uint256 x) internal pure returns (uint256 r) {
        /// @solidity memory-safe-assembly
        assembly {
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
