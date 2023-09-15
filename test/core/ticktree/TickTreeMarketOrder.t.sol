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
// 3. we remove the offers the market order should take from the snapshot tick tree
// 4. we run a market order in Mangrove
//   - in the posthook of the last offer, we check that Mangrove's tick tree matches the test tick tree.
//   - by doing this in the posthook, we ensure that the tick tree is updated when the first posthook runs.
//
// The scenarios we want to test are:
// - lower tick list
//   - tick is a *tick of interest* (ToI) as listed in TickTreeTest
//     - if feasible, given middle tick
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - middle tick (in lower tick cases 1. and 2.)
//   - tick has higher position in same leaf or level0-3 as ToI
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - higher tick list (in middle tick cases 1. and 2.)
//   - tick has lower position in same leaf or level0-3 as ToI
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

  function setUp() public override {
    super.setUp();

    mkr.setPosthookCallback($(this), this.checkMgvTickTreeInLastOfferPosthook.selector);
  }

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_market_order_for_TICK_MIN_L3_MAX_OTHERS() public {
    run_market_order_scenarios_for_tick(TICK_MIN_L3_MAX_OTHERS);
  }

  function test_market_order_for_TICK_MAX_L3_MIN_OTHERS() public {
    run_market_order_scenarios_for_tick(TICK_MAX_L3_MIN_OTHERS);
  }

  function test_market_order_for_TICK_MIDDLE() public {
    run_market_order_scenarios_for_tick(TICK_MIDDLE);
  }

  function test_market_order_for_TICK_MIN_ALLOWED() public {
    run_market_order_scenarios_for_tick(TICK_MIN_ALLOWED);
  }

  function test_market_order_for_TICK_MAX_ALLOWED() public {
    run_market_order_scenarios_for_tick(TICK_MAX_ALLOWED);
  }

  function run_market_order_scenarios_for_tick(Tick tick) internal {
    vm.pauseGasMetering();
    bool printToConsole = false;

    Tick[] memory higherTicks = generateHigherTickScenarios(tick);
    Tick[] memory lowerTicks = generateLowerTickScenarios(tick);

    MarketOrderScenario memory scenario = MarketOrderScenario({
      lowerTick: TickListScenario({tick: Tick.wrap(0), size: 0, offersToTake: 0}),
      middleTick: TickListScenario({tick: tick, size: 0, offersToTake: 0}),
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
      scenario.lowerTick.tick = lowerTicks[l];
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
                scenario.higherTick.tick = higherTicks[h];
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
        lowerTick: TickListScenario({tick: Tick.wrap(0), size: 0, offersToTake: 0}),
        middleTick: TickListScenario({tick: Tick.wrap(-1048575), size: 2, offersToTake: 2}),
        higherTick: TickListScenario({tick: Tick.wrap(0), size: 0, offersToTake: 0})
      }),
      true
    );
  }

  function scenarioToString(TickListScenario memory scenario) internal pure returns (string memory) {
    string memory tickListScenario = scenario.size == 0
      ? "empty          "
      : scenario.size == 2 ? "fully taken    " : scenario.offersToTake == 1 ? "partially taken" : "not taken      ";
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

  TestTickTree tickTree;
  uint lastTakenOfferId;
  bool lastTakenOfferPosthookCalled;

  function removeTakenOffers(TickListScenario memory scenario, uint[] memory offerIds) internal {
    for (uint i = 0; i < scenario.offersToTake; ++i) {
      tickTree.removeOffer(offerIds[i]);
    }
  }

  function getLastTakenOfferId(
    MarketOrderScenario memory scenario,
    uint[] memory lowerOfferIds,
    uint[] memory middleOfferIds,
    uint[] memory higherOfferIds
  ) internal pure returns (uint) {
    if (scenario.higherTick.offersToTake > 0) {
      return higherOfferIds[scenario.higherTick.offersToTake - 1];
    } else if (scenario.middleTick.offersToTake > 0) {
      return middleOfferIds[scenario.middleTick.offersToTake - 1];
    } else if (scenario.lowerTick.offersToTake > 0) {
      return lowerOfferIds[scenario.lowerTick.offersToTake - 1];
    }
    return 0;
  }

  function checkMgvTickTreeInLastOfferPosthook(MgvLib.SingleOrder calldata order) external {
    if (order.offerId == lastTakenOfferId) {
      tickTree.assertEqToMgvTickTree();
      lastTakenOfferPosthookCalled = true;
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
      add_n_offers_to_tick(scenario.lowerTick.tick, scenario.lowerTick.size);
    (uint[] memory middleOfferIds, uint middleOffersGive) =
      add_n_offers_to_tick(scenario.middleTick.tick, scenario.middleTick.size);
    (uint[] memory higherOfferIds, uint higherOffersGive) =
      add_n_offers_to_tick(scenario.higherTick.tick, scenario.higherTick.size);
    uint fillVolume = lowerOffersGive * scenario.lowerTick.offersToTake
      + middleOffersGive * scenario.middleTick.offersToTake + higherOffersGive * scenario.higherTick.offersToTake;
    lastTakenOfferId = getLastTakenOfferId(scenario, lowerOfferIds, middleOfferIds, higherOfferIds);

    // 3. Snapshot tick tree
    tickTree = snapshotTickTree();

    // 4. Run the market order and check that the tick tree is updated as expected
    // The check of the tick tree is done in the posthook of the last taken offer
    // by the checkMgvTickTreeInLastOfferPosthook function.
    // We therefore must update the test tick tree before the market order is run.
    removeTakenOffers(scenario.lowerTick, lowerOfferIds);
    removeTakenOffers(scenario.middleTick, middleOfferIds);
    removeTakenOffers(scenario.higherTick, higherOfferIds);
    mgv.marketOrderByLogPrice(olKey, MAX_LOG_PRICE, fillVolume, true);
    assertTrue(lastTakenOfferId == 0 || lastTakenOfferPosthookCalled, "last taken offer posthook not called");

    // assertMgvTickTreeIsConsistent();

    // 5. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}