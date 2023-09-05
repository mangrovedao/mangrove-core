// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.marketOrder's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - a lower tick
//   - a middle tick
//   - a higher tick
// 2. we take a snapshot of Mangrove's tick tree
// 3. we run a market order in Mangrove and remove the corresponding offers in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - lower tick list
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2} as middle tick
//     - if feasible, given middle tick
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - middle tick (in lower tick cases 1. and 2.)
//   - tick is MIN, MAX, min&max&mid {leaf, level0, level1, level2}
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - higher tick list (in middle tick cases 1. and 2.)
//   - tick is MIN, MAX, in same {leaf, level0, level1, level2} as middle tick
//     - if feasible, given middle tick
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
//
// We do not test failing offers or partial fills specifically,
// as they are not handled specially wrt the tick tree.
contract TickTreeMarketOrderTest is TickTreeTest {
  // Tick list               size  offersToTake
  // 1. is empty                0  0
  // 2. is fully taken          2  2
  // 3. is partially taken      3  1
  // 4. is not taken            3  0
  struct TickListScenario {
    Tick tick;
    uint size;
    uint offersToTake;
  }

  struct MarketOrderScenario {
    TickListScenario lowerTick;
    TickListScenario middleTick; // ignored if lowerTickListScenario.size == 3 (scenario 3. and 4.)
    TickListScenario higherTick; // ignored if {lower,middle}TickListScenario.size == 3 (scenario 3. and 4.)
  }

  // (list size, offers to take)
  uint[2][] tickListScenarios = [[0, 0], [2, 2], [3, 1], [3, 0]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.

  // Tick 0 (start leaf, start level0, start level1, mid level 2)
  function test_market_order_for_tick_0() public {
    run_market_order_scenarios_for_tick(0);
  }

  // Tick 1 (mid leaf, start level0, start level1, mid level 2)
  function test_market_order_for_tick_1() public {
    run_market_order_scenarios_for_tick(1);
  }

  // Tick 3 (end leaf, start level0, start level1, mid level 2)
  function test_market_order_for_tick_3() public {
    run_market_order_scenarios_for_tick(3);
  }

  // Tick -1 tests (end leaf, end level0, end level1, mid level 2)
  function test_market_order_for_tick_negative_1() public {
    run_market_order_scenarios_for_tick(-1);
  }

  // Tick -8323 tests (mid leaf, mid level0, mid level1, mid level 2)
  function test_market_order_for_tick_negative_8323() public {
    run_market_order_scenarios_for_tick(-8323);
  }

  // MAX_TICK (end leaf, end level0, end level1, end level 2)
  function test_market_order_for_tick_max() public {
    run_market_order_scenarios_for_tick(MAX_TICK);
  }

  // MIN_TICK tests (start leaf, start level0, start level1, start level 2)
  function test_market_order_for_tick_min() public {
    run_market_order_scenarios_for_tick(MIN_TICK);
  }

  function run_market_order_scenarios_for_tick(int tick) internal {
    vm.pauseGasMetering();
    bool printToConsole = false;

    int[] memory higherTicks = generateHigherTickScenarios(tick);
    int[] memory lowerTicks = generateLowerTickScenarios(tick);
    Tick _tick = Tick.wrap(tick);

    MarketOrderScenario memory scenario = MarketOrderScenario({
      lowerTick: TickListScenario({tick: Tick.wrap(0), size: 0, offersToTake: 0}),
      middleTick: TickListScenario({tick: _tick, size: 0, offersToTake: 0}),
      higherTick: TickListScenario({tick: Tick.wrap(0), size: 0, offersToTake: 0})
    });

    // Lower and higher tick are empty
    {
      for (uint ms = 0; ms < tickListScenarios.length; ++ms) {
        scenario.middleTick.size = tickListScenarios[ms][0];
        scenario.middleTick.offersToTake = tickListScenarios[ms][1];
        run_market_order_scenario(scenario, printToConsole);
      }
    }

    // Lower tick is non-empty
    for (uint l = 0; l < lowerTicks.length; ++l) {
      scenario.lowerTick.tick = Tick.wrap(lowerTicks[l]);
      for (uint ls = 1; ls < tickListScenarios.length; ++ls) {
        scenario.lowerTick.size = tickListScenarios[ls][0];
        scenario.lowerTick.offersToTake = tickListScenarios[ls][1];
        if (scenario.lowerTick.size == 3) {
          // Lower tick is not (fully) taken
          scenario.middleTick.size = 0;
          scenario.middleTick.offersToTake = 0;
          scenario.higherTick.size = 0;
          scenario.higherTick.offersToTake = 0;
          run_market_order_scenario(scenario, printToConsole);
        } else {
          // Lower tick is fully taken
          // Middle tick should be non-empty, otherwise the scenario is equivalent to the one where lower and higher are empty and middle tick is non-empty
          for (uint ms = 1; ms < tickListScenarios.length; ++ms) {
            scenario.middleTick.size = tickListScenarios[ms][0];
            scenario.middleTick.offersToTake = tickListScenarios[ms][1];
            scenario.higherTick.size = 0;
            scenario.higherTick.offersToTake = 0;
            if (scenario.middleTick.size == 3) {
              // Middle tick is not (fully) taken
              run_market_order_scenario(scenario, printToConsole);
            } else {
              // Middle tick is fully taken
              // Hight tick is empty
              run_market_order_scenario(scenario, printToConsole);
              for (uint h = 0; h < higherTicks.length; ++h) {
                scenario.higherTick.tick = Tick.wrap(higherTicks[h]);
                // Higher tick should be non-empty, empty is covered by the previous scenario
                for (uint hs = 1; hs < tickListScenarios.length; ++hs) {
                  scenario.higherTick.size = tickListScenarios[hs][0];
                  scenario.higherTick.offersToTake = tickListScenarios[hs][1];
                  run_market_order_scenario(scenario, printToConsole);
                }
              }
            }
          }
        }
      }
    }

    vm.resumeGasMetering();
  }

  // This test is useful for debugging a single scneario
  function test_single_market_order_scenario() public {
    run_market_order_scenario(
      MarketOrderScenario({
        lowerTick: TickListScenario({tick: Tick.wrap(-1), size: 2, offersToTake: 2}),
        middleTick: TickListScenario({tick: Tick.wrap(0), size: 2, offersToTake: 2}),
        higherTick: TickListScenario({tick: Tick.wrap(1), size: 3, offersToTake: 1})
      }),
      true
    );
  }

  function scenarioToString(TickListScenario memory scenario) internal pure returns (string memory) {
    string memory tickListScenario = scenario.size == 0
      ? "empty          "
      : scenario.size == 1 ? "fully taken    " : scenario.offersToTake == 1 ? "partially taken" : "not taken      ";
    return string.concat(
      tickListScenario,
      ", tick: ",
      toString(scenario.tick),
      ", size: ",
      vm.toString(scenario.size),
      ", offersToTake: ",
      vm.toString(scenario.offersToTake)
    );
  }

  function removeTakenOffers(TickTree storage tickTree, TickListScenario memory scenario, uint[] memory offerIds)
    internal
  {
    for (uint i = 0; i < scenario.offersToTake; ++i) {
      removeOffer(tickTree, offerIds[i]);
    }
  }

  function run_market_order_scenario(MarketOrderScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("market order scenario");
      console.log("  lower tick scenario:  ", scenarioToString(scenario.lowerTick));
      console.log("  middle tick scenario: ", scenarioToString(scenario.middleTick));
      console.log("  higher tick scenario: ", scenarioToString(scenario.higherTick));
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory lowerOfferIds, uint lowerOffersGive) =
      add_n_offers_to_tick(Tick.unwrap(scenario.lowerTick.tick), scenario.lowerTick.size);
    (uint[] memory middleOfferIds, uint middleOffersGive) =
      add_n_offers_to_tick(Tick.unwrap(scenario.middleTick.tick), scenario.middleTick.size);
    (uint[] memory higherOfferIds, uint higherOffersGive) =
      add_n_offers_to_tick(Tick.unwrap(scenario.higherTick.tick), scenario.higherTick.size);
    uint fillVolume = lowerOffersGive * scenario.lowerTick.offersToTake
      + middleOffersGive * scenario.middleTick.offersToTake + higherOffersGive * scenario.higherTick.offersToTake;

    // 3. Snapshot tick tree
    TickTree storage tickTree = snapshotTickTree();

    // 4. Run the market order
    mgv.marketOrderByLogPrice(olKey, MAX_LOG_PRICE, fillVolume, true);
    removeTakenOffers(tickTree, scenario.lowerTick, lowerOfferIds);
    removeTakenOffers(tickTree, scenario.middleTick, middleOfferIds);
    removeTakenOffers(tickTree, scenario.higherTick, higherOfferIds);

    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
