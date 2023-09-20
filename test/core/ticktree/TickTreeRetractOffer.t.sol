// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.retractOffer's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the offer to be retracted's tick (including the offer itself)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tick tree
// 3. we retract the offer in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - retraction tick
//   - tick is a *tick of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. the offer to be retracted is alone
//     2. the offer to be retracted is first of two offers
//     3. the offer to be retracted is last of two offers
//     4. the offer to be retracted is middle of three offers
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
contract TickTreeRetractOfferTest is TickTreeTest {
  struct RetractOfferScenario {
    TickScenario tickScenario;
    uint offerTickListSize;
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_retract_offer_for_TICK_MIN_ROOT_MAX_OTHERS() public {
    run_retract_offer_scenarios_for_tick(TICK_MIN_ROOT_MAX_OTHERS);
  }

  function test_retract_offer_for_TICK_MAX_ROOT_MIN_OTHERS() public {
    run_retract_offer_scenarios_for_tick(TICK_MAX_ROOT_MIN_OTHERS);
  }

  function test_retract_offer_for_TICK_MIDDLE() public {
    run_retract_offer_scenarios_for_tick(TICK_MIDDLE);
  }

  function test_retract_offer_for_TICK_MIN_ALLOWED() public {
    run_retract_offer_scenarios_for_tick(TICK_MIN_ALLOWED);
  }

  function test_retract_offer_for_TICK_MAX_ALLOWED() public {
    run_retract_offer_scenarios_for_tick(TICK_MAX_ALLOWED);
  }

  // size of {lower,higher}TickList if the tick is present in the scenario
  uint[] otherTickListSizeScenarios = [1];

  function run_retract_offer_scenarios_for_tick(Tick tick) internal {
    vm.pauseGasMetering();
    runTickScenarios(tick, otherTickListSizeScenarios, otherTickListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickScenario(TickScenario memory tickScenario) internal override {
    RetractOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListScenarios.length; ++j) {
      uint[2] storage tickListScenario = tickListScenarios[j];
      scenario.offerTickListSize = tickListScenario[0];
      scenario.offerPos = tickListScenario[1];
      run_retract_offer_scenario(scenario, false);
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_retract_offer_scenario() public {
    run_retract_offer_scenario(
      RetractOfferScenario({
        tickScenario: TickScenario({
          tick: Tick.wrap(0),
          hasHigherTick: true,
          higherTick: Tick.wrap(4),
          higherTickListSize: 1,
          hasLowerTick: false,
          lowerTick: Tick.wrap(0),
          lowerTickListSize: 0
        }),
        offerTickListSize: 1,
        offerPos: 0
      }),
      true
    );
  }

  function run_retract_offer_scenario(RetractOfferScenario memory scenario, bool printToConsole) internal {
    Tick tick = scenario.tickScenario.tick;
    if (printToConsole) {
      console.log("retract offer scenario");
      console.log("  retractionTick: %s", toString(tick));
      console.log("  offerTickListSize: %s", scenario.offerTickListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.tickScenario.hasHigherTick) {
        Tick higherTick = scenario.tickScenario.higherTick;
        console.log("  higherTick: %s", toString(higherTick));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(scenario.tickScenario.lowerTick));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory offerIds,) = add_n_offers_to_tick(scenario.tickScenario.tick, scenario.offerTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.tickScenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.tickScenario.lowerTickListSize);
    }

    // 3. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Retract the offer
    uint offerId = offerIds[scenario.offerPos];
    mkr.retractOffer(offerId);
    tickTree.removeOffer(offerId);

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
