// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

// Tests of the assumptions made about bins in the TickTreeTests.
contract TickTreeTestAssumptionsTest is TickTreeTest {
  // Checks that the bins used in these tests have the expected locations at various levels.
  function test_bins_are_at_expected_locations() public {
    assertBinAssumptions({
      bin: BIN_MIN_ROOT_MAX_OTHERS,
      posInRoot: MIN_ROOT_POS,
      posInLevel1: MAX_LEVEL_POS,
      posInLevel2: MAX_LEVEL_POS,
      posInLevel3: MAX_LEVEL_POS,
      posInLeaf: MAX_LEAF_POS
    });

    assertBinAssumptions({
      bin: BIN_MAX_ROOT_MIN_OTHERS,
      posInRoot: MAX_ROOT_POS,
      posInLevel1: MIN_LEVEL_POS,
      posInLevel2: MIN_LEVEL_POS,
      posInLevel3: MIN_LEVEL_POS,
      posInLeaf: MIN_LEAF_POS
    });

    assertBinAssumptions({
      bin: BIN_MIDDLE,
      posInRoot: MID_ROOT_POS,
      posInLevel1: MID_LEVEL_POS,
      posInLevel2: MID_LEVEL_POS,
      posInLevel3: MID_LEVEL_POS,
      posInLeaf: MID_LEAF_POS
    });
  }
}
