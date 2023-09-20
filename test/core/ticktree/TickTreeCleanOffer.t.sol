// SPDX-License-Identifier:  AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest, TestTickTree} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.cleanByImpersonation's interaction with the tickTreeIndex tree.
//
// The tests use the following pattern:
// 1. we establish a Mangrove tickTreeIndex tree where there may be offers at:
//   - the offer to be cleaned's tickTreeIndex (including the offer itself)
//   - a higher tick
//   - a lower tick
// 2. we take a snapshot of Mangrove's tickTreeIndex tree
// 3. we clean the offer in both Mangrove and in the snapshot tickTreeIndex tree
// 4. we check that Mangrove's tickTreeIndex tree matches the test tickTreeIndex tree.
//
// The scenarios we want to test are:
// - offer fails/doesn't fail
// - cleaning tick
//   - tickTreeIndex is a *tickTreeIndex of interest* (ToI) as listed in TickTreeTest
//   - list:
//     1. the offer to be cleaned is alone
//     2. the offer to be cleaned is first of two offers
//     3. the offer to be cleaned is last of two offers
//     4. the offer to be cleaned is middle of three offers
// - higher tickTreeIndex list
//   - tickTreeIndex has higher position in same leaf or level0-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
// - lower tickTreeIndex list
//   - tickTreeIndex has lower position in same leaf or level0-3 as ToI
//     - if feasible, given cleaning tick
//   - list:
//     1. is empty
//     2. is non-empty
contract TickTreeCleanOfferTest is TickTreeTest {
  struct CleanOfferScenario {
    TickTreeIndexScenario tickScenario;
    uint offerTickTreeIndexListSize;
    uint offerPos;
    bool offerFail;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[1, 0], [2, 0], [2, 1], [3, 1]];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per ToI instead.

  function test_clean_offer_for_TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS() public {
    run_clean_offer_scenarios_for_tick(TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS);
  }

  function test_clean_offer_for_TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS() public {
    run_clean_offer_scenarios_for_tick(TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS);
  }

  function test_clean_offer_for_TICK_TREE_INDEX_MIDDLE() public {
    run_clean_offer_scenarios_for_tick(TICK_TREE_INDEX_MIDDLE);
  }

  function test_clean_offer_for_TICK_TREE_INDEX_MIN_ALLOWED() public {
    run_clean_offer_scenarios_for_tick(TICK_TREE_INDEX_MIN_ALLOWED);
  }

  function test_clean_offer_for_TICK_TREE_INDEX_MAX_ALLOWED() public {
    run_clean_offer_scenarios_for_tick(TICK_TREE_INDEX_MAX_ALLOWED);
  }

  // size of {lower,higher}TickTreeIndexList if the tickTreeIndex is present in the scenario
  uint[] otherTickTreeIndexListSizeScenarios = [1];

  function run_clean_offer_scenarios_for_tick(TickTreeIndex tickTreeIndex) internal {
    vm.pauseGasMetering();
    runTickTreeIndexScenarios(tickTreeIndex, otherTickTreeIndexListSizeScenarios, otherTickTreeIndexListSizeScenarios);
    vm.resumeGasMetering();
  }

  function runTickTreeIndexScenario(TickTreeIndexScenario memory tickScenario) internal override {
    CleanOfferScenario memory scenario;
    scenario.tickScenario = tickScenario;
    for (uint j = 0; j < tickListScenarios.length; ++j) {
      uint[2] storage tickListScenario = tickListScenarios[j];
      scenario.offerTickTreeIndexListSize = tickListScenario[0];
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
        tickScenario: TickTreeIndexScenario({
          tickTreeIndex: TickTreeIndex.wrap(0),
          hasHigherTickTreeIndex: false,
          higherTickTreeIndex: TickTreeIndex.wrap(0),
          higherTickTreeIndexListSize: 0,
          hasLowerTickTreeIndex: false,
          lowerTickTreeIndex: TickTreeIndex.wrap(0),
          lowerTickTreeIndexListSize: 0
        }),
        offerTickTreeIndexListSize: 1,
        offerPos: 0,
        offerFail: true
      }),
      true
    );
  }

  function run_clean_offer_scenario(CleanOfferScenario memory scenario, bool printToConsole) internal {
    if (printToConsole) {
      console.log("clean offer scenario");
      console.log("  cleaningTickTreeIndex: %s", toString(scenario.tickScenario.tickTreeIndex));
      console.log("  offerTickTreeIndexListSize: %s", scenario.offerTickTreeIndexListSize);
      console.log("  offerPos: %s", scenario.offerPos);
      console.log("  offerFail: %s", scenario.offerFail);
      if (scenario.tickScenario.hasHigherTickTreeIndex) {
        TickTreeIndex higherTickTreeIndex = scenario.tickScenario.higherTickTreeIndex;
        console.log("  higherTickTreeIndex: %s", toString(higherTickTreeIndex));
      }
      if (scenario.tickScenario.hasLowerTickTreeIndex) {
        console.log("  lowerTickTreeIndex: %s", toString(scenario.tickScenario.lowerTickTreeIndex));
      }
    }

    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();

    // 2. Create scenario
    (uint[] memory offerIds,) =
      add_n_offers_to_tick(scenario.tickScenario.tickTreeIndex, scenario.offerTickTreeIndexListSize, scenario.offerFail);
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferPacked offer = mgv.offers(olKey, offerId);
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);

    if (scenario.tickScenario.hasHigherTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.higherTickTreeIndex, scenario.tickScenario.higherTickTreeIndexListSize);
    }
    if (scenario.tickScenario.hasLowerTickTreeIndex) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTickTreeIndex, scenario.tickScenario.lowerTickTreeIndexListSize);
    }

    // 3. Snapshot tickTreeIndex tree
    TestTickTree tickTree = snapshotTickTree();

    // 4. Clean the offer
    mgv.cleanByImpersonation(
      olKey, wrap_dynamic(MgvLib.CleanTarget(offerId, offer.logPrice(), offerDetail.gasreq(), 1 ether)), $(this)
    );
    if (scenario.offerFail) {
      tickTree.removeOffer(offerId);
    }

    // 5. Assert that Mangrove and tickTreeIndex tree are equal
    tickTree.assertEqToMgvTickTree();
    // Uncommenting the following can be helpful in debugging tree consistency issues
    // tickTree.assertMgvTickTreeIsConsistent();

    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
