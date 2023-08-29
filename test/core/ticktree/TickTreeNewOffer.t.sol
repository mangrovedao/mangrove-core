// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
import {
  IERC20,
  MgvLib,
  HasMgvEvents,
  IMaker,
  ITaker,
  IMgvMonitor,
  MgvStructs,
  Leaf,
  Field,
  Tick,
  LeafLib,
  LogPriceLib,
  FieldLib,
  TickLib,
  MIN_TICK,
  MAX_TICK,
  LEAF_SIZE_BITS,
  LEVEL0_SIZE_BITS,
  LEVEL1_SIZE_BITS,
  LEAF_SIZE,
  LEVEL0_SIZE,
  LEVEL1_SIZE,
  LEVEL2_SIZE,
  NUM_LEVEL1,
  NUM_LEVEL0,
  NUM_LEAFS,
  NUM_TICKS,
  MIN_LEAF_INDEX,
  MAX_LEAF_INDEX,
  MIN_LEVEL0_INDEX,
  MAX_LEVEL0_INDEX,
  MIN_LEVEL1_INDEX,
  MAX_LEVEL1_INDEX,
  MAX_LEAF_POSITION,
  MAX_LEVEL0_POSITION,
  MAX_LEVEL1_POSITION,
  MAX_LEVEL2_POSITION
} from "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.newOffer's interaction with the tick tree.
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

  // Can we make offers that keep within range?
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
    uint higherTickListSize;
    uint lowerTickListSize;
  }

  function run_new_offer_scenarios_for_tick(int tick) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios = generateTickScenarios(tick);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListSizeScenarios.length; ++j) {
        uint insertionTickListSize = tickListSizeScenarios[j];
        if (!tickScenario.hasHigherTick) {
          if (!tickScenario.hasLowerTick) {
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: 0,
                lowerTickListSize: 0
              })
            );
          } else {
            for (uint l = 1; l < tickListSizeScenarios.length; ++l) {
              uint lowerTickListSize = tickListSizeScenarios[l];
              run_new_offer_scenario(
                NewOfferScenario({
                  tickScenario: tickScenario,
                  insertionTickListSize: insertionTickListSize,
                  higherTickListSize: 0,
                  lowerTickListSize: lowerTickListSize
                })
              );
            }
          }
        } else if (!tickScenario.hasLowerTick) {
          for (uint h = 1; h < tickListSizeScenarios.length; ++h) {
            uint higherTickListSize = tickListSizeScenarios[h];
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: higherTickListSize,
                lowerTickListSize: 0
              })
            );
          }
        }
        // For higher and lower tick, we skip the empty tick list scenario as it's equivalent to has{Higher, Lower}Tick = false
        for (uint k = 1; k < tickListSizeScenarios.length; ++k) {
          uint higherTickListSize = tickListSizeScenarios[k];
          for (uint l = 1; l < tickListSizeScenarios.length; ++l) {
            uint lowerTickListSize = tickListSizeScenarios[l];
            run_new_offer_scenario(
              NewOfferScenario({
                tickScenario: tickScenario,
                insertionTickListSize: insertionTickListSize,
                higherTickListSize: higherTickListSize,
                lowerTickListSize: lowerTickListSize
              })
            );
          }
        }
      }
    }
  }

  function run_new_offer_scenario(NewOfferScenario memory scenario) internal {
    console.log("new offer scenario");
    console.log("  insertionTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
    console.log("  insertionTickListSize: %s", scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      console.log("  higherTick: %s", toString(Tick.wrap(scenario.tickScenario.higherTick)));
      console.log("  higherTickListSize: %s", scenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
      console.log("  lowerTickListSize: %s", scenario.lowerTickListSize);
    }
    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();
    // 2. Create scenario
    add_n_offers_to_tick(scenario.tickScenario.tick, scenario.insertionTickListSize);
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.lowerTickListSize);
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
