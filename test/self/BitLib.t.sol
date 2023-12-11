// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/lib/Test2.sol";
import {BitLib} from "@mgv/lib/core/BitLib.sol";

contract BitLibTest is Test2 {
  // adapted from solady's LibBit.t.sol
  function test_ctz64() public {
    assertEq(BitLib.ctz64(0xff << 3), 3);
    uint brutalizer = uint(keccak256(abi.encode(address(this), block.timestamp)));
    for (uint i = 0; i < 64; i++) {
      assertEq(BitLib.ctz64(1 << i), i);
      assertEq(BitLib.ctz64(type(uint).max << i), i);
      assertEq(BitLib.ctz64((brutalizer | 1) << i), i);
    }
    assertEq(BitLib.ctz64(0), 64);
  }

  function test_fls() public {
    assertEq(BitLib.fls(0xff << 3), 10);
    for (uint i = 1; i < 255; i++) {
      assertEq(BitLib.fls((1 << i) - 1), i - 1);
      assertEq(BitLib.fls((1 << i)), i);
      assertEq(BitLib.fls((1 << i) + 1), i);
    }
    assertEq(BitLib.fls(0), 256);
  }
}
