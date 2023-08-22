// // SPDX-License-Identifier:	AGPL-3.0

// pragma solidity ^0.8.18;

// import {
//   GasTestBaseStored,
//   MIDDLE_TICK,
//   LEAF_LOWER_TICK,
//   LEAF_HIGHER_TICK,
//   LEVEL0_LOWER_TICK,
//   LEVEL0_HIGHER_TICK,
//   LEVEL1_LOWER_TICK,
//   LEVEL1_HIGHER_TICK,
//   LEVEL2_LOWER_TICK,
//   LEVEL2_HIGHER_TICK
// } from "./GasTestBase.t.sol";

// import {AbstractMangrove, TestTaker, OLKey} from "mgv_test/lib/MangroveTest.sol";

// /// Implements tests for all boundaries of tick values. Starting from a MIDDLE_TICK it goes above and below creating new branches for all levels.
// abstract contract TickBoundariesGasTest is GasTestBaseStored {
//   int internal tick;

//   function testTick(int tick_) internal virtual {
//     tick = tick_;
//     (AbstractMangrove mgv, TestTaker taker, OLKey memory _olKey, uint offerId) = getStored();
//     impl(mgv, taker, olKey, offerId, tick);
//   }

//   function impl(AbstractMangrove mgv, TestTaker taker, address base, address quote, uint offerId, int tick)
//     internal
//     virtual;

//   function test_ExistingTick() public {
//     testTick(MIDDLE_TICK);
//     description = string.concat(description, " - Case: Existing tick");
//     printDescription();
//   }

//   function test_ExistingLeafLowerTick() public {
//     testTick(LEAF_LOWER_TICK);
//     description = string.concat(description, " - Case: Existing leaf lower tick");
//     printDescription();
//   }

//   function test_ExistingLeafHigherTick() public {
//     testTick(LEAF_HIGHER_TICK);
//     description = string.concat(description, " - Case: Existing leaf higher tick");
//     printDescription();
//   }

//   function test_NewLevel0HigherTick() public {
//     testTick(LEVEL0_HIGHER_TICK);
//     description = string.concat(description, " - Case: New level0 higher tick");
//     printDescription();
//   }

//   function test_NewLevel0LowerTick() public {
//     testTick(LEVEL0_LOWER_TICK);
//     description = string.concat(description, " - Case: New level0 lower tick");
//     printDescription();
//   }

//   function test_NewLevel1HigherTick() public {
//     testTick(LEVEL1_HIGHER_TICK);
//     description = string.concat(description, " - Case: New level 1 higher tick");
//     printDescription();
//   }

//   function test_NewLevel1LowerTick() public {
//     testTick(LEVEL1_LOWER_TICK);
//     description = string.concat(description, " - Case: New level 1 lower tick");
//     printDescription();
//   }

//   function test_NewLevel2HigherTick() public {
//     testTick(LEVEL2_HIGHER_TICK);
//     description = string.concat(description, " - Case: New level 2 higher tick");
//     printDescription();
//   }

//   function test_NewLevel2LowerTick() public {
//     testTick(LEVEL2_LOWER_TICK);
//     description = string.concat(description, " - Case: New level 2 lower tick");
//     printDescription();
//   }
// }
