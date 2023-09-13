// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.cleanByImpersonation's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the offer to be cleaned's tick (including the offer itself)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tick tree
// 3. we clean the offer in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - offer fails/doesn't fail
// - cleaning tick
//   - tick is a *tick of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. the offer to be cleaned is alone
//     2. the offer to be cleaned is first of two offers
//     3. the offer to be cleaned is last of two offers
//     4. the offer to be cleaned is middle of three offers
// - higher tick list
//   - tick has higher position in same leaf or level0-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list
//   - tick has lower position in same leaf or level0-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
contract TickTreeCleanOfferTest is TickTreeTest {
  struct CleanOfferScenario {
    TickScenario tickScenario;
    uint offerTickListSize;
    uint offerPos;
    bool offerFail;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_clean_offer_for_TICK_MIN_L3_MAX_OTHERS() public {
    run_clean_offer_scenarios_for_tick(TICK_MIN_L3_MAX_OTHERS);
  }

  function test_clean_offer_for_TICK_MAX_L3_MIN_OTHERS() public {
    run_clean_offer_scenarios_for_tick(TICK_MAX_L3_MIN_OTHERS);
  }

  function test_clean_offer_for_TICK_MIDDLE() public {
    run_clean_offer_scenarios_for_tick(TICK_MIDDLE);
  }

  // size of {lower,higher}TickList if the tick is present in the scenario
  uint[] otherTickListSizeScenarios = [1];

  function run_clean_offer_scenarios_for_tick(Tick tick) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios =
      generateTickScenarios(tick, otherTickListSizeScenarios, otherTickListSizeScenarios);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListScenarios.length; ++j) {
        uint[2] storage tickListScenario = tickListScenarios[j];
        run_clean_offer_scenario(
          CleanOfferScenario({
            tickScenario: tickScenario,
            offerTickListSize: tickListScenario[0],
            offerPos: tickListScenario[1],
            offerFail: true
          }),
          true
        );
        run_clean_offer_scenario(
          CleanOfferScenario({
            tickScenario: tickScenario,
            offerTickListSize: tickListScenario[0],
            offerPos: tickListScenario[1],
            offerFail: false
          }),
          true
        );
      }
    }
    vm.resumeGasMetering();
  }

  // This test is useful for debugging a single scneario
  function test_single_clean_offer_scenario() public {
    run_clean_offer_scenario(
      CleanOfferScenario({
        tickScenario: TickScenario({
          tick: Tick.wrap(0),
          hasHigherTick: false,
          higherTick: Tick.wrap(0),
          higherTickListSize: 0,
          hasLowerTick: false,
          lowerTick: Tick.wrap(0),
          lowerTickListSize: 0
        }),
        offerTickListSize: 1,
        offerPos: 0,
        offerFail: true
      }),
      true
    );
  }

  function run_clean_offer_scenario(CleanOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("clean offer scenario");
      console.log("  cleaningTick: %s", toString(scenario.tickScenario.tick));
      console.log("  offerTickListSize: %s", scenario.offerTickListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      console.log("  offerFail: %s", scenario.offerFail);
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
    (uint[] memory offerIds,) =
      add_n_offers_to_tick(scenario.tickScenario.tick, scenario.offerTickListSize, scenario.offerFail);
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);

    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.tickScenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.tickScenario.lowerTickListSize);
    }

    // 3. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();
    console.log("Before");
    console.log("  test tick tree");
    tickTree.logTickTree();
    console.log("  MGV branch");
    logTickTreeBranch(olKey);

    // 4. Clean the offer
    mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, offer.logPrice(), offerDetail.gasreq(), 1 ether)), $(this)
    );
    if (scenario.offerFail) {
      tickTree.removeOffer(offerId);
    }
    console.log("");
    console.log("After");
    console.log("  test tick tree");
    tickTree.logTickTree();
    console.log("  MGV branch");
    logTickTreeBranch(olKey);

    // 5. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // tickTree.assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
