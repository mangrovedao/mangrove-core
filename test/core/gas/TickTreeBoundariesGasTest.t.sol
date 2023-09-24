// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  GasTestBaseStored,
  MIDDLE_BIN,
  LEAF_LOWER_BIN,
  LEAF_HIGHER_BIN,
  LEVEL3_LOWER_BIN,
  LEVEL3_HIGHER_BIN,
  LEVEL2_LOWER_BIN,
  LEVEL2_HIGHER_BIN,
  LEVEL1_LOWER_BIN,
  LEVEL1_HIGHER_BIN,
  ROOT_LOWER_BIN,
  ROOT_HIGHER_BIN
} from "./GasTestBase.t.sol";

import {IMangrove, TestTaker, OLKey, MgvStructs} from "mgv_test/lib/MangroveTest.sol";
import "mgv_lib/Debug.sol";

/// Implements tests for all boundaries of bin values. Starting from a MIDDLE_BIN it goes above and below creating new branches for all levels.
abstract contract TickTreeBoundariesGasTest is GasTestBaseStored {
  Bin internal bin;

  function testBin(Bin _bin) internal virtual {
    bin = _bin;
    (IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();

    impl(mgv, taker, _olKey, offerId, _bin);
  }

  function impl(IMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId, Bin _bin) internal virtual;

  function test_ExistingBin() public {
    testBin(MIDDLE_BIN);
    description = string.concat(description, " - Case: Existing bin");
    printDescription();
  }

  function test_ExistingLeafLowerBin() public {
    testBin(LEAF_LOWER_BIN);
    description = string.concat(description, " - Case: Existing leaf lower bin");
    printDescription();
  }

  function test_ExistingLeafHigherBin() public {
    console.log("MIDDLE", toString(MIDDLE_BIN));
    console.log("LEAF HIGHER", toString(LEAF_HIGHER_BIN));
    testBin(LEAF_HIGHER_BIN);
    description = string.concat(description, " - Case: Existing leaf higher bin");
    printDescription();
  }

  function test_NewLevel3HigherBin() public {
    testBin(LEVEL3_HIGHER_BIN);
    description = string.concat(description, " - Case: New level3 higher bin");
    printDescription();
  }

  function test_NewLevel3LowerBin() public {
    testBin(LEVEL3_LOWER_BIN);
    description = string.concat(description, " - Case: New level3 lower bin");
    printDescription();
  }

  function test_NewLevel2HigherBin() public {
    testBin(LEVEL2_HIGHER_BIN);
    description = string.concat(description, " - Case: New level 2 higher bin");
    printDescription();
  }

  function test_NewLevel2LowerBin() public {
    testBin(LEVEL2_LOWER_BIN);
    description = string.concat(description, " - Case: New level 2 lower bin");
    printDescription();
  }

  function test_NewLevel1HigherBin() public {
    testBin(LEVEL1_HIGHER_BIN);
    description = string.concat(description, " - Case: New level 1 higher bin");
    printDescription();
  }

  function test_NewLevel1LowerBin() public {
    testBin(LEVEL1_LOWER_BIN);
    description = string.concat(description, " - Case: New level 1 lower bin");
    printDescription();
  }

  function test_NewRootHigherBin() public {
    testBin(ROOT_HIGHER_BIN);
    description = string.concat(description, " - Case: New root higher bin");
    printDescription();
  }

  function test_NewRootLowerBin() public {
    testBin(ROOT_LOWER_BIN);
    description = string.concat(description, " - Case: New root lower bin");
    printDescription();
  }
}
