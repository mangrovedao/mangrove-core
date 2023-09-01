// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
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
//   - tick is MIN, MAX, min&max&mid {leaf, level0, level1, level2}
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
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given retraction tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given retraction tick
//   - list:
//     1. is empty
//     2. is non-empty
// - new offer tick
//   1. same tick
//   2. the lower tick
//   3. the higher tick
contract TickTreeUpdateOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  struct UpdateOfferScenario {
    TickScenario tickScenario;
    int newTick;
    uint offerTickListSize; // 0 -> offer is not live
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[0, 0], [1, 0], [2, 0], [2, 1], [3, 1]];
  // size of {lower,higher}TickList
  uint[] otherTickListSizeScenarios = [0, 1];
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
  // We therefore restrict the ticks we test to select values, eg MIN, MAX, min&max&mid {leaf, level0, level1, level2}

  // Tick 0 tests (start leaf, start level0, start level1, mid level 2)
  function test_update_offer_for_tick_0_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(0, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_0_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(0, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // FIXME: This currently fails due to a bug in Mangrove, see specific test case further down
  // function testFail_update_offer_for_tick_0_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(0, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  function test_update_offer_for_tick_0_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(0, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // Tick 1 tests (mid leaf, start level0, start level1, mid level 2)
  function test_update_offer_for_tick_1_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(1, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_1_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(1, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // FIXME: This currently fails due to a bug in Mangrove, see specific test case further down
  // function testFail_update_offer_for_tick_1_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(1, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  function test_update_offer_for_tick_1_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(1, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // Tick 3 tests (end leaf, start level0, start level1, mid level 2)
  function test_update_offer_for_tick_3_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(3, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_3_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(3, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // FIXME: This currently fails due to a bug in Mangrove, see specific test case further down
  // function testFail_update_offer_for_tick_3_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(3, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  function test_update_offer_for_tick_3_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(3, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // Tick -1 tests (end leaf, end level0, end level1, mid level 2)
  function test_update_offer_for_tick_negative_1_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(-1, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_negative_1_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(-1, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // FIXME: This currently fails due to a bug in Mangrove, see specific test case further down
  // function testFail_update_offer_for_tick_negative_1_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(-1, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  function test_update_offer_for_tick_negative_1_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(-1, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // MAX_TICK tests (end leaf, end level0, end level1, end level 2)
  function test_update_offer_for_tick_MAX_TICK_where_higher_is_empty_and_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(MAX_TICK, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_MAX_TICK_where_higher_is_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(MAX_TICK, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // FIXME: This currently fails due to a bug in Mangrove, see specific test case further down
  // function testFail_update_offer_for_tick_MAX_TICK_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(MAX_TICK, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  function test_update_offer_for_tick_MAX_TICK_where_higher_is_not_empty_and_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(MAX_TICK, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // MIN_TICK tests (start leaf, start level0, start level1, start level 2)
  // FIXME: The tests currently fails for MIN_TICK with mgv/writeOffer/wants/tooLow due to limitations Mangrove
  // function test_update_offer_for_tick_MIN_TICK_where_higher_is_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(MIN_TICK, emptyTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  // function test_update_offer_for_tick_MIN_TICK_where_higher_is_empty_and_lower_is_not_empty() public {
  //   run_update_offer_scenarios_for_tick(MIN_TICK, emptyTickListSizeScenarios, singletonTickListSizeScenarios);
  // }

  // function testFail_update_offer_for_tick_MIN_TICK_where_higher_is_not_empty_and_lower_is_empty() public {
  //   run_update_offer_scenarios_for_tick(MIN_TICK, singletonTickListSizeScenarios, emptyTickListSizeScenarios);
  // }

  // function test_update_offer_for_tick_MIN_TICK_where_higher_is_not_empty_and_lower_is_not_empty() public {
  //   run_update_offer_scenarios_for_tick(MIN_TICK, singletonTickListSizeScenarios, singletonTickListSizeScenarios);
  // }

  function run_update_offer_scenarios_for_tick(
    int tick,
    uint[] storage higherTickListSizeScenarios,
    uint[] storage lowerTickListSizeScenarios
  ) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios =
      generateTickScenarios(tick, higherTickListSizeScenarios, lowerTickListSizeScenarios);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListScenarios.length; ++j) {
        uint[2] storage tickListScenario = tickListScenarios[j];
        run_update_offer_scenario(
          UpdateOfferScenario({
            tickScenario: tickScenario,
            newTick: tickScenario.tick,
            offerTickListSize: tickListScenario[0],
            offerPos: tickListScenario[1]
          }),
          false
        );
        if (tickScenario.hasHigherTick) {
          run_update_offer_scenario(
            UpdateOfferScenario({
              tickScenario: tickScenario,
              newTick: tickScenario.higherTick,
              offerTickListSize: tickListScenario[0],
              offerPos: tickListScenario[1]
            }),
            false
          );
        }
        if (tickScenario.hasLowerTick) {
          run_update_offer_scenario(
            UpdateOfferScenario({
              tickScenario: tickScenario,
              newTick: tickScenario.lowerTick,
              offerTickListSize: tickListScenario[0],
              offerPos: tickListScenario[1]
            }),
            false
          );
        }
      }
    }
    vm.resumeGasMetering();
  }

  // FIXME: This scenario triggers bug in Mangrove
  // function test_single_update_offer_scenario() public {
  //   run_update_offer_scenario(
  //     UpdateOfferScenario({
  //       tickScenario: TickScenario({
  //         tick: 0,
  //         hasHigherTick: true,
  //         higherTick: 524287,
  //         higherTickListSize: 1,
  //         hasLowerTick: true,
  //         lowerTick: -16384,
  //         lowerTickListSize: 0
  //       }),
  //       offerTickListSize: 1,
  //       offerPos: 0,
  //       newTick: -16384
  //     }),
  //     true
  //   );
  // }

  function run_update_offer_scenario(UpdateOfferScenario memory scenario, bool printToConsole) internal {
    // NB: Enabling all console.log statements will trigger an out-of-memory error when running through all test scenarios.
    // `printToConsole` is used to enable logging for specific scenarios.

    if (printToConsole) {
      console.log("update offer scenario");
      console.log("  oldTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
      console.log("  newTick: %s", toString(Tick.wrap(scenario.newTick)));
      console.log("  offerTickListSize: %s", scenario.offerTickListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.tickScenario.hasHigherTick) {
        Tick higherTick = Tick.wrap(scenario.tickScenario.higherTick);
        console.log("  higherTick: %s", toString(higherTick));
        console.log("  higherTickListSize: %s", vm.toString(scenario.tickScenario.higherTickListSize));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
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
    TickTree storage tickTree = snapshotTickTree();
    if (printToConsole) {
      console.log("before update");
      console.log("  MGV OB");
      printOrderBook(olKey);
      console.log("  tick tree");
      logTickTree(tickTree);
    }

    // 4. Update the offer
    Tick newTick = Tick.wrap(scenario.newTick);
    uint newGives = getAcceptableGivesForTick(newTick, offerDetail.gasreq());
    mkr.updateOfferByLogPrice(
      LogPriceLib.fromTick(newTick, olKey.tickScale), newGives, offerDetail.gasreq(), offerDetail.gasprice(), offerId
    );
    updateOffer(tickTree, offerId, newTick, newGives, offerDetail.gasreq(), offerDetail.gasprice(), $(mkr));
    assertMgvTickTreeIsConsistent();
    if (printToConsole) {
      console.log("");
      console.log("after update");
      // FIXME: Fails with "field is 0" when MGV tick tree is inconsistent
      console.log("  MGV OB");
      printOrderBook(olKey);
      console.log("  tick tree");
      logTickTree(tickTree);
    }

    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
