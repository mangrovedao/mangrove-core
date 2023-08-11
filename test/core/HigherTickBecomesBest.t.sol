// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, MAX_TICK, MIN_TICK} from "mgv_src/MgvLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";

contract HigherTickBecomesBestTest is MangroveTest {
  function setUp() public virtual override {
    super.setUp();

    deal($(base), $(this), 100 ether);
  }

  function test_lower_tick() public {}
}
