// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.newOffer's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the insertion tick
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tick tree
// 3. we insert a new offer at the insertion tick in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The reason for a having higher/lower ticks is to test Mangrove's handling of the levels that are stored in `local`.
// - if there are offers at a lower tick, the new offer will not be inserted on the best branch.
//   - But part of the branch may be shared -> we need to test the different cases of branch sharing: leaf, level0, level1, level2
// - if there are offers at a higher tick, those offer will not be be best after the new offer is inserted.
//   - If they were before, their path may need to be written to the mappings
//   - But part of the branch may be shared with the new best offer -> we need to test the different cases of branch sharing: leaf, level0, level1, level2
//
// The scenarios we want to test are:
// - empty book (this happens when lower, higher, and insertion ticks are empty)
// - insertion tick
//    - tick is MIN, MAX, min&max&mid {leaf, level0, level1, level2}
//    - list:
//      1. is empty
//      2. has one offer
//      3. has two offers
// - higher tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//      - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list (in {leaf, level0, level1, level2})
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.

  // Tick 0 (start leaf, start level0, start level1, mid level 2)
  function test_new_offer_for_tick_0() public {
    run_new_offer_scenarios_for_tick(0);
  }

  // Tick 1 (mid leaf, start level0, start level1, mid level 2)
  function test_new_offer_for_tick_1() public {
    run_new_offer_scenarios_for_tick(1);
  }

  // Tick 3 (end leaf, start level0, start level1, mid level 2)
  function test_new_offer_for_tick_3() public {
    run_new_offer_scenarios_for_tick(3);
  }

  // Tick -1 tests (end leaf, end level0, end level1, mid level 2)
  function test_new_offer_for_tick_negative_1() public {
    run_new_offer_scenarios_for_tick(-1);
  }

  // Tick -8323 tests (mid leaf, mid level0, mid level1, mid level 2)
  function test_new_offer_for_tick_negative_8323() public {
    run_new_offer_scenarios_for_tick(-8323);
  }

  // MAX_TICK (end leaf, end level0, end level1, end level 2)
  function test_new_offer_for_tick_max() public {
    run_new_offer_scenarios_for_tick(MAX_TICK);
  }

  // MIN_TICK tests (start leaf, start level0, start level1, start level 2)
  function test_new_offer_for_tick_min() public {
    run_new_offer_scenarios_for_tick(MIN_TICK);
  }

  struct NewOfferScenario {
    TickScenario tickScenario;
    uint insertionTickListSize;
  }

  uint[] tickListSizeScenarios = [0, 1, 2];
  // size of {lower,higher}TickList if the tick is present in the scenario
  uint[] otherTickListSizeScenarios = [1];

  function run_new_offer_scenarios_for_tick(int tick) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios =
      generateTickScenarios(tick, otherTickListSizeScenarios, otherTickListSizeScenarios);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
        uint insertionTickListSize = tickListSizeScenarios[j];
        run_new_offer_scenario(
          NewOfferScenario({tickScenario: tickScenario, insertionTickListSize: insertionTickListSize}), false
        );
      }
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_new_offer_scenario() public {
    run_new_offer_scenario(
      NewOfferScenario({
        tickScenario: TickScenario({
          tick: 0,
          hasHigherTick: true,
          higherTick: 4,
          higherTickListSize: 1,
          hasLowerTick: false,
          lowerTick: 0,
          lowerTickListSize: 0
        }),
        insertionTickListSize: 0
      }),
      true
    );
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("new offer scenario");
      console.log("  insertionTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
      console.log("  insertionTickListSize: %s", scenario.insertionTickListSize);
      if (scenario.tickScenario.hasHigherTick) {
        console.log("  higherTick: %s", toString(Tick.wrap(scenario.tickScenario.higherTick)));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.tick, scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.tickScenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.tickScenario.lowerTickListSize);
    }

    // 3. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Create new offer and add it to tick tree
    Tick _insertionTick = Tick.wrap(scenario.tickScenario.tick);
    int logPrice = LogPriceLib.fromTick(_insertionTick, olKey.tickScale, olKey.tickShift);
    uint gives = getAcceptableGivesForTick(_insertionTick, 50_000);
    mkr.newOfferByLogPrice(logPrice, gives, 50_000, 50);
    tickTree.addOffer(_insertionTick, gives, 50_000, 50, $(mkr));

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvOffer();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
