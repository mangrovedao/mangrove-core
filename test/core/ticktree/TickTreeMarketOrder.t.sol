// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.marketOrder's interaction with the tickTreeIndex tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tickTreeIndex tree where there may be offers at:
//   - a lower tick
//   - a middle tick
//   - a higher tick
// 2. we take a snapshot of Mangrove's tickTreeIndex tree
// 3. we remove the offers the market order should take from the snapshot tickTreeIndex tree
// 4. we run a market order in Mangrove
//   - in the posthook of the last offer, we check that Mangrove's tickTreeIndex tree matches the test tickTreeIndex tree.
//   - by doing this in the posthook, we ensure that the tickTreeIndex tree is updated when the first posthook runs.
//
// The scenarios we want to test are:
// - lower tickTreeIndex list
//   - tickTreeIndex is a *tickTreeIndex of interest* (ToI) as listed in TickTreeTest
//     - if feasible, given middle tick
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - middle tickTreeIndex (in lower tickTreeIndex cases 1. and 2.)
//   - tickTreeIndex has higher position in same leaf or level0-3 as ToI
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - higher tickTreeIndex list (in middle tickTreeIndex cases 1. and 2.)
//   - tickTreeIndex has lower position in same leaf or level0-3 as ToI
//     - if feasible, given middle tick
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
//
// We do not test failing offers or partial fills specifically,
// as they are not handled specially wrt the tickTreeIndex tree.
contract TickTreeMarketOrderTest is TickTreeTest {
  // TickTreeIndex list               size  offersToTake
  // 1. is empty                0  0
  // 2. is fully taken          2  2
  // 3. is partially taken      3  1
  // 4. is not taken            3  0
  struct TickTreeIndexListScenario {
    TickTreeIndex tickTreeIndex;
    uint size;
    uint offersToTake;
  }

  struct MarketOrderScenario {
    TickTreeIndexListScenario lowerTickTreeIndex;
    TickTreeIndexListScenario middleTickTreeIndex; // ignored if lowerTickTreeIndexListScenario.size == 3 (scenario 3. and 4.)
    TickTreeIndexListScenario higherTickTreeIndex; // ignored if {lower,middle}TickTreeIndexListScenario.size == 3 (scenario 3. and 4.)
  }

  // (list size, offers to take)
  uint[2][] tickListScenarios = [[0, 0], [2, 2], [3, 1], [3, 0]];

  function setUp() public override {
    super.setUp();

    mkr.setPosthookCallback($(this), this.checkMgvTickTreeInLastOfferPosthook.selector);
  }

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_market_order_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS() public {
    run_market_order_scenarios_for_tick(TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS);
  }

  function test_market_order_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS() public {
    run_market_order_scenarios_for_tick(TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS);
  }

  function test_market_order_for_TICK_TREE_INDEX_MIDDLE() public {
    run_market_order_scenarios_for_tick(TICK_TREE_INDEX_MIDDLE);
  }

  function test_market_order_for_TICK_TREE_INDEX_MIN_ALLOWED() public {
    run_market_order_scenarios_for_tick(TICK_TREE_INDEX_MIN_ALLOWED);
  }

  function test_market_order_for_TICK_TREE_INDEX_MAX_ALLOWED() public {
    run_market_order_scenarios_for_tick(TICK_TREE_INDEX_MAX_ALLOWED);
  }

  function run_market_order_scenarios_for_tick(TickTreeIndex tickTreeIndex) internal {
    vm.pauseGasMetering();
    bool printToConsole = false;

    TickTreeIndex[] memory higherTickTreeIndexs = generateHigherTickTreeIndexScenarios(tickTreeIndex);
    TickTreeIndex[] memory lowerTickTreeIndexs = generateLowerTickTreeIndexScenarios(tickTreeIndex);

    MarketOrderScenario memory scenario = MarketOrderScenario({
      lowerTickTreeIndex: TickTreeIndexListScenario({tickTreeIndex: TickTreeIndex.wrap(0), size: 0, offersToTake: 0}),
      middleTickTreeIndex: TickTreeIndexListScenario({tickTreeIndex: tickTreeIndex, size: 0, offersToTake: 0}),
      higherTickTreeIndex: TickTreeIndexListScenario({tickTreeIndex: TickTreeIndex.wrap(0), size: 0, offersToTake: 0})
    });

    // Lower and higher tickTreeIndex are empty
    {
      for (uint ms = 0; ms < tickListScenarios.length; ++ms) {
        scenario.middleTickTreeIndex.size = tickListScenarios[ms][0];
        scenario.middleTickTreeIndex.offersToTake = tickListScenarios[ms][1];
        run_market_order_scenario(scenario, printToConsole);
      }
    }

    // Lower tickTreeIndex is non-empty
    for (uint l = 0; l < lowerTickTreeIndexs.length; ++l) {
      scenario.lowerTickTreeIndex.tickTreeIndex = lowerTickTreeIndexs[l];
      for (uint ls = 1; ls < tickListScenarios.length; ++ls) {
        scenario.lowerTickTreeIndex.size = tickListScenarios[ls][0];
        scenario.lowerTickTreeIndex.offersToTake = tickListScenarios[ls][1];
        if (scenario.lowerTickTreeIndex.size == 3) {
          // Lower tickTreeIndex is not (fully) taken
          scenario.middleTickTreeIndex.size = 0;
          scenario.middleTickTreeIndex.offersToTake = 0;
          scenario.higherTickTreeIndex.size = 0;
          scenario.higherTickTreeIndex.offersToTake = 0;
          run_market_order_scenario(scenario, printToConsole);
        } else {
          // Lower tickTreeIndex is fully taken
          // Middle tickTreeIndex should be non-empty, otherwise the scenario is equivalent to the one where lower and higher are empty and middle tickTreeIndex is non-empty
          for (uint ms = 1; ms < tickListScenarios.length; ++ms) {
            scenario.middleTickTreeIndex.size = tickListScenarios[ms][0];
            scenario.middleTickTreeIndex.offersToTake = tickListScenarios[ms][1];
            scenario.higherTickTreeIndex.size = 0;
            scenario.higherTickTreeIndex.offersToTake = 0;
            if (scenario.middleTickTreeIndex.size == 3) {
              // Middle tickTreeIndex is not (fully) taken
              run_market_order_scenario(scenario, printToConsole);
            } else {
              // Middle tickTreeIndex is fully taken
              // Hight tickTreeIndex is empty
              run_market_order_scenario(scenario, printToConsole);
              for (uint h = 0; h < higherTickTreeIndexs.length; ++h) {
                scenario.higherTickTreeIndex.tickTreeIndex = higherTickTreeIndexs[h];
                // Higher tickTreeIndex should be non-empty, empty is covered by the previous scenario
                for (uint hs = 1; hs < tickListScenarios.length; ++hs) {
                  scenario.higherTickTreeIndex.size = tickListScenarios[hs][0];
                  scenario.higherTickTreeIndex.offersToTake = tickListScenarios[hs][1];
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
        lowerTickTreeIndex: TickTreeIndexListScenario({tickTreeIndex: TickTreeIndex.wrap(0), size: 0, offersToTake: 0}),
        middleTickTreeIndex: TickTreeIndexListScenario({
          tickTreeIndex: TickTreeIndex.wrap(-1048575),
          size: 2,
          offersToTake: 2
        }),
        higherTickTreeIndex: TickTreeIndexListScenario({tickTreeIndex: TickTreeIndex.wrap(0), size: 0, offersToTake: 0})
      }),
      true
    );
  }

  function scenarioToString(TickTreeIndexListScenario memory scenario) internal pure returns (string memory) {
    string memory tickListScenario = scenario.size == 0
      ? "empty          "
      : scenario.size == 2 ? "fully taken    " : scenario.offersToTake == 1 ? "partially taken" : "not taken      ";
    return string.concat(
      tickListScenario,
      ", tickTreeIndex: ",
      toString(scenario.tickTreeIndex),
      ", size: ",
      vm.toString(scenario.size),
      ", offersToTake: ",
      vm.toString(scenario.offersToTake)
    );
  }

  TestTickTree tickTree;
  uint lastTakenOfferId;
  bool lastTakenOfferPosthookCalled;

  function removeTakenOffers(TickTreeIndexListScenario memory scenario, uint[] memory offerIds) internal {
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
    if (scenario.higherTickTreeIndex.offersToTake > 0) {
      return higherOfferIds[scenario.higherTickTreeIndex.offersToTake - 1];
    } else if (scenario.middleTickTreeIndex.offersToTake > 0) {
      return middleOfferIds[scenario.middleTickTreeIndex.offersToTake - 1];
    } else if (scenario.lowerTickTreeIndex.offersToTake > 0) {
      return lowerOfferIds[scenario.lowerTickTreeIndex.offersToTake - 1];
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
      console.log("  lower tickTreeIndex scenario:  ", scenarioToString(scenario.lowerTickTreeIndex));
      console.log("  middle tickTreeIndex scenario: ", scenarioToString(scenario.middleTickTreeIndex));
      console.log("  higher tickTreeIndex scenario: ", scenarioToString(scenario.higherTickTreeIndex));
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory lowerOfferIds, uint lowerOffersGive) =
      add_n_offers_to_tick(scenario.lowerTickTreeIndex.tickTreeIndex, scenario.lowerTickTreeIndex.size);
    (uint[] memory middleOfferIds, uint middleOffersGive) =
      add_n_offers_to_tick(scenario.middleTickTreeIndex.tickTreeIndex, scenario.middleTickTreeIndex.size);
    (uint[] memory higherOfferIds, uint higherOffersGive) =
      add_n_offers_to_tick(scenario.higherTickTreeIndex.tickTreeIndex, scenario.higherTickTreeIndex.size);
    uint fillVolume = lowerOffersGive * scenario.lowerTickTreeIndex.offersToTake
      + middleOffersGive * scenario.middleTickTreeIndex.offersToTake
      + higherOffersGive * scenario.higherTickTreeIndex.offersToTake;
    lastTakenOfferId = getLastTakenOfferId(scenario, lowerOfferIds, middleOfferIds, higherOfferIds);

    // 3. Snapshot tickTreeIndex tree
    tickTree = snapshotTickTree();

    // 4. Run the market order and check that the tickTreeIndex tree is updated as expected
    // The check of the tickTreeIndex tree is done in the posthook of the last taken offer
    // by the checkMgvTickTreeInLastOfferPosthook function.
    // We therefore must update the test tickTreeIndex tree before the market order is run.
    removeTakenOffers(scenario.lowerTickTreeIndex, lowerOfferIds);
    removeTakenOffers(scenario.middleTickTreeIndex, middleOfferIds);
    removeTakenOffers(scenario.higherTickTreeIndex, higherOfferIds);
    mgv.marketOrderByLogPrice(olKey, MAX_LOG_PRICE, fillVolume, true);
    assertTrue(lastTakenOfferId == 0 || lastTakenOfferPosthookCalled, "last taken offer posthook not called");

    // assertMgvTickTreeIsConsistent();

    // 5. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
