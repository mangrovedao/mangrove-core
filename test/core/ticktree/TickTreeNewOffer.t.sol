// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

// Tests of Mangrove.newOffer's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the insertion bin
//   - a higher bin
//   - a lower bin
// 2. we take a snapshot of Mangrove's tick tree
// 3. we insert a new offer at the insertion bin in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The reason for a having higher/lower bins is to test Mangrove's handling of the levels that are stored in `local`.
// - if there are offers at a lower bin, the new offer will not be inserted on the best branch.
//   - But part of the branch may be shared -> we need to test the different cases of branch sharing: leaf, level3, level2, level1
// - if there are offers at a higher bin, those offer will not be be best after the new offer is inserted.
//   - If they were before, their path may need to be written to the mappings
//   - But part of the branch may be shared with the new best offer -> we need to test the different cases of branch sharing: leaf, level3, level2, level1
//
// The scenarios we want to test are:
// - empty book (this happens when lower, higher, and insertion bins are empty)
// - insertion bin
//   - bin is a *bin of interest* (BoI) as listed in TickTreeTest
//   - list:
//     1. is empty
//     2. has one offer
//     3. has two offers
// - higher bin list
//   - bin has higher position in same leaf or level1-3 as BoI
//     - if feasible, given insertion bin
//   - list:
//     1. is empty
//     2. is non-empty
// - lower bin list (in {leaf, level3, level2, level1})
//   - bin has lower position in same leaf or level1-3 as BoI
//     - if feasible, given insertion bin
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  struct NewOfferScenario {
    BinScenario binScenario;
    uint insertionBinListSize;
  }

  uint[] binListSizeScenarios = [0, 1, 2];
  // size of {lower,higher}BinList if the bin is present in the scenario
  uint[] otherBinListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_new_offer_for_BIN_MIN_ROOT_MAX_OTHERS() public {
    run_new_offer_scenarios_for_bin(BIN_MIN_ROOT_MAX_OTHERS);
  }

  function test_new_offer_for_BIN_MAX_ROOT_MIN_OTHERS() public {
    run_new_offer_scenarios_for_bin(BIN_MAX_ROOT_MIN_OTHERS);
  }

  function test_new_offer_for_BIN_MIDDLE() public {
    run_new_offer_scenarios_for_bin(BIN_MIDDLE);
  }

  function test_new_offer_for_BIN_MIN_ALLOWED() public {
    run_new_offer_scenarios_for_bin(BIN_MIN_ALLOWED);
  }

  function test_new_offer_for_BIN_MAX_ALLOWED() public {
    run_new_offer_scenarios_for_bin(BIN_MAX_ALLOWED);
  }

  function run_new_offer_scenarios_for_bin(Bin bin) internal {
    runBinScenarios(bin, otherBinListSizeScenarios, otherBinListSizeScenarios);
  }

  function runBinScenario(BinScenario memory binScenario) internal override {
    NewOfferScenario memory scenario;
    scenario.binScenario = binScenario;
    for (uint j = 0; j < binListSizeScenarios.length; ++j) {
      scenario.insertionBinListSize = binListSizeScenarios[j];
      run_new_offer_scenario(scenario, false);
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_new_offer_scenario() public {
    run_new_offer_scenario(
      NewOfferScenario({
        binScenario: BinScenario({
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
    setUp();
    if (printToConsole) {
      console.log("new offer scenario");
      console.log("  insertionBin: %s", toString(scenario.binScenario.bin));
      console.log("  insertionBinListSize: %s", scenario.insertionBinListSize);
      if (scenario.binScenario.hasHigherBin) {
        console.log("  higherBin: %s", toString(scenario.binScenario.higherBin));
      }
      if (scenario.binScenario.hasLowerBin) {
        console.log("  lowerBin: %s", toString(scenario.binScenario.lowerBin));
      }
    }

    // 1. Create scenario
    add_n_offers_to_bin(scenario.binScenario.bin, scenario.insertionBinListSize);
    if (scenario.binScenario.hasHigherBin) {
      add_n_offers_to_bin(scenario.binScenario.higherBin, scenario.binScenario.higherBinListSize);
    }
    if (scenario.binScenario.hasLowerBin) {
      add_n_offers_to_bin(scenario.binScenario.lowerBin, scenario.binScenario.lowerBinListSize);
    }

    // 2. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();

    // 3. Create new offer and add it to tick tree
    Bin insertionBin = scenario.binScenario.bin;
    Tick tick = insertionBin.tick(olKey.tickSpacing);
    uint gives = getAcceptableGivesForBin(insertionBin, 50_000);
    mkr.newOfferByTick(tick, gives, 50_000, 50);
    tickTree.addOffer(insertionBin, gives, 50_000, 50, $(mkr));

    // 4. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();
  }
}
