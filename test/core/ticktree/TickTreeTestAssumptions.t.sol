// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of the assumptions made about ticks in the TickTreeTests.
contract TickTreeTestAssumptionsTest is TickTreeTest {
  // Checks that the ticks used in these tests have the expected locations at various levels.
  function test_ticks_are_at_expected_locations() public {
    assertTickAssumptions({
      tick: TICK_MIN_L3_MAX_OTHERS,
      posInLevel3: MIN_LEVEL3_POS,
      posInLevel2: MAX_LEVEL2_POS,
      posInLevel1: MAX_LEVEL1_POS,
      posInLevel0: MAX_LEVEL0_POS,
      posInLeaf: MAX_LEAF_POS
    });

    assertTickAssumptions({
      tick: TICK_MAX_L3_MIN_OTHERS,
      posInLevel3: MAX_LEVEL3_POS,
      posInLevel2: MIN_LEVEL2_POS,
      posInLevel1: MIN_LEVEL1_POS,
      posInLevel0: MIN_LEVEL0_POS,
      posInLeaf: MIN_LEAF_POS
    });

    assertTickAssumptions({
      tick: TICK_MIDDLE,
      posInLevel3: MID_LEVEL3_POS,
      posInLevel2: MID_LEVEL2_POS,
      posInLevel1: MID_LEVEL1_POS,
      posInLevel0: MID_LEVEL0_POS,
      posInLeaf: MID_LEAF_POS
    });
  }
}
