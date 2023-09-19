// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  TestTickTree,
  TickTreeUtil,
  MIN_LEAF_INDEX,
  MIN_LEVEL0_INDEX,
  MIN_LEVEL1_INDEX,
  MAX_LEAF_INDEX,
  MAX_LEVEL0_INDEX,
  MAX_LEVEL1_INDEX,
  MIN_LEAF_POS,
  MIN_LEVEL0_POS,
  MIN_LEVEL1_POS,
  MIN_LEVEL2_POS,
  MIN_LEVEL3_POS,
  MAX_LEAF_POS,
  MAX_LEVEL0_POS,
  MAX_LEVEL1_POS,
  MAX_LEVEL2_POS,
  MAX_LEVEL3_POS,
  MID_LEAF_POS,
  MID_LEVEL0_POS,
  MID_LEVEL1_POS,
  MID_LEVEL2_POS,
  MID_LEVEL3_POS
} from "mgv_test/lib/TestTickTree.sol";
import {AbstractMangrove, TestTaker, MangroveTest, IMaker, TestMaker} from "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Base class for test of Mangrove's tick tree data structure
//
// Provides a simple tick tree data structure and operations on it that can be used to simulate Mangrove's tick tree
// and then be compared to the actual tick tree.
//
// The test tick tree operations uses simpler (and less efficient) code to manipulate the tick tree, which should make
// it clearer what is going on and easier to convince yourself that the tick tree is manipulated correctly.
//
// In contrast, Mangrove's tick tree operations are optimized and interleaved with other code, which makes it harder to
// reason about.
//
// tl;dr: We use a simple tick tree operations to verify Mangrove's complex tick tree operations.
//
// Basic test flow:
// 1. Set up Mangrove's initial state, ie post offers at relevant ticks
// 2. Take a snapshot of Mangrove's tick tree using `snapshotTickTree` which returns a `TickTree` struct
// 3. Perform some operation on Mangrove (eg add or remove an offer)
// 4. Perform equivalent operation on the snapshot tick tree
// 5. Compare Mangrove's tick tree to the snapshot tick tree using `assertEqToMgvTickTree`
//
// See README.md in this folder for more details.
abstract contract TickTreeTest is MangroveTest {
  TestMaker mkr;

  receive() external payable {}

  // # Ticks of interest
  // Levels&leaf are assumed independent, so we can test multiple equivalence clases with one tick.
  //
  // Equivalence classes to test:
  // - leaf: min, max, mid
  // - levelX: min, max, mid
  //
  // In addition, we test the min and max ticks allowed by (log)Price math.

  // min L3, max L2-0, max leaf
  // We use this tick to test the case where the tick is at the max position in all levels except level3:
  // Max in all positions isn't supported by (log)price math.
  Tick immutable TICK_MIN_L3_MAX_OTHERS =
    TickTreeUtil.tickFromPositions(MIN_LEVEL3_POS, MAX_LEVEL2_POS, MAX_LEVEL1_POS, MAX_LEVEL0_POS, MAX_LEAF_POS);

  // max L3, min L2-0, min leaf
  // We use this tick to test the case where the tick is at the min position in all levels except level3:
  // Min in all positions isn't supported by (log)price math.
  Tick immutable TICK_MAX_L3_MIN_OTHERS =
    TickTreeUtil.tickFromPositions(MAX_LEVEL3_POS, MIN_LEVEL2_POS, MIN_LEVEL1_POS, MIN_LEVEL0_POS, MIN_LEAF_POS);

  // middle L3-0, middle leaf
  Tick immutable TICK_MIDDLE =
    TickTreeUtil.tickFromPositions(MID_LEVEL3_POS, MID_LEVEL2_POS, MID_LEVEL1_POS, MID_LEVEL0_POS, MID_LEAF_POS);

  // min tick allowed by (log)price math
  Tick immutable TICK_MIN_ALLOWED = Tick.wrap(MIN_TICK_ALLOWED);

  // max tick allowed by (log)price math
  Tick immutable TICK_MAX_ALLOWED = Tick.wrap(MAX_TICK_ALLOWED);

  function setUp() public virtual override {
    super.setUp();

    // Density is irrelevant when testing the tick tree data structure,
    // so we set it to 0 to avoid having to deal with it
    mgv.setDensity96X32(olKey, 0);
    mgv.setGasmax(10_000_000);

    mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, type(uint).max);
    mkr.provisionMgv(100 ether);

    deal($(base), $(mkr), type(uint).max);
    deal($(quote), $(this), type(uint).max);
  }

  // # Test tick tree utility functions

  // Creates a snapshot of the Mangrove tick tree
  function snapshotTickTree() internal returns (TestTickTree) {
    TestTickTree tickTree = new TestTickTree(mgv, reader, olKey);
    tickTree.snapshotMgvTickTree();
    return tickTree;
  }

  // # Offer utility functions

  // Calculates gives that Mangrove will accept and can handle (eg in price math) for a tick & gasreq
  function getAcceptableGivesForTick(Tick tick, uint gasreq) internal pure returns (uint gives) {
    tick; //shh
    gasreq; //shh
    // With density=0, Mangrove currently accepts and can handle gives=1 for both high and low prices
    return 1;
  }

  // # Tick scenario utility structs and functions

  struct TickScenario {
    Tick tick;
    bool hasHigherTick;
    Tick higherTick;
    uint higherTickListSize;
    bool hasLowerTick;
    Tick lowerTick;
    uint lowerTickListSize;
  }

  function generateHigherTickScenarios(Tick tick) internal view returns (Tick[] memory) {
    uint next = 0;
    Tick[] memory ticks = new Tick[](10);
    if (tick.posInLeaf() < MAX_LEAF_POS) {
      // higher leaf position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1(), tick.posInLevel0(), tick.posInLeaf() + 1
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel0() < MAX_LEVEL0_POS) {
      // higher level0 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1(), tick.posInLevel0() + 1, tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel1() < MAX_LEVEL1_POS) {
      // higher level1 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1() + 1, tick.posInLevel0(), tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel2() < MAX_LEVEL2_POS) {
      // higher level2 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2() + 1, tick.posInLevel1(), tick.posInLevel0(), tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel3() < MAX_LEVEL3_POS) {
      // higher level3 position
      // Choosing MIN POSITION for level2, level1, level0, leaf to avoid hitting logPrice limits.
      // The important thing is to have a higher position in level3.
      ticks[next++] = TickTreeUtil.tickFromPositions(tick.posInLevel3() + 1, 0, 0, 0, 0);
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }

    Tick[] memory res = new Tick[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateLowerTickScenarios(Tick tick) internal view returns (Tick[] memory) {
    uint next = 0;
    Tick[] memory ticks = new Tick[](10);
    if (tick.posInLeaf() > 0) {
      // lower leaf position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1(), tick.posInLevel0(), tick.posInLeaf() - 1
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel0() > 0) {
      // lower level0 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1(), tick.posInLevel0() - 1, tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel1() > 0) {
      // lower level1 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2(), tick.posInLevel1() - 1, tick.posInLevel0(), tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel2() > 0) {
      // lower level2 position
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3(), tick.posInLevel2() - 1, tick.posInLevel1(), tick.posInLevel0(), tick.posInLeaf()
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tick.posInLevel3() > 0) {
      // lower level3 position
      // Choosing MAX POSITION for level2, level1, level0, leaf to avoid hitting logPrice limits.
      // The important thing is to have a lower position in level3.
      ticks[next++] = TickTreeUtil.tickFromPositions(
        tick.posInLevel3() - 1, MAX_LEVEL2_POS, MAX_LEVEL1_POS, MAX_LEVEL0_POS, MAX_LEAF_POS
      );
      if (!isAllowedByPriceMath(ticks[next - 1])) {
        next--;
      }
    }

    Tick[] memory res = new Tick[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function isAllowedByPriceMath(Tick tick) internal view returns (bool) {
    return Tick.unwrap(TICK_MIN_ALLOWED) <= Tick.unwrap(tick) && Tick.unwrap(tick) <= Tick.unwrap(TICK_MAX_ALLOWED);
  }

  // Implement this in subclasses and then call `runTickScenarios` to generate and run all scenarios
  function runTickScenario(TickScenario memory scenario) internal virtual {}

  // Generates all tick scenarios and calls `runTickScenario` for each one
  function runTickScenarios(
    Tick tick,
    uint[] storage higherTickListSizeScenarios,
    uint[] storage lowerTickListSizeScenarios
  ) internal {
    Tick[] memory higherTicks = generateHigherTickScenarios(tick);
    Tick[] memory lowerTicks = generateLowerTickScenarios(tick);
    TickScenario memory scenario;

    scenario.tick = tick;
    scenario.hasHigherTick = false;
    scenario.higherTick = Tick.wrap(0);
    scenario.higherTickListSize = 0;
    scenario.hasLowerTick = false;
    scenario.lowerTick = Tick.wrap(0);
    scenario.lowerTickListSize = 0;

    runTickScenario(scenario);

    scenario.hasHigherTick = true;
    for (uint h = 0; h < higherTicks.length; ++h) {
      scenario.higherTick = higherTicks[h];
      for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
        scenario.higherTickListSize = higherTickListSizeScenarios[hs];
        runTickScenario(scenario);
      }
    }

    scenario.hasHigherTick = false;
    scenario.higherTick = Tick.wrap(0);
    scenario.higherTickListSize = 0;
    scenario.hasLowerTick = true;
    for (uint l = 0; l < lowerTicks.length; ++l) {
      scenario.lowerTick = lowerTicks[l];
      for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
        scenario.lowerTickListSize = lowerTickListSizeScenarios[ls];
        runTickScenario(scenario);
      }
    }

    scenario.hasHigherTick = true;
    scenario.hasLowerTick = true;
    for (uint h = 0; h < higherTicks.length; ++h) {
      scenario.higherTick = higherTicks[h];
      for (uint l = 0; l < lowerTicks.length; ++l) {
        scenario.lowerTick = lowerTicks[l];
        for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
          scenario.higherTickListSize = higherTickListSizeScenarios[hs];
          for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
            scenario.lowerTickListSize = lowerTickListSizeScenarios[ls];
            runTickScenario(scenario);
          }
        }
      }
    }
  }

  function add_n_offers_to_tick(Tick tick, uint n) internal returns (uint[] memory offerIds, uint gives) {
    return add_n_offers_to_tick(tick, n, false);
  }

  function add_n_offers_to_tick(Tick tick, uint n, bool offersFail)
    internal
    returns (uint[] memory offerIds, uint gives)
  {
    int logPrice = LogPriceLib.fromTick(tick, olKey.tickScale);
    uint gasreq = 10_000_000;
    gives = getAcceptableGivesForTick(tick, gasreq);
    offerIds = new uint[](n);
    for (uint i = 0; i < n; ++i) {
      if (offersFail) {
        offerIds[i] = mkr.newFailingOfferByLogPrice(logPrice, gives, gasreq);
      } else {
        offerIds[i] = mkr.newOfferByLogPrice(logPrice, gives, gasreq);
      }
    }
  }

  // # Tick utility functions

  function assertTickAssumptions(
    Tick tick,
    uint posInLeaf,
    uint posInLevel0,
    uint posInLevel1,
    uint posInLevel2,
    uint posInLevel3
  ) internal {
    string memory tickString = toString(tick);
    assertEq(
      tick.posInLeaf(),
      posInLeaf,
      string.concat(
        "tick's posInLeaf does not match expected value | posInLeaf: ", vm.toString(posInLeaf), ", tick: ", tickString
      )
    );
    assertEq(
      tick.posInLevel0(),
      posInLevel0,
      string.concat(
        "tick's posInLevel0 does not match expected value | posInLevel0: ",
        vm.toString(posInLevel0),
        ", tick: ",
        tickString
      )
    );
    assertEq(
      tick.posInLevel1(),
      posInLevel1,
      string.concat(
        "tick's posInLevel1 does not match expected value | posInLevel1: ",
        vm.toString(posInLevel1),
        ", tick: ",
        tickString
      )
    );
    assertEq(
      tick.posInLevel2(),
      posInLevel2,
      string.concat(
        "tick's posInLevel2 does not match expected value | posInLevel2: ",
        vm.toString(posInLevel2),
        ", tick: ",
        tickString
      )
    );
    assertEq(
      tick.posInLevel3(),
      posInLevel3,
      string.concat(
        "tick's posInLevel3 does not match expected value | posInLevel3: ",
        vm.toString(posInLevel3),
        ", tick: ",
        tickString
      )
    );
  }
}
