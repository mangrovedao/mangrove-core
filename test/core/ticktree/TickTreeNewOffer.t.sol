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
//   - tick is a *tick of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. is empty
//     2. has one offer
//     3. has two offers
// - higher tick list
//   - tick has higher position in same leaf or level0-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list (in {leaf, level0, level1, level2})
//   - tick has lower position in same leaf or level0-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  struct NewOfferScenario {
    TickScenario tickScenario;
    uint insertionTickListSize;
  }

  uint[] tickListSizeScenarios = [0, 1, 2];
  // size of {lower,higher}TickList if the tick is present in the scenario
  uint[] otherTickListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_new_offer_for_TICK_MIN_ROOT_MAX_OTHERS() public {
    run_new_offer_scenarios_for_tick(TICK_MIN_ROOT_MAX_OTHERS);
  }

  function test_new_offer_for_TICK_MAX_ROOT_MIN_OTHERS() public {
    run_new_offer_scenarios_for_tick(TICK_MAX_ROOT_MIN_OTHERS);
  }

  function test_new_offer_for_TICK_MIDDLE() public {
    run_new_offer_scenarios_for_tick(TICK_MIDDLE);
  }

  function test_new_offer_for_TICK_MIN_ALLOWED() public {
    run_new_offer_scenarios_for_tick(TICK_MIN_ALLOWED);
  }

  function test_new_offer_for_TICK_MAX_ALLOWED() public {
    run_new_offer_scenarios_for_tick(TICK_MAX_ALLOWED);
  }

  function run_new_offer_scenarios_for_tick(Tick tick) internal {
    vm.pauseGasMetering();
    runTickScenarios(tick, otherTickListSizeScenarios, otherTickListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickScenario(TickScenario memory tickScenario) internal override {
    NewOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
      scenario.insertionTickListSize = tickListSizeScenarios[j];
      run_new_offer_scenario(scenario, false);
    }
    vm.resumeGasMetering();
  }

  // This test is useful for debugging a single scneario
  function test_single_new_offer_scenario() public {
    run_new_offer_scenario(
      NewOfferScenario({
        tickScenario: TickScenario({
          tick: Tick.wrap(0),
          hasHigherTick: false,
          higherTick: Tick.wrap(0),
          higherTickListSize: 0,
          hasLowerTick: false,
          lowerTick: Tick.wrap(0),
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
      console.log("  insertionTick: %s", toString(scenario.tickScenario.tick));
      console.log("  insertionTickListSize: %s", scenario.insertionTickListSize);
      if (scenario.tickScenario.hasHigherTick) {
        console.log("  higherTick: %s", toString(scenario.tickScenario.higherTick));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(scenario.tickScenario.lowerTick));
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
    Tick insertionTick = scenario.tickScenario.tick;
    int logPrice = LogPriceLib.fromTick(insertionTick, olKey.tickScale);
    uint gives = getAcceptableGivesForTick(insertionTick, 50_000);
    mkr.newOfferByLogPrice(logPrice, gives, 50_000, 50);
    tickTree.addOffer(insertionTick, gives, 50_000, 50, $(mkr));

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
