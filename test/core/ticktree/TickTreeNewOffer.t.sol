// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.newOffer's interaction with the tickTreeIndex tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tickTreeIndex tree where there may be offers at:
//   - the insertion tick
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tickTreeIndex tree
// 3. we insert a new offer at the insertion tickTreeIndex in both Mangrove and in the snapshot tickTreeIndex tree
// 4. we check that Mangrove's tickTreeIndex tree matches the test tickTreeIndex tree.
//
// The reason for a having higher/lower ticks is to test Mangrove's handling of the levels that are stored in `local`.
// - if there are offers at a lower tickTreeIndex, the new offer will not be inserted on the best branch.
//   - But part of the branch may be shared -> we need to test the different cases of branch sharing: leaf, level0, level1, level2
// - if there are offers at a higher tickTreeIndex, those offer will not be be best after the new offer is inserted.
//   - If they were before, their path may need to be written to the mappings
//   - But part of the branch may be shared with the new best offer -> we need to test the different cases of branch sharing: leaf, level0, level1, level2
//
// The scenarios we want to test are:
// - empty book (this happens when lower, higher, and insertion ticks are empty)
// - insertion tick
//   - tickTreeIndex is a *tickTreeIndex of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. is empty
//     2. has one offer
//     3. has two offers
// - higher tickTreeIndex list
//   - tickTreeIndex has higher position in same leaf or level0-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tickTreeIndex list (in {leaf, level0, level1, level2})
//   - tickTreeIndex has lower position in same leaf or level0-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  struct NewOfferScenario {
    TickTreeIndexScenario tickScenario;
    uint insertionTickTreeIndexListSize;
  }

  uint[] tickListSizeScenarios = [0, 1, 2];
  // size of {lower,higher}TickTreeIndexList if the tickTreeIndex is present in the scenario
  uint[] otherTickTreeIndexListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_new_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS() public {
    run_new_offer_scenarios_for_tick(TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS);
  }

  function test_new_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS() public {
    run_new_offer_scenarios_for_tick(TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS);
  }

  function test_new_offer_for_TICK_TREE_INDEX_MIDDLE() public {
    run_new_offer_scenarios_for_tick(TICK_TREE_INDEX_MIDDLE);
  }

  function test_new_offer_for_TICK_TREE_INDEX_MIN_ALLOWED() public {
    run_new_offer_scenarios_for_tick(TICK_TREE_INDEX_MIN_ALLOWED);
  }

  function test_new_offer_for_TICK_TREE_INDEX_MAX_ALLOWED() public {
    run_new_offer_scenarios_for_tick(TICK_TREE_INDEX_MAX_ALLOWED);
  }

  function run_new_offer_scenarios_for_tick(TickTreeIndex tickTreeIndex) internal {
    vm.pauseGasMetering();
    runTickTreeIndexScenarios(tickTreeIndex, otherTickTreeIndexListSizeScenarios, otherTickTreeIndexListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickTreeIndexScenario(TickTreeIndexScenario memory tickScenario) internal override {
    NewOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
      scenario.insertionTickTreeIndexListSize = tickListSizeScenarios[j];
      run_new_offer_scenario(scenario, false);
    }
    vm.resumeGasMetering();
  }

  // This test is useful for debugging a single scneario
  function test_single_new_offer_scenario() public {
    run_new_offer_scenario(
      NewOfferScenario({
        tickScenario: TickTreeIndexScenario({
          tickTreeIndex: TickTreeIndex.wrap(0),
          hasHigherTickTreeIndex: false,
          higherTickTreeIndex: TickTreeIndex.wrap(0),
          higherTickTreeIndexListSize: 0,
          hasLowerTickTreeIndex: false,
          lowerTickTreeIndex: TickTreeIndex.wrap(0),
          lowerTickTreeIndexListSize: 0
        }),
        insertionTickTreeIndexListSize: 0
      }),
      true
    );
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("new offer scenario");
      console.log("  insertionTickTreeIndex: %s", toString(scenario.tickScenario.tickTreeIndex));
      console.log("  insertionTickTreeIndexListSize: %s", scenario.insertionTickTreeIndexListSize);
      if (scenario.tickScenario.hasHigherTickTreeIndex) {
        console.log("  higherTickTreeIndex: %s", toString(scenario.tickScenario.higherTickTreeIndex));
      }
      if (scenario.tickScenario.hasLowerTickTreeIndex) {
        console.log("  lowerTickTreeIndex: %s", toString(scenario.tickScenario.lowerTickTreeIndex));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.tickTreeIndex, scenario.insertionTickTreeIndexListSize);
    if (scenario.tickScenario.hasHigherTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.higherTickTreeIndex, scenario.tickScenario.higherTickTreeIndexListSize);
    }
    if (scenario.tickScenario.hasLowerTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTickTreeIndex, scenario.tickScenario.lowerTickTreeIndexListSize);
    }

    // 3. Snapshot tickTreeIndex tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Create new offer and add it to tickTreeIndex tree
    TickTreeIndex insertionTickTreeIndex = scenario.tickScenario.tickTreeIndex;
    int tick = TickLib.fromTickTreeIndex(insertionTickTreeIndex, olKey.tickSpacing);
    uint gives = getAcceptableGivesForTickTreeIndex(insertionTickTreeIndex, 50_000);
    mkr.newOfferByTick(tick, gives, 50_000, 50);
    tickTree.addOffer(insertionTickTreeIndex, gives, 50_000, 50, $(mkr));

    // 5. Assert that Mangrove and tickTreeIndex tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
