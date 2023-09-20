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

/// Implements tests for all boundaries of tick values. Starting from a MIDDLE_LOG_PRICE it goes above and below creating new branches for all levels.
abstract contract TickBoundariesGasTest is GasTestBaseStored {
  int internal logPrice;

  function testLogPrice(int _logPrice) internal virtual {
    logPrice = _logPrice;
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();

    impl(mgv, taker, _olKey, offerId, _logPrice);
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, int _logPrice) internal virtual;

  function test_ExistingTick() public {
    testLogPrice(MIDDLE_LOG_PRICE);
    description = string.concat(description, " - Case: Existing tick");
    printDescription();
  }

  function test_ExistingLeafLowerTick() public {
    testLogPrice(LEAF_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: Existing leaf lower tick");
    printDescription();
  }

  function test_ExistingLeafHigherTick() public {
    console.log("MIDDLE", MIDDLE_LOG_PRICE);
    console.log("LEAF HIGHER", LEAF_HIGHER_LOG_PRICE);
    testLogPrice(LEAF_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: Existing leaf higher tick");
    printDescription();
  }

  function test_NewLevel0HigherTick() public {
    testLogPrice(LEVEL0_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level0 higher tick");
    printDescription();
  }

  function test_NewLevel0LowerTick() public {
    testLogPrice(LEVEL0_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level0 lower tick");
    printDescription();
  }

  function test_NewLevel1HigherTick() public {
    testLogPrice(LEVEL1_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 1 higher tick");
    printDescription();
  }

  function test_NewLevel1LowerTick() public {
    testLogPrice(LEVEL1_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 1 lower tick");
    printDescription();
  }

  function test_NewLevel2HigherTick() public {
    testLogPrice(LEVEL2_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 2 higher tick");
    printDescription();
  }

  function test_NewLevel2LowerTick() public {
    testLogPrice(LEVEL2_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 2 lower tick");
    printDescription();
  }

  function test_NewRootHigherTick() public {
    testLogPrice(ROOT_HIGHER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 3 higher tick");
    printDescription();
  }

  function test_NewRootLowerTick() public {
    testLogPrice(ROOT_LOWER_LOG_PRICE);
    description = string.concat(description, " - Case: New level 3 lower tick");
    printDescription();
  }
}
