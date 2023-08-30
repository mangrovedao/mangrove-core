// SPDX-License-Identifier: AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
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
//    - tick is MIN, MAX, min&max&mid {leaf, level0, level1, level2}
//    - list:
//      1. is empty
//      2. has one offer
//      3. has two offers
// - higher tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//      - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tick list (in {leaf, level0, level1, level2})
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2}
//     - if feasible, given insertion tick
//   - list:
//     1. is empty
//     2. non-empty
contract TickTreeNewOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.

  function test_new_offer_for_tick_0() public {
    run_new_offer_scenarios_for_tick(0);
  }

  function test_new_offer_for_tick_1() public {
    run_new_offer_scenarios_for_tick(1);
  }

  function test_new_offer_for_tick_2() public {
    run_new_offer_scenarios_for_tick(2);
  }

  function test_new_offer_for_tick_3() public {
    run_new_offer_scenarios_for_tick(3);
  }

  function test_new_offer_for_tick_negative_1() public {
    run_new_offer_scenarios_for_tick(-1);
  }

  function test_new_offer_for_tick_negative_2() public {
    run_new_offer_scenarios_for_tick(-2);
  }

  function test_new_offer_for_tick_negative_3() public {
    run_new_offer_scenarios_for_tick(-3);
  }

  function test_new_offer_for_tick_negative_4() public {
    run_new_offer_scenarios_for_tick(-4);
  }

  function test_new_offer_for_tick_max() public {
    run_new_offer_scenarios_for_tick(MAX_TICK);
  }

  // FIXME: This currently fails with mgv/writeOffer/wants/tooLow
  // Can we make offers that keep within range? I don't think so, because we set gives to max in this case...
  function testFail_new_offer_for_tick_min() public {
    run_new_offer_scenarios_for_tick(MIN_TICK);
  }

  struct NewOfferScenario {
    TickScenario tickScenario;
    uint insertionTickListSize;
  }

  uint[] tickListSizeScenarios = [0, 1, 2];

  function run_new_offer_scenarios_for_tick(int tick) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios = generateTickScenarios(tick);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
        uint insertionTickListSize = tickListSizeScenarios[j];
        run_new_offer_scenario(
          NewOfferScenario({tickScenario: tickScenario, insertionTickListSize: insertionTickListSize})
        );
      }
    }
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario) internal {
    console.log("new offer scenario");
    console.log("  insertionTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
    console.log("  insertionTickListSize: %s", scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      console.log("  higherTick: %s", toString(Tick.wrap(scenario.tickScenario.higherTick)));
    }
    if (scenario.tickScenario.hasLowerTick) {
      console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
    }
    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();
    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.tick, scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, 1);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, 1);
    }
    // 3. Snapshot tick tree
    TickTree storage tickTree = snapshotTickTree();
    // 4. Create new offer and add it to tick tree
    Tick _insertionTick = Tick.wrap(scenario.tickScenario.tick);
    int logPrice = LogPriceLib.fromTick(_insertionTick, olKey.tickScale);
    uint gives = getAcceptableGivesForTick(_insertionTick, 50_000);
    mgv.newOfferByLogPrice(olKey, logPrice, gives, 50_000, 50);
    addOffer(tickTree, _insertionTick, logPrice, gives, 50_000, 50, $(this));
    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);
    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
