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
// 3. we insert a new offer at the insertion bin in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The reason for a having higher/lower ticks is to test Mangrove's handling of the levels that are stored in `local`.
// - if there are offers at a lower bin, the new offer will not be inserted on the best branch.
//   - But part of the branch may be shared -> we need to test the different cases of branch sharing: leaf, level3, level2, level1
// - if there are offers at a higher bin, those offer will not be be best after the new offer is inserted.
//   - If they were before, their path may need to be written to the mappings
//   - But part of the branch may be shared with the new best offer -> we need to test the different cases of branch sharing: leaf, level3, level2, level1
//
// The scenarios we want to test are:
// - empty book (this happens when lower, higher, and insertion ticks are empty)
// - insertion tick
//   - bin is a *bin of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. is empty
//     2. has one offer
//     3. has two offers
// - higher bin list
//   - bin has higher position in same leaf or level3-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower bin list (in {leaf, level3, level2, level1})
//   - bin has lower position in same leaf or level3-3 as ToI
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  struct NewOfferScenario {
    BinScenario tickScenario;
    uint insertionBinListSize;
  }

  uint[] tickListSizeScenarios = [0, 1, 2];
  // size of {lower,higher}BinList if the bin is present in the scenario
  uint[] otherBinListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_new_offer_for_BIN_MIN_ROOT_MAX_OTHERS() public {
    run_new_offer_scenarios_for_tick(BIN_MIN_ROOT_MAX_OTHERS);
  }

  function test_new_offer_for_BIN_MAX_ROOT_MIN_OTHERS() public {
    run_new_offer_scenarios_for_tick(BIN_MAX_ROOT_MIN_OTHERS);
  }

  function test_new_offer_for_BIN_MIDDLE() public {
    run_new_offer_scenarios_for_tick(BIN_MIDDLE);
  }

  function test_new_offer_for_BIN_MIN_ALLOWED() public {
    run_new_offer_scenarios_for_tick(BIN_MIN_ALLOWED);
  }

  function test_new_offer_for_BIN_MAX_ALLOWED() public {
    run_new_offer_scenarios_for_tick(BIN_MAX_ALLOWED);
  }

  function run_new_offer_scenarios_for_tick(Bin bin) internal {
    vm.pauseGasMetering();
    runBinScenarios(bin, otherBinListSizeScenarios, otherBinListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runBinScenario(BinScenario memory tickScenario) internal override {
    NewOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
      scenario.insertionBinListSize = tickListSizeScenarios[j];
      run_new_offer_scenario(scenario, false);
    }
    vm.resumeGasMetering();
  }

  // This test is useful for debugging a single scneario
  function test_single_new_offer_scenario() public {
    run_new_offer_scenario(
      NewOfferScenario({
        tickScenario: BinScenario({
          bin: Bin.wrap(0),
          hasHigherBin: false,
          higherBin: Bin.wrap(0),
          higherBinListSize: 0,
          hasLowerBin: false,
          lowerBin: Bin.wrap(0),
          lowerBinListSize: 0
        }),
        insertionBinListSize: 0
      }),
      true
    );
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("new offer scenario");
      console.log("  insertionBin: %s", toString(scenario.tickScenario.bin));
      console.log("  insertionBinListSize: %s", scenario.insertionBinListSize);
      if (scenario.tickScenario.hasHigherBin) {
        console.log("  higherBin: %s", toString(scenario.tickScenario.higherBin));
      }
      if (scenario.tickScenario.hasLowerBin) {
        console.log("  lowerBin: %s", toString(scenario.tickScenario.lowerBin));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.bin, scenario.insertionBinListSize);
    if (scenario.tickScenario.hasHigherBin) {
      add_n_offers_to_tick(scenario.tickScenario.higherBin, scenario.tickScenario.higherBinListSize);
    }
    if (scenario.tickScenario.hasLowerBin) {
      add_n_offers_to_tick(scenario.tickScenario.lowerBin, scenario.tickScenario.lowerBinListSize);
    }

    // 3. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Create new offer and add it to tick tree
    Bin insertionBin = scenario.tickScenario.bin;
    int tick = TickLib.fromBin(insertionBin, olKey.tickSpacing);
    uint gives = getAcceptableGivesForBin(insertionBin, 50_000);
    mkr.newOfferByTick(tick, gives, 50_000, 50);
    tickTree.addOffer(insertionBin, gives, 50_000, 50, $(mkr));

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
