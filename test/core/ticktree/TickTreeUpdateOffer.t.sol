// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

// Tests of Mangrove.updateOffer's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the offer to be updated's bin (the offer itself may not be live)
//   - a higher bin
//   - a lower bin
// 2. we take a snapshot of Mangrove's tick tree
// 3. we update the offer in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - starting offer bin
//   - bin is a *bin of interest* (BoI) as listed in TickTreeTest
//   - list:
//     1. offer is not live
//     2. is singleton
//     3. updated offer is first of two offers
//     4. updated offer is last of two offers
//     5. updated offer is middle of three offers
//     - This is encoded as:
//       - list length
//       - offer pos
// - higher bin list
//   - bin has higher position in same leaf or level1-3 as BoI
//     - if feasible, given retraction bin
//   - list:
//     1. is empty
//     2. is non-empty
// - lower bin list
//   - bin has lower position in same leaf or level1-3 as BoI
//     - if feasible, given retraction bin
//   - list:
//     1. is empty
//     2. is non-empty
// - new offer bin
//   1. same bin
//   2. the lower bin
//   3. the higher bin
contract TickTreeUpdateOfferTest is TickTreeTest {
  struct UpdateOfferScenario {
    BinScenario binScenario;
    Bin newBin;
    uint offerBinListSize; // 0 -> offer is not live
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] binListScenarios = [[0, 0], [1, 0], [2, 0], [2, 1], [3, 1]];
  // size of {lower,higher}BinList
  uint[] emptyBinListSizeScenarios = [0];
  uint[] singletonBinListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through too many scenarios in one test: https://github.com/foundry-rs/foundry/issues/3971

  // Foundry will run this test way more than the needed 4 times for each bin due to bools being passed as uints.
  // This variant therefore takes too much time to run:
  //
  // function test_update_offer_for_bin_0(int24 bin, bool higherIsEmpty, bool lowerIsEmpty) public {
  //   vm.assume(Bin.wrap(bin).inRange());
  //   run_update_offer_scenarios_for_bin(
  //     bin,
  //     higherIsEmpty ? emptyBinListSizeScenarios : singletonBinListSizeScenarios,
  //     lowerIsEmpty ? emptyBinListSizeScenarios : singletonBinListSizeScenarios);
  // }
  //
  // Instead we make a test case for each combination of higherIsEmpty and lowerIsEmpty.
  //
  // NB: Fuzzing these tests for just the bin is super slow and also runs out of memory.
  //
  // function test_update_offer_for_bin_where_higher_is_empty_and_lower_is_empty(int24 bin) public {
  //   vm.assume(Bin.wrap(bin).inRange());
  //   run_update_offer_scenarios_for_bin(bin, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  // }
  //
  // We therefore restrict the ticks we test to the ToI

  // BIN_MIN_ROOT_MAX_OTHERS tests
  function test_update_offer_for_BIN_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIN_ROOT_MAX_OTHERS, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MIN_ROOT_MAX_OTHERS, emptyBinListSizeScenarios, singletonBinListSizeScenarios
    );
  }

  function test_update_offer_for_BIN_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MIN_ROOT_MAX_OTHERS, singletonBinListSizeScenarios, emptyBinListSizeScenarios
    );
  }

  function test_update_offer_for_BIN_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MIN_ROOT_MAX_OTHERS, singletonBinListSizeScenarios, singletonBinListSizeScenarios
    );
  }

  // BIN_MAX_ROOT_MIN_OTHERS tests
  function test_update_offer_for_BIN_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MAX_ROOT_MIN_OTHERS, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MAX_ROOT_MIN_OTHERS, emptyBinListSizeScenarios, singletonBinListSizeScenarios
    );
  }

  function test_update_offer_for_BIN_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MAX_ROOT_MIN_OTHERS, singletonBinListSizeScenarios, emptyBinListSizeScenarios
    );
  }

  function test_update_offer_for_BIN_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(
      BIN_MAX_ROOT_MIN_OTHERS, singletonBinListSizeScenarios, singletonBinListSizeScenarios
    );
  }

  // BIN_MIDDLE tests
  function test_update_offer_for_BIN_MIDDLE_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIDDLE, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIDDLE_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIDDLE, emptyBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIDDLE_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIDDLE, singletonBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIDDLE_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIDDLE, singletonBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  // BIN_MIN_ALLOWED tests
  function test_update_offer_for_BIN_MIN_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIN_ALLOWED, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIN_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIN_ALLOWED, emptyBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIN_ALLOWED, singletonBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MIN_ALLOWED, singletonBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  // BIN_MAX_ALLOWED tests
  function test_update_offer_for_BIN_MAX_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MAX_ALLOWED, emptyBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MAX_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MAX_ALLOWED, emptyBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MAX_ALLOWED, singletonBinListSizeScenarios, emptyBinListSizeScenarios);
  }

  function test_update_offer_for_BIN_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_bin(BIN_MAX_ALLOWED, singletonBinListSizeScenarios, singletonBinListSizeScenarios);
  }

  function run_update_offer_scenarios_for_bin(
    Bin bin,
    uint[] storage higherBinListSizeScenarios,
    uint[] storage lowerBinListSizeScenarios
  ) internal {
    runBinScenarios(bin, higherBinListSizeScenarios, lowerBinListSizeScenarios);
  }

  function runBinScenario(BinScenario memory binScenario) internal override {
    UpdateOfferScenario memory scenario;
    scenario.binScenario = binScenario;
    uint[2] storage binListScenario;

    for (uint j = 0; j < binListScenarios.length; ++j) {
      binListScenario = binListScenarios[j];
      scenario.offerBinListSize = binListScenario[0];
      scenario.offerPos = binListScenario[1];

      scenario.newBin = binScenario.bin;
      run_update_offer_scenario(scenario, false);
      if (binScenario.hasHigherBin) {
        scenario.newBin = binScenario.higherBin;
        run_update_offer_scenario(scenario, false);
      }
      if (binScenario.hasLowerBin) {
        scenario.newBin = binScenario.lowerBin;
        run_update_offer_scenario(scenario, false);
      }
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_update_offer_scenario() public {
    run_update_offer_scenario(
      UpdateOfferScenario({
        binScenario: BinScenario({
          bin: Bin.wrap(0),
          hasHigherBin: true,
          higherBin: Bin.wrap(524287),
          higherBinListSize: 1,
          hasLowerBin: true,
          lowerBin: Bin.wrap(-16384),
          lowerBinListSize: 0
        }),
        offerBinListSize: 1,
        offerPos: 0,
        newBin: Bin.wrap(-16384)
      }),
      true
    );
  }

  function run_update_offer_scenario(UpdateOfferScenario memory scenario, bool printToConsole) internal {
    setUp();
    // NB: Enabling all console.log statements will trigger an out-of-memory error when running through all test scenarios.
    // `printToConsole` is used to enable logging for specific scenarios.

    if (printToConsole) {
      console.log("update offer scenario");
      console.log("  oldBin: %s", toString(scenario.binScenario.bin));
      console.log("  newBin: %s", toString(scenario.newBin));
      console.log("  offerBinListSize: %s", scenario.offerBinListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.binScenario.hasHigherBin) {
        console.log("  higherBin: %s", toString(scenario.binScenario.higherBin));
        console.log("  higherBinListSize: %s", vm.toString(scenario.binScenario.higherBinListSize));
      }
      if (scenario.binScenario.hasLowerBin) {
        console.log("  lowerBin: %s", toString(scenario.binScenario.lowerBin));
        console.log("  lowerBinListSize: %s", vm.toString(scenario.binScenario.lowerBinListSize));
      }
    }

    // 1. Create scenario
    (uint[] memory offerIds,) =
      add_n_offers_to_bin(scenario.binScenario.bin, scenario.offerBinListSize == 0 ? 1 : scenario.offerBinListSize);
    uint offerId = offerIds[scenario.offerPos];
    OfferDetail offerDetail = mgv.offerDetails(olKey, offerId);
    if (scenario.offerBinListSize == 0) {
      mkr.retractOffer(offerIds[0]);
    }
    if (scenario.binScenario.hasHigherBin) {
      add_n_offers_to_bin(scenario.binScenario.higherBin, scenario.binScenario.higherBinListSize);
    }
    if (scenario.binScenario.hasLowerBin) {
      add_n_offers_to_bin(scenario.binScenario.lowerBin, scenario.binScenario.lowerBinListSize);
    }

    // 2. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();
    if (printToConsole) {
      console.log("before update");
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tick tree");
      tickTree.logTickTree();
    }

    // 3. Update the offer
    Bin newBin = scenario.newBin;
    uint newGives = getAcceptableGivesForBin(newBin, offerDetail.gasreq());
    mkr.updateOfferByTick(
      newBin.tick(olKey.tickSpacing), newGives, offerDetail.gasreq(), offerDetail.gasprice(), offerId
    );
    tickTree.updateOffer(offerId, newBin, newGives, offerDetail.gasreq(), offerDetail.gasprice(), $(mkr));
    if (printToConsole) {
      console.log("");
      console.log("after update");
      // NB: Fails with "field is 0" when MGV tick tree is inconsistent
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tick tree");
      tickTree.logTickTree();
    }

    // 4. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();
  }
}
