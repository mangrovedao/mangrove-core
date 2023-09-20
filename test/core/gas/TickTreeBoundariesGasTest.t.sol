// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  GasTestBaseStored,
  MIDDLE_LOG_PRICE,
  LEAF_LOWER_LOG_PRICE,
  LEAF_HIGHER_LOG_PRICE,
  LEVEL0_LOWER_LOG_PRICE,
  LEVEL0_HIGHER_LOG_PRICE,
  LEVEL1_LOWER_LOG_PRICE,
  LEVEL1_HIGHER_LOG_PRICE,
  LEVEL2_LOWER_LOG_PRICE,
  LEVEL2_HIGHER_LOG_PRICE,
  ROOT_LOWER_LOG_PRICE,
  ROOT_HIGHER_LOG_PRICE
} from "./GasTestBase.t.sol";

import {IMangrove, TestTaker, OLKey, MgvStructs} from "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Debug.sol";

/// Implements tests for all boundaries of tickTreeIndex values. Starting from a MIDDLE_LOG_PRICE it goes above and below creating new branches for all levels.
abstract contract TickTreeBoundariesGasTest is GasTestBaseStored {
  int internal tick;

  function testTick(int _tick) internal virtual {
    tick = _tick;
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();

    impl(mgv, taker, _olKey, offerId, _tick);
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, int _tick) internal virtual;

  function test_ExistingTickTreeIndex() public {
    testTick(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: Existing tick");
    printDescription();
  }

  function test_ExistingLeafLowerTickTreeIndex() public {
    testTick(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: Existing leaf lower tick");
    printDescription();
  }

  function test_ExistingLeafHigherTickTreeIndex() public {
    console.log("MIDDLE", MIDDLE_LOG_PRICE);
    console.log("LEAF HIGHER", LEAF_HIGHER_LOG_PRICE);
    testTick(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: Existing leaf higher tick");
    printDescription();
  }

  function test_NewLevel0HigherTickTreeIndex() public {
    testTick(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level0 higher tick");
    printDescription();
  }

  function test_NewLevel0LowerTickTreeIndex() public {
    testTick(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level0 lower tick");
    printDescription();
  }

  function test_NewLevel1HigherTickTreeIndex() public {
    testTick(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 1 higher tick");
    printDescription();
  }

  function test_NewLevel1LowerTickTreeIndex() public {
    testTick(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 1 lower tick");
    printDescription();
  }

  function test_NewLevel2HigherTickTreeIndex() public {
    testTick(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 2 higher tick");
    printDescription();
  }

  function test_NewLevel2LowerTickTreeIndex() public {
    testTick(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 2 lower tick");
    printDescription();
  }

  function test_NewRootHigherTickTreeIndex() public {
    testTick(ROOT_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 3 higher tick");
    printDescription();
  }

  function test_NewRootLowerTickTreeIndex() public {
    testTick(ROOT_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 3 lower tick");
    printDescription();
  }
}
