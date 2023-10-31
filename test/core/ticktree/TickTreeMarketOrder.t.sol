// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import "./TickTreeTest.t.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

// Tests of Mangrove.marketOrder's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - a lower bin
//   - a middle bin
//   - a higher bin
// 2. we take a snapshot of Mangrove's tick tree
// 3. we remove the offers the market order should take from the snapshot tick tree
// 4. we run a market order in Mangrove
//   - in the posthook of the last offer, we check that Mangrove's tick tree matches the test tick tree.
//   - by doing this in the posthook, we ensure that the tick tree is updated when the first posthook runs.
//
// The scenarios we want to test are:
// - lower bin list
//   - bin is a *bin of interest* (BoI) as listed in TickTreeTest
//     - if feasible, given middle bin
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - middle bin (in lower bin cases 1. and 2.)
//   - bin has higher position in same leaf or level1-3 as BoI
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
// - higher bin list (in middle bin cases 1. and 2.)
//   - bin has lower position in same leaf or level1-3 as BoI
//     - if feasible, given middle bin
//   - list:
//     1. is empty
//     2. is fully taken
//     3. is partially taken
//     4. is not taken
//
// We do not test failing offers or partial fills specifically,
// as they are not handled specially wrt the tick tree.
contract TickTreeMarketOrderTest is TickTreeTest {
  // Bin list                size  offersToTake
  // 1. is empty                0  0
  // 2. is fully taken          2  2
  // 3. is partially taken      3  1
  // 4. is not taken            3  0
  struct BinListScenario {
    Bin bin;
    uint size;
    uint offersToTake;
  }

  struct MarketOrderScenario {
    BinListScenario lowerBin;
    BinListScenario middleBin; // ignored if lowerBinListScenario.size == 3 (scenario 3. and 4.)
    BinListScenario higherBin; // ignored if {lower,middle}BinListScenario.size == 3 (scenario 3. and 4.)
  }

  // (list size, offers to take)
  uint[2][] binListScenarios = [[0, 0], [2, 2], [3, 1], [3, 0]];

  function setUp() public override {
    super.setUp();

    mkr.setPosthookCallback($(this), this.checkMgvTickTreeInLastOfferPosthook.selector);
  }

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_market_order_for_BIN_MIN_ROOT_MAX_OTHERS() public {
    run_market_order_scenarios_for_bin(BIN_MIN_ROOT_MAX_OTHERS);
  }

  function test_market_order_for_BIN_MAX_ROOT_MIN_OTHERS() public {
    run_market_order_scenarios_for_bin(BIN_MAX_ROOT_MIN_OTHERS);
  }

  function test_market_order_for_BIN_MIDDLE() public {
    run_market_order_scenarios_for_bin(BIN_MIDDLE);
  }

  function test_market_order_for_BIN_MIN_ALLOWED() public {
    run_market_order_scenarios_for_bin(BIN_MIN_ALLOWED);
  }

  function test_market_order_for_BIN_MAX_ALLOWED() public {
    run_market_order_scenarios_for_bin(BIN_MAX_ALLOWED);
  }

  function run_market_order_scenarios_for_bin(Bin bin) internal {
    bool printToConsole = false;

    Bin[] memory higherBins = generateHigherBinScenarios(bin);
    Bin[] memory lowerBins = generateLowerBinScenarios(bin);

    MarketOrderScenario memory scenario = MarketOrderScenario({
      lowerBin: BinListScenario({bin: Bin.wrap(0), size: 0, offersToTake: 0}),
      middleBin: BinListScenario({bin: bin, size: 0, offersToTake: 0}),
      higherBin: BinListScenario({bin: Bin.wrap(0), size: 0, offersToTake: 0})
    });

    // Lower and higher bin are empty
    {
      for (uint ms = 0; ms < binListScenarios.length; ++ms) {
        scenario.middleBin.size = binListScenarios[ms][0];
        scenario.middleBin.offersToTake = binListScenarios[ms][1];
        run_market_order_scenario(scenario, printToConsole);
      }
    }

    // Lower bin is non-empty
    for (uint l = 0; l < lowerBins.length; ++l) {
      scenario.lowerBin.bin = lowerBins[l];
      for (uint ls = 1; ls < binListScenarios.length; ++ls) {
        scenario.lowerBin.size = binListScenarios[ls][0];
        scenario.lowerBin.offersToTake = binListScenarios[ls][1];
        if (scenario.lowerBin.size == 3) {
          // Lower bin is not (fully) taken
          scenario.middleBin.size = 0;
          scenario.middleBin.offersToTake = 0;
          scenario.higherBin.size = 0;
          scenario.higherBin.offersToTake = 0;
          run_market_order_scenario(scenario, printToConsole);
        } else {
          // Lower bin is fully taken
          // Middle bin should be non-empty, otherwise the scenario is equivalent to the one where lower and higher are empty and middle bin is non-empty
          for (uint ms = 1; ms < binListScenarios.length; ++ms) {
            scenario.middleBin.size = binListScenarios[ms][0];
            scenario.middleBin.offersToTake = binListScenarios[ms][1];
            scenario.higherBin.size = 0;
            scenario.higherBin.offersToTake = 0;
            if (scenario.middleBin.size == 3) {
              // Middle bin is not (fully) taken
              run_market_order_scenario(scenario, printToConsole);
            } else {
              // Middle bin is fully taken
              // Hight bin is empty
              run_market_order_scenario(scenario, printToConsole);
              for (uint h = 0; h < higherBins.length; ++h) {
                scenario.higherBin.bin = higherBins[h];
                // Higher bin should be non-empty, empty is covered by the previous scenario
                for (uint hs = 1; hs < binListScenarios.length; ++hs) {
                  scenario.higherBin.size = binListScenarios[hs][0];
                  scenario.higherBin.offersToTake = binListScenarios[hs][1];
                  run_market_order_scenario(scenario, printToConsole);
                }
              }
            }
          }
        }
      }
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_market_order_scenario() public {
    run_market_order_scenario(
      MarketOrderScenario({
        lowerBin: BinListScenario({bin: Bin.wrap(0), size: 0, offersToTake: 0}),
        middleBin: BinListScenario({bin: BIN_MIN_ALLOWED, size: 2, offersToTake: 2}),
        higherBin: BinListScenario({bin: Bin.wrap(0), size: 0, offersToTake: 0})
      }),
      true
    );
  }

  function scenarioToString(BinListScenario memory scenario) internal pure returns (string memory) {
    string memory binListScenario = scenario.size == 0
      ? "empty          "
      : scenario.size == 2 ? "fully taken    " : scenario.offersToTake == 1 ? "partially taken" : "not taken      ";
    return string.concat(
      binListScenario,
      ", bin: ",
      toString(scenario.bin),
      ", size: ",
      vm.toString(scenario.size),
      ", offersToTake: ",
      vm.toString(scenario.offersToTake)
    );
  }

  TestTickTree tickTree;
  uint lastTakenOfferId;
  bool lastTakenOfferPosthookCalled;

  function removeTakenOffers(BinListScenario memory scenario, uint[] memory offerIds) internal {
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
    if (scenario.higherBin.offersToTake > 0) {
      return higherOfferIds[scenario.higherBin.offersToTake - 1];
    } else if (scenario.middleBin.offersToTake > 0) {
      return middleOfferIds[scenario.middleBin.offersToTake - 1];
    } else if (scenario.lowerBin.offersToTake > 0) {
      return lowerOfferIds[scenario.lowerBin.offersToTake - 1];
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
    setUp();
    if (printToConsole) {
      console.log("market order scenario");
      console.log("  lower bin scenario:  ", scenarioToString(scenario.lowerBin));
      console.log("  middle bin scenario: ", scenarioToString(scenario.middleBin));
      console.log("  higher bin scenario: ", scenarioToString(scenario.higherBin));
    }
    // 1. Create scenario
    (uint[] memory lowerOfferIds, uint lowerOffersGive) =
      add_n_offers_to_bin(scenario.lowerBin.bin, scenario.lowerBin.size);
    (uint[] memory middleOfferIds, uint middleOffersGive) =
      add_n_offers_to_bin(scenario.middleBin.bin, scenario.middleBin.size);
    (uint[] memory higherOfferIds, uint higherOffersGive) =
      add_n_offers_to_bin(scenario.higherBin.bin, scenario.higherBin.size);
    uint fillVolume = lowerOffersGive * scenario.lowerBin.offersToTake
      + middleOffersGive * scenario.middleBin.offersToTake + higherOffersGive * scenario.higherBin.offersToTake;
    lastTakenOfferId = getLastTakenOfferId(scenario, lowerOfferIds, middleOfferIds, higherOfferIds);

    // 2. Snapshot tick tree
    tickTree = snapshotTickTree();

    // 3. Run the market order and check that the tick tree is updated as expected
    // The check of the tick tree is done in the posthook of the last taken offer
    // by the checkMgvTickTreeInLastOfferPosthook function.
    // We therefore must update the test tick tree before the market order is run.
    removeTakenOffers(scenario.lowerBin, lowerOfferIds);
    removeTakenOffers(scenario.middleBin, middleOfferIds);
    removeTakenOffers(scenario.higherBin, higherOfferIds);
    mgv.marketOrderByTick(olKey, Tick.wrap(MAX_TICK), fillVolume, true);
    assertTrue(lastTakenOfferId == 0 || lastTakenOfferPosthookCalled, "last taken offer posthook not called");

    // assertMgvTickTreeIsConsistent();
  }
}
