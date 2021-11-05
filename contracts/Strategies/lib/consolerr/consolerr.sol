pragma solidity >=0.6.10 <0.8.0;

/*
 * Error logging
 * Author: Zac Williamson, AZTEC
 * Licensed under the Apache 2.0 license
 */

library consolerr {
  function errorBytes(string memory reasonString, bytes memory varA)
    internal
    pure
  {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendBytes(varA, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function error(string memory reasonString, bytes32 varA) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    append0x(errorPtr);
    appendBytes32(varA, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function error(
    string memory reasonString,
    bytes32 varA,
    bytes32 varB
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    append0x(errorPtr);
    appendBytes32(varA, errorPtr);
    appendComma(errorPtr);
    append0x(errorPtr);
    appendBytes32(varB, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function error(
    string memory reasonString,
    bytes32 varA,
    bytes32 varB,
    bytes32 varC
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    append0x(errorPtr);
    appendBytes32(varA, errorPtr);
    appendComma(errorPtr);
    append0x(errorPtr);
    appendBytes32(varB, errorPtr);
    appendComma(errorPtr);
    append0x(errorPtr);
    appendBytes32(varC, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorBytes32(string memory reasonString, bytes32 varA)
    internal
    pure
  {
    error(reasonString, varA);
  }

  function errorBytes32(
    string memory reasonString,
    bytes32 varA,
    bytes32 varB
  ) internal pure {
    error(reasonString, varA, varB);
  }

  function errorBytes32(
    string memory reasonString,
    bytes32 varA,
    bytes32 varB,
    bytes32 varC
  ) internal pure {
    error(reasonString, varA, varB, varC);
  }

  function errorAddress(string memory reasonString, address varA)
    internal
    pure
  {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendAddress(varA, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorAddress(
    string memory reasonString,
    address varA,
    address varB
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendAddress(varA, errorPtr);
    appendComma(errorPtr);
    appendAddress(varB, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorAddress(
    string memory reasonString,
    address varA,
    address varB,
    address varC
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendAddress(varA, errorPtr);
    appendComma(errorPtr);
    appendAddress(varB, errorPtr);
    appendComma(errorPtr);
    appendAddress(varC, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorUint(string memory reasonString, uint varA) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendUint(varA, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorUint(
    string memory reasonString,
    uint varA,
    uint varB
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendUint(varA, errorPtr);
    appendComma(errorPtr);
    appendUint(varB, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function errorUint(
    string memory reasonString,
    uint varA,
    uint varB,
    uint varC
  ) internal pure {
    (bytes32 revertPtr, bytes32 errorPtr) = initErrorPtr();
    appendString(reasonString, errorPtr);
    appendUint(varA, errorPtr);
    appendComma(errorPtr);
    appendUint(varB, errorPtr);
    appendComma(errorPtr);
    appendUint(varC, errorPtr);

    assembly {
      revert(revertPtr, add(mload(errorPtr), 0x44))
    }
  }

  function toAscii(bytes32 input)
    internal
    pure
    returns (bytes32 hi, bytes32 lo)
  {
    assembly {
      for {
        let j := 0
      } lt(j, 32) {
        j := add(j, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        if gt(slice, 0x39) {
          slice := add(slice, 39)
        }
        lo := add(lo, shl(mul(8, j), slice))
        input := shr(4, input)
      }
      for {
        let k := 0
      } lt(k, 32) {
        k := add(k, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        if gt(slice, 0x39) {
          slice := add(slice, 39)
        }
        hi := add(hi, shl(mul(8, k), slice))
        input := shr(4, input)
      }
    }
  }

  function appendComma(bytes32 stringPtr) internal pure {
    assembly {
      let stringLen := mload(stringPtr)

      mstore(add(stringPtr, add(stringLen, 0x20)), ", ")
      mstore(stringPtr, add(stringLen, 2))
    }
  }

  function append0x(bytes32 stringPtr) internal pure {
    assembly {
      let stringLen := mload(stringPtr)
      mstore(add(stringPtr, add(stringLen, 0x20)), "0x")
      mstore(stringPtr, add(stringLen, 2))
    }
  }

  function appendString(string memory toAppend, bytes32 stringPtr)
    internal
    pure
  {
    assembly {
      let appendLen := mload(toAppend)
      let stringLen := mload(stringPtr)
      let appendPtr := add(stringPtr, add(0x20, stringLen))
      for {
        let i := 0
      } lt(i, appendLen) {
        i := add(i, 0x20)
      } {
        mstore(add(appendPtr, i), mload(add(toAppend, add(i, 0x20))))
      }

      // update string length
      mstore(stringPtr, add(stringLen, appendLen))
    }
  }

  function appendBytes(bytes memory toAppend, bytes32 stringPtr) internal pure {
    uint bytesLen;
    bytes32 inPtr;
    assembly {
      bytesLen := mload(toAppend)
      inPtr := add(toAppend, 0x20)
    }

    for (uint i = 0; i < bytesLen; i += 0x20) {
      bytes32 slice;
      assembly {
        slice := mload(inPtr)
        inPtr := add(inPtr, 0x20)
      }
      appendBytes32(slice, stringPtr);
    }

    uint offset = bytesLen % 0x20;
    if (offset > 0) {
      // update length
      assembly {
        let lengthReduction := sub(0x20, offset)
        let len := mload(stringPtr)
        mstore(stringPtr, sub(len, lengthReduction))
      }
    }
  }

  function appendBytes32(bytes32 input, bytes32 stringPtr) internal pure {
    assembly {
      let hi
      let lo
      for {
        let j := 0
      } lt(j, 32) {
        j := add(j, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        slice := add(slice, mul(39, gt(slice, 0x39)))
        lo := add(lo, shl(mul(8, j), slice))
        input := shr(4, input)
      }
      for {
        let k := 0
      } lt(k, 32) {
        k := add(k, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        if gt(slice, 0x39) {
          slice := add(slice, 39)
        }
        hi := add(hi, shl(mul(8, k), slice))
        input := shr(4, input)
      }

      let stringLen := mload(stringPtr)

      // mstore(add(stringPtr, add(stringLen, 0x20)), '0x')
      mstore(add(stringPtr, add(stringLen, 0x20)), hi)
      mstore(add(stringPtr, add(stringLen, 0x40)), lo)
      mstore(stringPtr, add(stringLen, 0x40))
    }
  }

  function appendAddress(address input, bytes32 stringPtr) internal pure {
    assembly {
      let hi
      let lo
      for {
        let j := 0
      } lt(j, 8) {
        j := add(j, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        slice := add(slice, mul(39, gt(slice, 0x39)))
        lo := add(lo, shl(mul(8, j), slice))
        input := shr(4, input)
      }

      lo := shl(192, lo)
      for {
        let k := 0
      } lt(k, 32) {
        k := add(k, 0x01)
      } {
        let slice := add(0x30, and(input, 0xf))
        if gt(slice, 0x39) {
          slice := add(slice, 39)
        }
        hi := add(hi, shl(mul(8, k), slice))
        input := shr(4, input)
      }

      let stringLen := mload(stringPtr)

      mstore(add(stringPtr, add(stringLen, 0x20)), "0x")
      mstore(add(stringPtr, add(stringLen, 0x22)), hi)
      mstore(add(stringPtr, add(stringLen, 0x42)), lo)
      mstore(stringPtr, add(stringLen, 42))
    }
  }

  function appendUint(uint input, bytes32 stringPtr) internal pure {
    assembly {
      // Clear out some low bytes
      let result := mload(0x40)
      if lt(result, 0x200) {
        result := 0x200
      }
      mstore(add(result, 0xa0), mload(0x40))
      mstore(add(result, 0xc0), mload(0x60))
      mstore(add(result, 0xe0), mload(0x80))
      mstore(add(result, 0x100), mload(0xa0))
      mstore(add(result, 0x120), mload(0xc0))
      mstore(add(result, 0x140), mload(0xe0))
      mstore(add(result, 0x160), mload(0x100))
      mstore(add(result, 0x180), mload(0x120))
      mstore(add(result, 0x1a0), mload(0x140))

      // Store lookup table that maps an integer from 0 to 99 into a 2-byte ASCII equivalent
      mstore(
        0x00,
        0x0000000000000000000000000000000000000000000000000000000000003030
      )
      mstore(
        0x20,
        0x3031303230333034303530363037303830393130313131323133313431353136
      )
      mstore(
        0x40,
        0x3137313831393230323132323233323432353236323732383239333033313332
      )
      mstore(
        0x60,
        0x3333333433353336333733383339343034313432343334343435343634373438
      )
      mstore(
        0x80,
        0x3439353035313532353335343535353635373538353936303631363236333634
      )
      mstore(
        0xa0,
        0x3635363636373638363937303731373237333734373537363737373837393830
      )
      mstore(
        0xc0,
        0x3831383238333834383538363837383838393930393139323933393439353936
      )
      mstore(
        0xe0,
        0x3937393839390000000000000000000000000000000000000000000000000000
      )

      // Convert integer into string slices
      function slice(v) -> y {
        y := add(
          add(
            add(
              add(
                and(mload(shl(1, mod(v, 100))), 0xffff),
                shl(16, and(mload(shl(1, mod(div(v, 100), 100))), 0xffff))
              ),
              add(
                shl(32, and(mload(shl(1, mod(div(v, 10000), 100))), 0xffff)),
                shl(48, and(mload(shl(1, mod(div(v, 1000000), 100))), 0xffff))
              )
            ),
            add(
              add(
                shl(
                  64,
                  and(mload(shl(1, mod(div(v, 100000000), 100))), 0xffff)
                ),
                shl(
                  80,
                  and(mload(shl(1, mod(div(v, 10000000000), 100))), 0xffff)
                )
              ),
              add(
                shl(
                  96,
                  and(mload(shl(1, mod(div(v, 1000000000000), 100))), 0xffff)
                ),
                shl(
                  112,
                  and(mload(shl(1, mod(div(v, 100000000000000), 100))), 0xffff)
                )
              )
            )
          ),
          add(
            add(
              add(
                shl(
                  128,
                  and(
                    mload(shl(1, mod(div(v, 10000000000000000), 100))),
                    0xffff
                  )
                ),
                shl(
                  144,
                  and(
                    mload(shl(1, mod(div(v, 1000000000000000000), 100))),
                    0xffff
                  )
                )
              ),
              add(
                shl(
                  160,
                  and(
                    mload(shl(1, mod(div(v, 100000000000000000000), 100))),
                    0xffff
                  )
                ),
                shl(
                  176,
                  and(
                    mload(shl(1, mod(div(v, 10000000000000000000000), 100))),
                    0xffff
                  )
                )
              )
            ),
            add(
              add(
                shl(
                  192,
                  and(
                    mload(shl(1, mod(div(v, 1000000000000000000000000), 100))),
                    0xffff
                  )
                ),
                shl(
                  208,
                  and(
                    mload(
                      shl(1, mod(div(v, 100000000000000000000000000), 100))
                    ),
                    0xffff
                  )
                )
              ),
              add(
                shl(
                  224,
                  and(
                    mload(
                      shl(1, mod(div(v, 10000000000000000000000000000), 100))
                    ),
                    0xffff
                  )
                ),
                shl(
                  240,
                  and(
                    mload(
                      shl(1, mod(div(v, 1000000000000000000000000000000), 100))
                    ),
                    0xffff
                  )
                )
              )
            )
          )
        )
      }

      mstore(0x100, 0x00)
      mstore(0x120, 0x00)
      mstore(0x140, slice(input))
      input := div(input, 100000000000000000000000000000000)
      if input {
        mstore(0x120, slice(input))
        input := div(input, 100000000000000000000000000000000)
        if input {
          mstore(0x100, slice(input))
        }
      }

      function getMsbBytePosition(inp) -> y {
        inp := sub(
          inp,
          0x3030303030303030303030303030303030303030303030303030303030303030
        )
        let v := and(
          add(
            inp,
            0x7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f7f
          ),
          0x8080808080808080808080808080808080808080808080808080808080808080
        )
        v := or(v, shr(1, v))
        v := or(v, shr(2, v))
        v := or(v, shr(4, v))
        v := or(v, shr(8, v))
        v := or(v, shr(16, v))
        v := or(v, shr(32, v))
        v := or(v, shr(64, v))
        v := or(v, shr(128, v))
        y := mul(
          iszero(iszero(inp)),
          and(
            div(
              0x201f1e1d1c1b1a191817161514131211100f0e0d0c0b0a090807060504030201,
              add(shr(8, v), 1)
            ),
            0xff
          )
        )
      }

      let len := getMsbBytePosition(mload(0x140))
      if mload(0x120) {
        len := add(getMsbBytePosition(mload(0x120)), 32)
        if mload(0x100) {
          len := add(getMsbBytePosition(mload(0x100)), 64)
        }
      }

      let currentStringLength := mload(stringPtr)

      let writePtr := add(stringPtr, add(currentStringLength, 0x20))

      let offset := sub(96, len)
      // mstore(result, len)
      mstore(writePtr, mload(add(0x100, offset)))
      mstore(add(writePtr, 0x20), mload(add(0x120, offset)))
      mstore(add(writePtr, 0x40), mload(add(0x140, offset)))

      // // update length
      mstore(stringPtr, add(currentStringLength, len))

      mstore(0x40, mload(add(result, 0xa0)))
      mstore(0x60, mload(add(result, 0xc0)))
      mstore(0x80, mload(add(result, 0xe0)))
      mstore(0xa0, mload(add(result, 0x100)))
      mstore(0xc0, mload(add(result, 0x120)))
      mstore(0xe0, mload(add(result, 0x140)))
      mstore(0x100, mload(add(result, 0x160)))
      mstore(0x120, mload(add(result, 0x180)))
      mstore(0x140, mload(add(result, 0x1a0)))
    }
  }

  function initErrorPtr() internal pure returns (bytes32, bytes32) {
    bytes32 mPtr;
    bytes32 errorPtr;
    assembly {
      mPtr := mload(0x40)
      if lt(mPtr, 0x200) {
        // our uint -> base 10 ascii method requires about 0x200 bytes of mem
        mPtr := 0x200
      }
      mstore(0x40, add(mPtr, 0x1000)) // let's reserve a LOT of memory for our error string.
      mstore(
        mPtr,
        0x08c379a000000000000000000000000000000000000000000000000000000000
      )
      mstore(add(mPtr, 0x04), 0x20)
      mstore(add(mPtr, 0x24), 0)
      errorPtr := add(mPtr, 0x24)
    }

    return (mPtr, errorPtr);
  }
}
