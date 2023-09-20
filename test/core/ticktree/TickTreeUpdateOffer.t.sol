// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.updateOffer's interaction with the tickTreeIndex tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tickTreeIndex tree where there may be offers at:
//   - the offer to be updated's tickTreeIndex (the offer itself may not be live)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tickTreeIndex tree
// 3. we update the offer in both Mangrove and in the snapshot tickTreeIndex tree
// 4. we check that Mangrove's tickTreeIndex tree matches the test tickTreeIndex tree.
//
// The scenarios we want to test are:
// - starting offer tick
//   - tickTreeIndex is a *tickTreeIndex of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. offer is not live
//     2. is singleton
//     3. updated offer is first of two offers
//     4. updated offer is last of two offers
//     5. updated offer is middle of three offers
//     - This is encoded as:
//       - list length
//       - offer pos
// - higher tickTreeIndex list
//   - tickTreeIndex has higher position in same leaf or level0-3 as ToI
//     - if feasible, given retraction tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tickTreeIndex list
//   - tickTreeIndex has lower position in same leaf or level0-3 as ToI
//     - if feasible, given retraction tick
//   - list:
//     1. is empty
//     2. is non-empty
// - new offer tick
//   1. same tick
//   2. the lower tick
//   3. the higher tick
contract TickTreeUpdateOfferTest is TickTreeTest {
  struct UpdateOfferScenario {
    TickTreeIndexScenario tickScenario;
    TickTreeIndex newTickTreeIndex;
    uint offerTickTreeIndexListSize; // 0 -> offer is not live
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[0, 0], [1, 0], [2, 0], [2, 1], [3, 1]];
  // size of {lower,higher}TickTreeIndexList
  uint[] emptyTickTreeIndexListSizeScenarios = [0];
  uint[] singletonTickTreeIndexListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through too many scenarios in one test: https://github.com/foundry-rs/foundry/issues/3971

  // Foundry will run this test way more than the needed 4 times for each tickTreeIndex due to bools being passed as uints.
  // This variant therefore takes too much time to run:
  //
  // function test_update_offer_for_tick_0(int24 tickTreeIndex, bool higherIsEmpty, bool lowerIsEmpty) public {
  //   vm.assume(TickTreeIndex.wrap(tickTreeIndex).inRange());
  //   run_update_offer_scenarios_for_tick(
  //     tickTreeIndex,
  //     higherIsEmpty ? emptyTickTreeIndexListSizeScenarios : singletonTickTreeIndexListSizeScenarios,
  //     lowerIsEmpty ? emptyTickTreeIndexListSizeScenarios : singletonTickTreeIndexListSizeScenarios);
  // }
  //
  // Instead we make a test case for each combination of higherIsEmpty and lowerIsEmpty.
  //
  // NB: Fuzzing these tests for just the tickTreeIndex is super slow and also runs out of memory.
  //
  // function test_update_offer_for_tick_where_higher_is_empty_and_lower_is_empty(int24 tickTreeIndex) public {
  //   vm.assume(TickTreeIndex.wrap(tickTreeIndex).inRange());
  //   run_update_offer_scenarios_for_tick(tickTreeIndex, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios);
  // }
  //
  // We therefore restrict the ticks we test to the ToI

  // TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS tests
  function test_update_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_not_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS, emptyTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS, singletonTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS,
      singletonTickTreeIndexListSizeScenarios,
      singletonTickTreeIndexListSizeScenarios
    );
  }

  // TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS tests
  function test_update_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_not_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS, emptyTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS, singletonTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty()
    public
  {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS,
      singletonTickTreeIndexListSizeScenarios,
      singletonTickTreeIndexListSizeScenarios
    );
  }

  // TICK_TREE_INDEX_MIDDLE tests
  function test_update_offer_for_TICK_TREE_INDEX_MIDDLE_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIDDLE, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIDDLE_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIDDLE, emptyTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIDDLE_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIDDLE, singletonTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIDDLE_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIDDLE, singletonTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  // TICK_TREE_INDEX_MIN_ALLOWED tests
  function test_update_offer_for_TICK_TREE_INDEX_MIN_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ALLOWED, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ALLOWED, emptyTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ALLOWED, singletonTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MIN_ALLOWED, singletonTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  // TICK_TREE_INDEX_MAX_ALLOWED tests
  function test_update_offer_for_TICK_TREE_INDEX_MAX_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ALLOWED, emptyTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ALLOWED, emptyTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ALLOWED, singletonTickTreeIndexListSizeScenarios, emptyTickTreeIndexListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_TREE_INDEX_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_TREE_INDEX_MAX_ALLOWED, singletonTickTreeIndexListSizeScenarios, singletonTickTreeIndexListSizeScenarios
    );
  }

  function run_update_offer_scenarios_for_tick(
    TickTreeIndex tickTreeIndex,
    uint[] storage higherTickTreeIndexListSizeScenarios,
    uint[] storage lowerTickTreeIndexListSizeScenarios
  ) internal {
    vm.pauseGasMetering();
    runTickTreeIndexScenarios(tickTreeIndex, higherTickTreeIndexListSizeScenarios, lowerTickTreeIndexListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickTreeIndexScenario(TickTreeIndexScenario memory tickScenario) internal override {
    UpdateOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListScenarios.length; ++j) {
      uint[2] storage tickListScenario = tickListScenarios[j];
      scenario.offerTickTreeIndexListSize = tickListScenario[0];
      scenario.offerPos = tickListScenario[1];

      scenario.newTickTreeIndex = tickScenario.tickTreeIndex;
      run_update_offer_scenario(scenario, false);
      if (tickScenario.hasHigherTickTreeIndex) {
        scenario.newTickTreeIndex = tickScenario.higherTickTreeIndex;
        run_update_offer_scenario(scenario, false);
      }
      if (tickScenario.hasLowerTickTreeIndex) {
        scenario.newTickTreeIndex = tickScenario.lowerTickTreeIndex;
        run_update_offer_scenario(scenario, false);
      }
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_update_offer_scenario() public {
    run_update_offer_scenario(
      UpdateOfferScenario({
        tickScenario: TickTreeIndexScenario({
          tickTreeIndex: TickTreeIndex.wrap(0),
          hasHigherTickTreeIndex: true,
          higherTickTreeIndex: TickTreeIndex.wrap(524287),
          higherTickTreeIndexListSize: 1,
          hasLowerTickTreeIndex: true,
          lowerTickTreeIndex: TickTreeIndex.wrap(-16384),
          lowerTickTreeIndexListSize: 0
        }),
        offerTickTreeIndexListSize: 1,
        offerPos: 0,
        newTickTreeIndex: TickTreeIndex.wrap(-16384)
      }),
      true
    );
  }

  function run_update_offer_scenario(UpdateOfferScenario memory scenario, bool printToConsole) internal {
    // NB: Enabling all console.log statements will trigger an out-of-memory error when running through all test scenarios.
    // `printToConsole` is used to enable logging for specific scenarios.

    if (printToConsole) {
      console.log("update offer scenario");
      console.log("  oldTickTreeIndex: %s", toString(scenario.tickScenario.tickTreeIndex));
      console.log("  newTickTreeIndex: %s", toString(scenario.newTickTreeIndex));
      console.log("  offerTickTreeIndexListSize: %s", scenario.offerTickTreeIndexListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.tickScenario.hasHigherTickTreeIndex) {
        console.log("  higherTickTreeIndex: %s", toString(scenario.tickScenario.higherTickTreeIndex));
        console.log("  higherTickTreeIndexListSize: %s", vm.toString(scenario.tickScenario.higherTickTreeIndexListSize));
      }
      if (scenario.tickScenario.hasLowerTickTreeIndex) {
        console.log("  lowerTickTreeIndex: %s", toString(scenario.tickScenario.lowerTickTreeIndex));
        console.log("  lowerTickTreeIndexListSize: %s", vm.toString(scenario.tickScenario.lowerTickTreeIndexListSize));
      }
    }

    // 1. Capture VM state before scenario so we can restore it after
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory offerIds,) = add_n_offers_to_tick(
      scenario.tickScenario.tickTreeIndex,
      scenario.offerTickTreeIndexListSize == 0 ? 1 : scenario.offerTickTreeIndexListSize
    );
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);
    if (scenario.offerTickTreeIndexListSize == 0) {
      mkr.retractOffer(offerIds[0]);
    }
    if (scenario.tickScenario.hasHigherTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.higherTickTreeIndex, scenario.tickScenario.higherTickTreeIndexListSize);
    }
    if (scenario.tickScenario.hasLowerTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTickTreeIndex, scenario.tickScenario.lowerTickTreeIndexListSize);
    }

    // 3. Snapshot tickTreeIndex tree
    TestTickTree tickTree = snapshotTickTree();
    if (printToConsole) {
      console.log("before update");
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tickTreeIndex tree");
      tickTree.logTickTree();
    }

    // 4. Update the offer
    TickTreeIndex newTickTreeIndex = scenario.newTickTreeIndex;
    uint newGives = getAcceptableGivesForTickTreeIndex(newTickTreeIndex, offerDetail.gasreq());
    mkr.updateOfferByTick(
      TickLib.fromTickTreeIndex(newTickTreeIndex, olKey.tickSpacing),
      newGives,
      offerDetail.gasreq(),
      offerDetail.gasprice(),
      offerId
    );
    tickTree.updateOffer(offerId, newTickTreeIndex, newGives, offerDetail.gasreq(), offerDetail.gasprice(), $(mkr));
    if (printToConsole) {
      console.log("");
      console.log("after update");
      // NB: Fails with "field is 0" when MGV tickTreeIndex tree is inconsistent
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tickTreeIndex tree");
      tickTree.logTickTree();
    }

    // 5. Assert that Mangrove and tickTreeIndex tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
