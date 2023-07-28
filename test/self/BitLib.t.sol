// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_lib/Test2.sol";
import {BitLib} from "mgv_lib/BitLib.sol";

contract BitLibTest is Test2 {
  // from solady's LibBit.t.sol
  function test_ctz() public {
    assertEq(BitLib.ctz(0xff << 3), 3);
    uint brutalizer = uint(keccak256(abi.encode(address(this), block.timestamp)));
    for (uint i = 0; i < 256; i++) {
      assertEq(BitLib.ctz(1 << i), i);
      assertEq(BitLib.ctz(type(uint).max << i), i);
      assertEq(BitLib.ctz((brutalizer | 1) << i), i);
    }
    assertEq(BitLib.ctz(0), 256);
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
