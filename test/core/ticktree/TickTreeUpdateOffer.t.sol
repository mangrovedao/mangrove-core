// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.updateOffer's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the offer to be updated's tick (the offer itself may not be live)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tick tree
// 3. we update the offer in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - starting offer tick
//   - tick is a *tick of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. offer is not live
//     2. is singleton
//     3. updated offer is first of two offers
//     4. updated offer is last of two offers
//     5. updated offer is middle of three offers
//     - This is encoded as:
//       - list length
//       - offer pos
// - higher tick list
//   - tick has higher position in same leaf or level0-3 as ToI
//     - if feasible, given retraction tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list
//   - tick has lower position in same leaf or level0-3 as ToI
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
    TickScenario tickScenario;
    Tick newTick;
    uint offerTickListSize; // 0 -> offer is not live
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[0, 0], [1, 0], [2, 0], [2, 1], [3, 1]];
  // size of {lower,higher}TickList
  uint[] emptyTickListSizeScenarios = [0];
  uint[] singletonTickListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through too many scenarios in one test: https://github.com/foundry-rs/foundry/issues/3971

  // Foundry will run this test way more than the needed 4 times for each tick due to bools being passed as uints.
  // This variant therefore takes too much time to run:
  //
  // function test_update_offer_for_tick_0(int24 tick, bool higherIsEmpty, bool lowerIsEmpty) public {
  //   vm.assume(Tick.wrap(tick).inRange());
  //   run_update_offer_scenarios_for_tick(
  //     tick,
  //     higherIsEmpty ? emptyTickListSizeScenarios : singletonTickListSizeScenarios,
  //     lowerIsEmpty ? emptyTickListSizeScenarios : singletonTickListSizeScenarios);
  // }
  //
  // Instead we make a test case for each combination of higherIsEmpty and lowerIsEmpty.
  //
  // NB: Fuzzing these tests for just the tick is super slow and also runs out of memory.
  //
  // function test_update_offer_for_tick_where_higher_is_empty_and_lower_is_empty(int24 tick) public {
  //   vm.assume(Tick.wrap(tick).inRange());
  //   run_update_offer_scenarios_for_tick(tick, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  // }
  //
  // We therefore restrict the ticks we test to the ToI

  // TICK_MIN_ROOT_MAX_OTHERS tests
  function test_update_offer_for_TICK_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MIN_ROOT_MAX_OTHERS, emptyTickListSizeScenarios, emptyTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MIN_ROOT_MAX_OTHERS_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MIN_ROOT_MAX_OTHERS, emptyTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MIN_ROOT_MAX_OTHERS, singletonTickListSizeScenarios, emptyTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MIN_ROOT_MAX_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MIN_ROOT_MAX_OTHERS, singletonTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  // TICK_MAX_ROOT_MIN_OTHERS tests
  function test_update_offer_for_TICK_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MAX_ROOT_MIN_OTHERS, emptyTickListSizeScenarios, emptyTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MAX_ROOT_MIN_OTHERS_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MAX_ROOT_MIN_OTHERS, emptyTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MAX_ROOT_MIN_OTHERS, singletonTickListSizeScenarios, emptyTickListSizeScenarios
    );
  }

  function test_update_offer_for_TICK_MAX_ROOT_MIN_OTHERS_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MAX_ROOT_MIN_OTHERS, singletonTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  // TICK_MIDDLE tests
  function test_update_offer_for_TICK_MIDDLE_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIDDLE, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIDDLE_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIDDLE, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIDDLE_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIDDLE, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIDDLE_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIDDLE, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // TICK_MIN_ALLOWED tests
  function test_update_offer_for_TICK_MIN_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIN_ALLOWED, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIN_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIN_ALLOWED, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MIN_ALLOWED, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MIN_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MIN_ALLOWED, singletonTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  // TICK_MAX_ALLOWED tests
  function test_update_offer_for_TICK_MAX_ALLOWED_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MAX_ALLOWED, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MAX_ALLOWED_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MAX_ALLOWED, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(TICK_MAX_ALLOWED, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_TICK_MAX_ALLOWED_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(
      TICK_MAX_ALLOWED, singletonTickListSizeScenarios, singletonTickListSizeScenarios
    );
  }

  function run_update_offer_scenarios_for_tick(
    Tick tick,
    uint[] storage higherTickListSizeScenarios,
    uint[] storage lowerTickListSizeScenarios
  ) internal {
    vm.pauseGasMetering();
    runTickScenarios(tick, higherTickListSizeScenarios, lowerTickListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickScenario(TickScenario memory tickScenario) internal override {
    UpdateOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListScenarios.length; ++j) {
      uint[2] storage tickListScenario = tickListScenarios[j];
      scenario.offerTickListSize = tickListScenario[0];
      scenario.offerPos = tickListScenario[1];

      scenario.newTick = tickScenario.tick;
      run_update_offer_scenario(scenario, false);
      if (tickScenario.hasHigherTick) {
        scenario.newTick = tickScenario.higherTick;
        run_update_offer_scenario(scenario, false);
      }
      if (tickScenario.hasLowerTick) {
        scenario.newTick = tickScenario.lowerTick;
        run_update_offer_scenario(scenario, false);
      }
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_update_offer_scenario() public {
    run_update_offer_scenario(
      UpdateOfferScenario({
        tickScenario: TickScenario({
          tick: Tick.wrap(0),
          hasHigherTick: true,
          higherTick: Tick.wrap(524287),
          higherTickListSize: 1,
          hasLowerTick: true,
          lowerTick: Tick.wrap(-16384),
          lowerTickListSize: 0
        }),
        offerTickListSize: 1,
        offerPos: 0,
        newTick: Tick.wrap(-16384)
      }),
      true
    );
  }

  function run_update_offer_scenario(UpdateOfferScenario memory scenario, bool printToConsole) internal {
    // NB: Enabling all console.log statements will trigger an out-of-memory error when running through all test scenarios.
    // `printToConsole` is used to enable logging for specific scenarios.

    if (printToConsole) {
      console.log("update offer scenario");
      console.log("  oldTick: %s", toString(scenario.tickScenario.tick));
      console.log("  newTick: %s", toString(scenario.newTick));
      console.log("  offerTickListSize: %s", scenario.offerTickListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.tickScenario.hasHigherTick) {
        console.log("  higherTick: %s", toString(scenario.tickScenario.higherTick));
        console.log("  higherTickListSize: %s", vm.toString(scenario.tickScenario.higherTickListSize));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(scenario.tickScenario.lowerTick));
        console.log("  lowerTickListSize: %s", vm.toString(scenario.tickScenario.lowerTickListSize));
      }
    }

    // 1. Capture VM state before scenario so we can restore it after
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory offerIds,) =
      add_n_offers_to_tick(scenario.tickScenario.tick, scenario.offerTickListSize == 0 ? 1 : scenario.offerTickListSize);
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);
    if (scenario.offerTickListSize == 0) {
      mkr.retractOffer(offerIds[0]);
    }
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.tickScenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.tickScenario.lowerTickListSize);
    }

    // 3. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();
    if (printToConsole) {
      console.log("before update");
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tick tree");
      tickTree.logTickTree();
    }

    // 4. Update the offer
    Tick newTick = scenario.newTick;
    uint newGives = getAcceptableGivesForTick(newTick, offerDetail.gasreq());
    mkr.updateOfferByLogPrice(
      LogPriceLib.fromTick(newTick, olKey.tickScale), newGives, offerDetail.gasreq(), offerDetail.gasprice(), offerId
    );
    tickTree.updateOffer(offerId, newTick, newGives, offerDetail.gasreq(), offerDetail.gasprice(), $(mkr));
    if (printToConsole) {
      console.log("");
      console.log("after update");
      // NB: Fails with "field is 0" when MGV tick tree is inconsistent
      console.log("  MGV OB");
      printOfferList(olKey);
      console.log("  tick tree");
      tickTree.logTickTree();
    }

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
