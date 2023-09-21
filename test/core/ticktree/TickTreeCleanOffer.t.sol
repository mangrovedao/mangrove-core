// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.cleanByImpersonation's interaction with the bin tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove bin tree where there may be offers at:
//   - the offer to be cleaned's bin (including the offer itself)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's bin tree
// 3. we clean the offer in both Mangrove and in the snapshot bin tree
// 4. we check that Mangrove's bin tree matches the test bin tree.
//
// The scenarios we want to test are:
// - offer fails/doesn't fail
// - cleaning tick
//   - bin is a *bin of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. the offer to be cleaned is alone
//     2. the offer to be cleaned is first of two offers
//     3. the offer to be cleaned is last of two offers
//     4. the offer to be cleaned is middle of three offers
// - higher bin list
//   - bin has higher position in same leaf or level2-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower bin list
//   - bin has lower position in same leaf or level2-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
contract TickTreeCleanOfferTest is TickTreeTest {
  struct CleanOfferScenario {
    BinScenario tickScenario;
    uint offerBinListSize;
    uint offerPos;
    bool offerFail;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_clean_offer_for_BIN_MIN_ROOT_MAX_OTHERS() public {
    run_clean_offer_scenarios_for_tick(BIN_MIN_ROOT_MAX_OTHERS);
  }

  function test_clean_offer_for_BIN_MAX_ROOT_MIN_OTHERS() public {
    run_clean_offer_scenarios_for_tick(BIN_MAX_ROOT_MIN_OTHERS);
  }

  function test_clean_offer_for_BIN_MIDDLE() public {
    run_clean_offer_scenarios_for_tick(BIN_MIDDLE);
  }

  function test_clean_offer_for_BIN_MIN_ALLOWED() public {
    run_clean_offer_scenarios_for_tick(BIN_MIN_ALLOWED);
  }

  function test_clean_offer_for_BIN_MAX_ALLOWED() public {
    run_clean_offer_scenarios_for_tick(BIN_MAX_ALLOWED);
  }

  // size of {lower,higher}BinList if the bin is present in the scenario
  uint[] otherBinListSizeScenarios = [1];

  function run_clean_offer_scenarios_for_tick(Bin bin) internal {
    vm.pauseGasMetering();
    runBinScenarios(bin, otherBinListSizeScenarios, otherBinListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runBinScenario(BinScenario memory tickScenario) internal override {
    CleanOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListScenarios.length; ++j) {
      uint[2] storage tickListScenario = tickListScenarios[j];
      scenario.offerBinListSize = tickListScenario[0];
      scenario.offerPos = tickListScenario[1];

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
        tickScenario: BinScenario({
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
    if (printToConsole) {
      console.log("clean offer scenario");
      console.log("  cleaningBin: %s", toString(scenario.tickScenario.bin));
      console.log("  offerBinListSize: %s", scenario.offerBinListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      console.log("  offerFail: %s", scenario.offerFail);
      if (scenario.tickScenario.hasHigherBin) {
        Bin higherBin = scenario.tickScenario.higherBin;
        console.log("  higherBin: %s", toString(higherBin));
      }
      if (scenario.tickScenario.hasLowerBin) {
        console.log("  lowerBin: %s", toString(scenario.tickScenario.lowerBin));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory offerIds,) =
      add_n_offers_to_tick(scenario.tickScenario.bin, scenario.offerBinListSize, scenario.offerFail);
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);

    if (scenario.tickScenario.hasHigherBin) {
      add_n_offers_to_tick(scenario.tickScenario.higherBin, scenario.tickScenario.higherBinListSize);
    }
    if (scenario.tickScenario.hasLowerBin) {
      add_n_offers_to_tick(scenario.tickScenario.lowerBin, scenario.tickScenario.lowerBinListSize);
    }

    // 3. Snapshot bin tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Clean the offer
    mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, offer.tick(), offerDetail.gasreq(), 1 ether)), $(this)
    );
    if (scenario.offerFail) {
      tickTree.removeOffer(offerId);
    }

    // 5. Assert that Mangrove and bin tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // tickTree.assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
