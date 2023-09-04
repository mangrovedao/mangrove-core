// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of the assumptions made about ticks in the TickTreeTests.
contract TickTreeTestAssumptionsTest is TickTreeTest {
  // Checks that the ticks used in these tests have the expected locations at various levels.
  // This also serves as a reading guide to the constants.
  function test_ticks_are_at_expected_locations() public {
    // tick is MIN_TICK
    // tick is min {leaf, level0, level1, level2}
    assertTickAssumptions({
      tick: Tick.wrap(MIN_TICK),
      posInLeaf: 0,
      leafIndex: MIN_LEAF_INDEX,
      posInLevel0: 0,
      level0Index: MIN_LEVEL0_INDEX,
      posInLevel1: 0,
      level1Index: MIN_LEVEL1_INDEX,
      posInLevel2: 0
    });

    // tick is MIN_TICK
    // tick is max {leaf, level0, level1, level2}
    assertTickAssumptions({
      tick: Tick.wrap(MAX_TICK),
      posInLeaf: MAX_LEAF_POSITION,
      leafIndex: MAX_LEAF_INDEX,
      posInLevel0: MAX_LEVEL0_POSITION,
      level0Index: MAX_LEVEL0_INDEX,
      posInLevel1: MAX_LEVEL1_POSITION,
      level1Index: MAX_LEVEL1_INDEX,
      posInLevel2: MAX_LEVEL2_POSITION
    });

    // tick is min {leaf, level0, level1}
    // tick is mid {level2}
    assertTickAssumptions({
      tick: Tick.wrap(0),
      posInLeaf: 0,
      leafIndex: 0,
      posInLevel0: 0,
      level0Index: 0,
      posInLevel1: 0,
      level1Index: 0,
      posInLevel2: MAX_LEVEL2_POSITION / 2 + 1
    });

    // tick is min {level0, level1}
    // tick is mid {level2}
    // tick is mid {leaf}
    assertTickAssumptions({
      tick: Tick.wrap(1),
      posInLeaf: MAX_LEAF_POSITION / 2,
      leafIndex: 0,
      posInLevel0: 0,
      level0Index: 0,
      posInLevel1: 0,
      level1Index: 0,
      posInLevel2: MAX_LEVEL2_POSITION / 2 + 1
    });

    // tick is min {level0, level1}
    // tick is mid {level2}
    // tick is max {leaf}
    assertTickAssumptions({
      tick: Tick.wrap(3),
      posInLeaf: MAX_LEAF_POSITION,
      leafIndex: 0,
      posInLevel0: 0,
      level0Index: 0,
      posInLevel1: 0,
      level1Index: 0,
      posInLevel2: MAX_LEVEL2_POSITION / 2 + 1
    });

    // tick is negative
    // tick is max {level0, level1}
    // tick is mid {level2}
    // tick is max {leaf}
    assertTickAssumptions({
      tick: Tick.wrap(-1),
      posInLeaf: MAX_LEAF_POSITION,
      leafIndex: -1,
      posInLevel0: MAX_LEVEL0_POSITION,
      level0Index: -1,
      posInLevel1: MAX_LEVEL1_POSITION,
      level1Index: -1,
      posInLevel2: MAX_LEVEL2_POSITION / 2
    });

    // tick is mid {leaf, level0, level1, level2}
    assertTickAssumptions({
      tick: Tick.wrap(-8323),
      posInLeaf: MAX_LEAF_POSITION / 2,
      leafIndex: -2081,
      posInLevel0: MAX_LEVEL0_POSITION / 2,
      level0Index: -33,
      posInLevel1: MAX_LEVEL1_POSITION / 2,
      level1Index: -1,
      posInLevel2: MAX_LEVEL2_POSITION / 2
    });
  }
}
