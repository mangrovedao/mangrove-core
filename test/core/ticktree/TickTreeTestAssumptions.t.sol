// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of the assumptions made about ticks in the TickTreeTests.
contract TickTreeTestAssumptionsTest is TickTreeTest {
  // Checks that the ticks used in these tests have the expected locations at various levels.
  function test_ticks_are_at_expected_locations() public {
    assertBinAssumptions({
      bin: BIN_MIN_ROOT_MAX_OTHERS,
      posInRoot: MIN_ROOT_POS,
      posInLevel2: MAX_LEVEL_POS,
      posInLevel1: MAX_LEVEL_POS,
      posInLevel0: MAX_LEVEL_POS,
      posInLeaf: MAX_LEAF_POS
    });

    assertBinAssumptions({
      bin: BIN_MAX_ROOT_MIN_OTHERS,
      posInRoot: MAX_ROOT_POS,
      posInLevel2: MIN_LEVEL_POS,
      posInLevel1: MIN_LEVEL_POS,
      posInLevel0: MIN_LEVEL_POS,
      posInLeaf: MIN_LEAF_POS
    });

    assertBinAssumptions({
      bin: BIN_MIDDLE,
      posInRoot: MID_ROOT_POS,
      posInLevel2: MID_LEVEL_POS,
      posInLevel1: MID_LEVEL_POS,
      posInLevel0: MID_LEVEL_POS,
      posInLeaf: MID_LEAF_POS
    });
  }
}
