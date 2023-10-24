// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "@mgv/src/core/MgvLib.sol";
import "@mgv/lib/Debug.sol";

// Tests of Mangrove.cleanByImpersonation's interaction with the tick tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tick tree where there may be offers at:
//   - the offer to be cleaned's bin (including the offer itself)
//   - a higher bin
//   - a lower bin
// 2. we take a snapshot of Mangrove's tick tree
// 3. we clean the offer in both Mangrove and in the snapshot tick tree
// 4. we check that Mangrove's tick tree matches the test tick tree.
//
// The scenarios we want to test are:
// - offer fails/doesn't fail
// - cleaning bin
//   - bin is a *bin of interest* (BoI) as listed in TickTreeTest
//   - list:
//     1. the offer to be cleaned is alone
//     2. the offer to be cleaned is first of two offers
//     3. the offer to be cleaned is last of two offers
//     4. the offer to be cleaned is middle of three offers
// - higher bin list
//   - bin has higher position in same leaf or level1-3 as BoI
//     - if feasible, given cleaning bin
//   - list:
//     1. is empty
//     2. is non-empty
// - lower bin list
//   - bin has lower position in same leaf or level1-3 as BoI
//     - if feasible, given cleaning bin
//   - list:
//     1. is empty
//     2. is non-empty
contract TickTreeCleanOfferTest is TickTreeTest {
  struct CleanOfferScenario {
    BinScenario binScenario;
    uint offerBinListSize;
    uint offerPos;
    bool offerFail;
  }

  // (list size, offer pos)
  uint[2][] binListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_clean_offer_for_BIN_MIN_ROOT_MAX_OTHERS() public {
    run_clean_offer_scenarios_for_bin(BIN_MIN_ROOT_MAX_OTHERS);
  }

  function test_clean_offer_for_BIN_MAX_ROOT_MIN_OTHERS() public {
    run_clean_offer_scenarios_for_bin(BIN_MAX_ROOT_MIN_OTHERS);
  }

  function test_clean_offer_for_BIN_MIDDLE() public {
    run_clean_offer_scenarios_for_bin(BIN_MIDDLE);
  }

  function test_clean_offer_for_BIN_MIN_ALLOWED() public {
    run_clean_offer_scenarios_for_bin(BIN_MIN_ALLOWED);
  }

  function test_clean_offer_for_BIN_MAX_ALLOWED() public {
    run_clean_offer_scenarios_for_bin(BIN_MAX_ALLOWED);
  }

  // size of {lower,higher}BinList if the bin is present in the scenario
  uint[] otherBinListSizeScenarios = [1];

  function run_clean_offer_scenarios_for_bin(Bin bin) internal {
    runBinScenarios(bin, otherBinListSizeScenarios, otherBinListSizeScenarios);
  }

  function runBinScenario(BinScenario memory binScenario) internal override {
    CleanOfferScenario memory scenario;
    scenario.binScenario = binScenario;
    uint[2] storage binListScenario;
    for (uint j = 0; j < binListScenarios.length; ++j) {
      binListScenario = binListScenarios[j];
      scenario.offerBinListSize = binListScenario[0];
      scenario.offerPos = binListScenario[1];

      scenario.offerFail = true;
      run_clean_offer_scenario(scenario, false);

      scenario.offerFail = false;
      run_clean_offer_scenario(scenario, false);
    }
  }

  // This test is useful for debugging a single scneario
  function test_single_clean_offer_scenario() public {
    run_clean_offer_scenario(
      CleanOfferScenario({
        binScenario: BinScenario({
          bin: Bin.wrap(0),
          hasHigherBin: false,
          higherBin: Bin.wrap(0),
          higherBinListSize: 0,
          hasLowerBin: false,
          lowerBin: Bin.wrap(0),
          lowerBinListSize: 0
        }),
        offerBinListSize: 1,
        offerPos: 0,
        offerFail: true
      }),
      true
    );
  }

  function run_clean_offer_scenario(CleanOfferScenario memory scenario, bool printToConsole) internal {
    setUp();
    if (printToConsole) {
      console.log("clean offer scenario");
      console.log("  cleaningBin: %s", toString(scenario.binScenario.bin));
      console.log("  offerBinListSize: %s", scenario.offerBinListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      console.log("  offerFail: %s", scenario.offerFail);
      if (scenario.binScenario.hasHigherBin) {
        Bin higherBin = scenario.binScenario.higherBin;
        console.log("  higherBin: %s", toString(higherBin));
      }
      if (scenario.binScenario.hasLowerBin) {
        console.log("  lowerBin: %s", toString(scenario.binScenario.lowerBin));
      }
    }

    // 1. Create scenario
    (uint[] memory offerIds,) =
      add_n_offers_to_bin(scenario.binScenario.bin, scenario.offerBinListSize, scenario.offerFail);
    uint offerId = offerIds[scenario.offerPos];
    Offer offer = mgv.offers(olKey, offerId);
    OfferDetail offerDetail = mgv.offerDetails(olKey, offerId);

    if (scenario.binScenario.hasHigherBin) {
      add_n_offers_to_bin(scenario.binScenario.higherBin, scenario.binScenario.higherBinListSize);
    }
    if (scenario.binScenario.hasLowerBin) {
      add_n_offers_to_bin(scenario.binScenario.lowerBin, scenario.binScenario.lowerBinListSize);
    }

    // 2. Snapshot tick tree
    TestTickTree tickTree = snapshotTickTree();

    // 3. Clean the offer
    mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, offer.tick(), offerDetail.gasreq(), 1 ether)), $(this)
    );
    if (scenario.offerFail) {
      tickTree.removeOffer(offerId);
    }

    // 4. Assert that Mangrove and tick tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // tickTree.assertMgvTickTreeIsConsistent();
  }
}
