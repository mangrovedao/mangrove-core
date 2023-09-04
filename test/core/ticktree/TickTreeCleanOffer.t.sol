// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
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
//   - tick is MIN, MAX, min&max&mid {leaf, level0, level1, level2}
//   - list:
//     1. the offer to be cleaned is alone
//     2. the offer to be cleaned is first of two offers
//     3. the offer to be cleaned is last of two offers
//     4. the offer to be cleaned is middle of three offers
// - higher tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
contract TickTreeCleanOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  struct CleanOfferScenario {
    TickScenario tickScenario;
    uint offerTickListSize;
    uint offerPos;
    bool offerFail;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.

  // Tick 0 tests (start leaf, start level0, start level1, mid level 2)
  function test_clean_offer_for_tick_0() public {
    run_clean_offer_scenarios_for_tick(0);
  }

  // Tick 1 tests (mid leaf, start level0, start level1, mid level 2)
  function test_clean_offer_for_tick_1() public {
    run_clean_offer_scenarios_for_tick(1);
  }

  // Tick 3 tests (end leaf, start level0, start level1, mid level 2)
  function test_clean_offer_for_tick_3() public {
    run_clean_offer_scenarios_for_tick(3);
  }

  // Tick -1 tests (end leaf, end level0, end level1, mid level 2)
  function test_clean_offer_for_tick_negative_1() public {
    run_clean_offer_scenarios_for_tick(-1);
  }

  // Tick -8323 tests (mid leaf, mid level0, mid level1, mid level 2)
  function test_clean_offer_for_tick_negative_8323() public {
    run_clean_offer_scenarios_for_tick(-8323);
  }

  // MAX_TICK tests (end leaf, end level0, end level1, end level 2)
  function test_clean_offer_for_tick_max() public {
    run_clean_offer_scenarios_for_tick(MAX_TICK);
  }

  // MIN_TICK tests (start leaf, start level0, start level1, start level 2)
  function test_clean_offer_for_tick_min() public {
    run_clean_offer_scenarios_for_tick(MIN_TICK);
  }

  // size of {lower,higher}TickList if the tick is present in the scenario
  uint[] otherTickListSizeScenarios = [1];

  function run_clean_offer_scenarios_for_tick(int tick) internal {
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
          false
        );
        run_clean_offer_scenario(
          CleanOfferScenario({
            tickScenario: tickScenario,
            offerTickListSize: tickListScenario[0],
            offerPos: tickListScenario[1],
            offerFail: false
          }),
          false
        );
      }
    }
    vm.resumeGasMetering();
  }

  // function test_single_scenario() public {
  //   run_clean_offer_scenario(
  //     CleanOfferScenario({tickScenario: TickScenario({tick: 0, hasHigherTick: true, higherTick: 4, hasLowerTick: false, lowerTick: 0}), offerTickListSize: 1, offerPos: 0}),
  //     true
  //   );
  // }

  function run_clean_offer_scenario(CleanOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("clean offer scenario");
      console.log("  cleaningTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
      console.log("  offerTickListSize: %s", scenario.offerTickListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      if (scenario.tickScenario.hasHigherTick) {
        Tick higherTick = Tick.wrap(scenario.tickScenario.higherTick);
        console.log("  higherTick: %s", toString(higherTick));
      }
      if (scenario.tickScenario.hasLowerTick) {
        console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
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
    TickTree storage tickTree = snapshotTickTree();

    // 4. Clean the offer
    mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, offer.logPrice(), offerDetail.gasreq(), 1 ether)), $(this)
    );
    if (scenario.offerFail) {
      removeOffer(tickTree, offerId);
    }

    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
