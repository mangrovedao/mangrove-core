// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TickTreeTest} from "./TickTreeTest.t.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Tests of Mangrove.updateOffer's interaction with the tick tree.
contract TickTreeUpdateOfferTest is TickTreeTest {
  function setUp() public override {
    super.setUp();

    // Check that the tick tree is consistent after set up
    assertMgvTickTreeIsConsistent();
  }

  struct UpdateOfferScenario {
    TickScenario tickScenario;
    int newTick;
    uint offerTickListSize; // 0 -> offer is not live
    uint offerPos;
  }

  // (list size, offer pos)
  uint[2][] tickListScenarios = [[0, 0], [1, 0], [2, 0], [2, 1], [3, 1]];
  // size of {lower,higher}TickList
  uint[] otherTickListSizeScenarios = [0, 1];
  uint[] emptyTickListSizeScenarios = [0];
  uint[] singletonTickListSizeScenarios = [1];

  // NB: We ran into this memory issue when running through all test ticks in one test: https://github.com/foundry-rs/foundry/issues/3971
  // We therefore have a test case per tick instead.

  function test_update_offer_for_tick_0_higher_is_empty() public {
    run_update_offer_scenarios_for_tick(0, emptyTickListSizeScenarios, otherTickListSizeScenarios);
  }

  function test_update_offer_for_tick_0_higher_is_not_empty() public {
    run_update_offer_scenarios_for_tick(0, singletonTickListSizeScenarios, otherTickListSizeScenarios);
  }

  function test_update_offer_for_tick_0_lower_is_empty() public {
    run_update_offer_scenarios_for_tick(0, otherTickListSizeScenarios, emptyTickListSizeScenarios);
  }

  function test_update_offer_for_tick_0_lower_is_not_empty() public {
    run_update_offer_scenarios_for_tick(0, otherTickListSizeScenarios, singletonTickListSizeScenarios);
  }

  // function test_update_offer_for_tick_1() public {
  //   run_update_offer_scenarios_for_tick(1);
  // }

  // function test_update_offer_for_tick_2() public {
  //   run_update_offer_scenarios_for_tick(2);
  // }

  // function test_update_offer_for_tick_3() public {
  //   run_update_offer_scenarios_for_tick(3);
  // }

  // function test_update_offer_for_tick_negative_1() public {
  //   run_update_offer_scenarios_for_tick(-1);
  // }

  // function test_update_offer_for_tick_negative_2() public {
  //   run_update_offer_scenarios_for_tick(-2);
  // }

  // function test_update_offer_for_tick_negative_3() public {
  //   run_update_offer_scenarios_for_tick(-3);
  // }

  // function test_update_offer_for_tick_negative_4() public {
  //   run_update_offer_scenarios_for_tick(-4);
  // }

  // function test_update_offer_for_tick_max() public {
  //   run_update_offer_scenarios_for_tick(MAX_TICK);
  // }

  // // FIXME: This currently fails with mgv/writeOffer/wants/tooLow
  // // Can we make offers that keep within range? I don't think so, because we set gives to max in this case...
  // function testFail_update_offer_for_tick_min() public {
  //   run_update_offer_scenarios_for_tick(MIN_TICK);
  // }

  function run_update_offer_scenarios_for_tick(
    int tick,
    uint[] memory higherTickListSizeScenarios,
    uint[] memory lowerTickListSizeScenarios
  ) internal {
    vm.pauseGasMetering();
    TickScenario[] memory tickScenarios =
      generateTickScenarios(tick, higherTickListSizeScenarios, lowerTickListSizeScenarios);
    for (uint i = 0; i < tickScenarios.length; ++i) {
      TickScenario memory tickScenario = tickScenarios[i];
      for (uint j = 0; j < tickListScenarios.length; ++j) {
        uint[2] storage tickListScenario = tickListScenarios[j];
        run_update_offer_scenario(
          UpdateOfferScenario({
            tickScenario: tickScenario,
            newTick: tickScenario.tick,
            offerTickListSize: tickListScenario[0],
            offerPos: tickListScenario[1]
          })
        );
        if (tickScenario.hasHigherTick) {
          run_update_offer_scenario(
            UpdateOfferScenario({
              tickScenario: tickScenario,
              newTick: tickScenario.higherTick,
              offerTickListSize: tickListScenario[0],
              offerPos: tickListScenario[1]
            })
          );
        }
        if (tickScenario.hasLowerTick) {
          run_update_offer_scenario(
            UpdateOfferScenario({
              tickScenario: tickScenario,
              newTick: tickScenario.lowerTick,
              offerTickListSize: tickListScenario[0],
              offerPos: tickListScenario[1]
            })
          );
        }
      }
    }
  }

  // FIXME: This scenario triggers bug in Mangrove
  function test_single_update_offer_scenario() public {
    run_update_offer_scenario(
      UpdateOfferScenario({
        tickScenario: TickScenario({
          tick: 0,
          hasHigherTick: true,
          higherTick: 524287,
          higherTickListSize: 1,
          hasLowerTick: true,
          lowerTick: -16384,
          lowerTickListSize: 0
        }),
        offerTickListSize: 1,
        offerPos: 0,
        newTick: -16384
      })
    );
  }

  function run_update_offer_scenario(UpdateOfferScenario memory scenario) internal {
    console.log("update offer scenario");
    console.log("  oldTick: %s", toString(Tick.wrap(scenario.tickScenario.tick)));
    console.log("  newTick: %s", toString(Tick.wrap(scenario.newTick)));
    console.log("  offerTickListSize: %s", scenario.offerTickListSize);
    console.log("  offerPos: %s", scenario.offerPos);
    if (scenario.tickScenario.hasHigherTick) {
      Tick higherTick = Tick.wrap(scenario.tickScenario.higherTick);
      console.log("  higherTick: %s", toString(higherTick));
      console.log("  higherTickListSize: %s", vm.toString(scenario.tickScenario.higherTickListSize));
    }
    if (scenario.tickScenario.hasLowerTick) {
      console.log("  lowerTick: %s", toString(Tick.wrap(scenario.tickScenario.lowerTick)));
      console.log("  lowerTickListSize: %s", vm.toString(scenario.tickScenario.lowerTickListSize));
    }
    // 1. Capture state before test
    uint vmSnapshotId = vm.snapshot();
    // 2. Create scenario
    uint[] memory offerIds =
      add_n_offers_to_tick(scenario.tickScenario.tick, scenario.offerTickListSize == 0 ? 1 : scenario.offerTickListSize);
    uint offerId = offerIds[scenario.offerPos];
    MgvStructs.OfferDetailPacked offerDetail = mgv.offerDetails(olKey, offerId);
    if (scenario.offerTickListSize == 0) {
      mgv.retractOffer(olKey, offerIds[0], false);
    }
    if (scenario.tickScenario.hasHigherTick) {
      add_n_offers_to_tick(scenario.tickScenario.higherTick, scenario.tickScenario.higherTickListSize);
    }
    if (scenario.tickScenario.hasLowerTick) {
      add_n_offers_to_tick(scenario.tickScenario.lowerTick, scenario.tickScenario.lowerTickListSize);
    }
    // 3. Snapshot tick tree
    TickTree storage tickTree = snapshotTickTree();
    console.log("before update");
    console.log("  MGV OB");
    printOrderBook(olKey);
    console.log("  tick tree");
    logTickTree(tickTree);
    // 4. Update the offer
    Tick newTick = Tick.wrap(scenario.newTick);
    uint newGives = getAcceptableGivesForTick(newTick, offerDetail.gasreq());
    mgv.updateOfferByLogPrice(
      olKey,
      LogPriceLib.fromTick(newTick, olKey.tickScale),
      newGives,
      offerDetail.gasreq(),
      offerDetail.gasprice(),
      offerId
    );
    updateOffer(tickTree, offerId, newTick, newGives, offerDetail.gasreq(), offerDetail.gasprice(), $(this));
    assertMgvTickTreeIsConsistent();
    console.log("");
    console.log("after update");
    // FIXME: Fails with "field is 0" when MGV tick tree is inconsistent
    // console.log("  MGV OB");
    // printOrderBook(olKey);
    MgvStructs.OfferPacked mgvOfferAfter = mgv.offers(olKey, offerId);
    console.log("  offer ID %s: %s", vm.toString(offerId), toString(mgvOfferAfter));
    console.log("  tick tree");
    logTickTree(tickTree);
    // 5. Assert that Mangrove and tick tree are equal
    assertMgvOfferListEqToTickTree(tickTree);
    // 6. Restore state from before test
    vm.revertTo(vmSnapshotId);
  }
}
