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
  MIN_LEVEL_POS,
  MIN_ROOT_POS,
  MAX_LEAF_POS,
  MAX_LEVEL_POS,
  MAX_ROOT_POS,
  MID_LEAF_POS,
  MID_LEVEL_POS,
  MID_ROOT_POS
} from "mgv_test/lib/TestTickTree.sol";
import {AbstractMangrove, TestTaker, MangroveTest, IMaker, TestMaker} from "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

// Base class for test of Mangrove's tickTreeIndex tree data structure
//
// Provides a simple tickTreeIndex tree data structure and operations on it that can be used to simulate Mangrove's tickTreeIndex tree
// and then be compared to the actual tickTreeIndex tree.
//
// The test tickTreeIndex tree operations uses simpler (and less efficient) code to manipulate the tickTreeIndex tree, which should make
// it clearer what is going on and easier to convince yourself that the tickTreeIndex tree is manipulated correctly.
//
// In contrast, Mangrove's tickTreeIndex tree operations are optimized and interleaved with other code, which makes it harder to
// reason about.
//
// tl;dr: We use a simple tickTreeIndex tree operations to verify Mangrove's complex tickTreeIndex tree operations.
//
// Basic test flow:
// 1. Set up Mangrove's initial state, ie post offers at relevant ticks
// 2. Take a snapshot of Mangrove's tickTreeIndex tree using `snapshotTickTree` which returns a `TickTree` struct
// 3. Perform some operation on Mangrove (eg add or remove an offer)
// 4. Perform equivalent operation on the snapshot tickTreeIndex tree
// 5. Compare Mangrove's tickTreeIndex tree to the snapshot tickTreeIndex tree using `assertEqToMgvTickTree`
//
// See README.md in this folder for more details.
abstract contract TickTreeTest is MangroveTest {
  TestMaker mkr;

  receive() external payable {}

  // # TickTreeIndexs of interest
  // Levels&leaf are assumed independent, so we can test multiple equivalence clases with one tickTreeIndex.
  //
  // Equivalence classes to test:
  // - leaf: min, max, mid
  // - levelX: min, max, mid
  //
  // In addition, we test the min and max ticks allowed by (log)Ratio math.

  // min ROOT, max L2-0, max leaf
  // We use this tickTreeIndex to test the case where the tickTreeIndex is at the max position in all levels except root:
  // Max in all positions isn't supported by (log)ratio math.
  TickTreeIndex immutable TICK_TREE_INDEX_MIN_ROOT_MAX_OTHERS =
    TickTreeUtil.tickTreeIndexFromPositions(MIN_ROOT_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEAF_POS);

  // max ROOT, min L2-0, min leaf
  // We use this tickTreeIndex to test the case where the tickTreeIndex is at the min position in all levels except root:
  // Min in all positions isn't supported by (log)ratio math.
  TickTreeIndex immutable TICK_TREE_INDEX_MAX_ROOT_MIN_OTHERS =
    TickTreeUtil.tickTreeIndexFromPositions(MAX_ROOT_POS, MIN_LEVEL_POS, MIN_LEVEL_POS, MIN_LEVEL_POS, MIN_LEAF_POS);

  // middle ROOT-0, middle leaf
  TickTreeIndex immutable TICK_TREE_INDEX_MIDDLE =
    TickTreeUtil.tickTreeIndexFromPositions(MID_ROOT_POS, MID_LEVEL_POS, MID_LEVEL_POS, MID_LEVEL_POS, MID_LEAF_POS);

  // min tickTreeIndex allowed by (log)ratio math
  TickTreeIndex immutable TICK_TREE_INDEX_MIN_ALLOWED = TickTreeIndex.wrap(MIN_TICK_TREE_INDEX_ALLOWED);

  // max tickTreeIndex allowed by (log)ratio math
  TickTreeIndex immutable TICK_TREE_INDEX_MAX_ALLOWED = TickTreeIndex.wrap(MAX_TICK_TREE_INDEX_ALLOWED);

  function setUp() public virtual override {
    super.setUp();

    // Density is irrelevant when testing the tickTreeIndex tree data structure,
    // so we set it to 0 to avoid having to deal with it
    mgv.setDensity96X32(olKey, 0);
    mgv.setGasmax(10_000_000);

    mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, type(uint).max);
    mkr.provisionMgv(100 ether);

    deal($(base), $(mkr), type(uint).max);
    deal($(quote), $(this), type(uint).max);
  }

  // # Test tickTreeIndex tree utility functions

  // Creates a snapshot of the Mangrove tickTreeIndex tree
  function snapshotTickTree() internal returns (TestTickTree) {
    TestTickTree tickTree = new TestTickTree(mgv, reader, olKey);
    tickTree.snapshotMgvTickTree();
    return tickTree;
  }

  // # Offer utility functions

  // Calculates gives that Mangrove will accept and can handle (eg in ratio math) for a tickTreeIndex & gasreq
  function getAcceptableGivesForTickTreeIndex(TickTreeIndex tickTreeIndex, uint gasreq)
    internal
    pure
    returns (uint gives)
  {
    tickTreeIndex; //shh
    gasreq; //shh
    // With density=0, Mangrove currently accepts and can handle gives=1 for both high and low ratios
    return 1;
  }

  // # TickTreeIndex scenario utility structs and functions

  struct TickTreeIndexScenario {
    TickTreeIndex tickTreeIndex;
    bool hasHigherTickTreeIndex;
    TickTreeIndex higherTickTreeIndex;
    uint higherTickTreeIndexListSize;
    bool hasLowerTickTreeIndex;
    TickTreeIndex lowerTickTreeIndex;
    uint lowerTickTreeIndexListSize;
  }

  function generateHigherTickTreeIndexScenarios(TickTreeIndex tickTreeIndex)
    internal
    view
    returns (TickTreeIndex[] memory)
  {
    uint next = 0;
    TickTreeIndex[] memory ticks = new TickTreeIndex[](10);
    if (tickTreeIndex.posInLeaf() < MAX_LEAF_POS) {
      // higher leaf position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf() + 1
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel0() < MAX_LEVEL_POS) {
      // higher level0 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0() + 1,
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel1() < MAX_LEVEL_POS) {
      // higher level1 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1() + 1,
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel2() < MAX_LEVEL_POS) {
      // higher level2 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2() + 1,
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInRoot() < MAX_ROOT_POS) {
      // higher root position
      // Choosing MIN POSITION for level2, level1, level0, leaf to avoid hitting tick limits.
      // The important thing is to have a higher position in root.
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(tickTreeIndex.posInRoot() + 1, 0, 0, 0, 0);
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }

    TickTreeIndex[] memory res = new TickTreeIndex[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateLowerTickTreeIndexScenarios(TickTreeIndex tickTreeIndex)
    internal
    view
    returns (TickTreeIndex[] memory)
  {
    uint next = 0;
    TickTreeIndex[] memory ticks = new TickTreeIndex[](10);
    if (tickTreeIndex.posInLeaf() > 0) {
      // lower leaf position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf() - 1
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel0() > 0) {
      // lower level0 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0() - 1,
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel1() > 0) {
      // lower level1 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2(),
        tickTreeIndex.posInLevel1() - 1,
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInLevel2() > 0) {
      // lower level2 position
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot(),
        tickTreeIndex.posInLevel2() - 1,
        tickTreeIndex.posInLevel1(),
        tickTreeIndex.posInLevel0(),
        tickTreeIndex.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (tickTreeIndex.posInRoot() > 0) {
      // lower root position
      // Choosing MAX POSITION for level2, level1, level0, leaf to avoid hitting tick limits.
      // The important thing is to have a lower position in root.
      ticks[next++] = TickTreeUtil.tickTreeIndexFromPositions(
        tickTreeIndex.posInRoot() - 1, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEAF_POS
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }

    TickTreeIndex[] memory res = new TickTreeIndex[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function isAllowedByRatioMath(TickTreeIndex tickTreeIndex) internal view returns (bool) {
    return TickTreeIndex.unwrap(TICK_TREE_INDEX_MIN_ALLOWED) <= TickTreeIndex.unwrap(tickTreeIndex)
      && TickTreeIndex.unwrap(tickTreeIndex) <= TickTreeIndex.unwrap(TICK_TREE_INDEX_MAX_ALLOWED);
  }

  // Implement this in subclasses and then call `runTickTreeIndexScenarios` to generate and run all scenarios
  function runTickTreeIndexScenario(TickTreeIndexScenario memory scenario) internal virtual {}

  // Generates all tickTreeIndex scenarios and calls `runTickTreeIndexScenario` for each one
  function runTickTreeIndexScenarios(
    TickTreeIndex tickTreeIndex,
    uint[] storage higherTickTreeIndexListSizeScenarios,
    uint[] storage lowerTickTreeIndexListSizeScenarios
  ) internal {
    TickTreeIndex[] memory higherTickTreeIndexs = generateHigherTickTreeIndexScenarios(tickTreeIndex);
    TickTreeIndex[] memory lowerTickTreeIndexs = generateLowerTickTreeIndexScenarios(tickTreeIndex);
    TickTreeIndexScenario memory scenario;

    scenario.tickTreeIndex = tickTreeIndex;
    scenario.hasHigherTickTreeIndex = false;
    scenario.higherTickTreeIndex = TickTreeIndex.wrap(0);
    scenario.higherTickTreeIndexListSize = 0;
    scenario.hasLowerTickTreeIndex = false;
    scenario.lowerTickTreeIndex = TickTreeIndex.wrap(0);
    scenario.lowerTickTreeIndexListSize = 0;

    runTickTreeIndexScenario(scenario);

    scenario.hasHigherTickTreeIndex = true;
    for (uint h = 0; h < higherTickTreeIndexs.length; ++h) {
      scenario.higherTickTreeIndex = higherTickTreeIndexs[h];
      for (uint hs = 0; hs < higherTickTreeIndexListSizeScenarios.length; ++hs) {
        scenario.higherTickTreeIndexListSize = higherTickTreeIndexListSizeScenarios[hs];
        runTickTreeIndexScenario(scenario);
      }
    }

    scenario.hasHigherTickTreeIndex = false;
    scenario.higherTickTreeIndex = TickTreeIndex.wrap(0);
    scenario.higherTickTreeIndexListSize = 0;
    scenario.hasLowerTickTreeIndex = true;
    for (uint l = 0; l < lowerTickTreeIndexs.length; ++l) {
      scenario.lowerTickTreeIndex = lowerTickTreeIndexs[l];
      for (uint ls = 0; ls < lowerTickTreeIndexListSizeScenarios.length; ++ls) {
        scenario.lowerTickTreeIndexListSize = lowerTickTreeIndexListSizeScenarios[ls];
        runTickTreeIndexScenario(scenario);
      }
    }

    scenario.hasHigherTickTreeIndex = true;
    scenario.hasLowerTickTreeIndex = true;
    for (uint h = 0; h < higherTickTreeIndexs.length; ++h) {
      scenario.higherTickTreeIndex = higherTickTreeIndexs[h];
      for (uint l = 0; l < lowerTickTreeIndexs.length; ++l) {
        scenario.lowerTickTreeIndex = lowerTickTreeIndexs[l];
        for (uint hs = 0; hs < higherTickTreeIndexListSizeScenarios.length; ++hs) {
          scenario.higherTickTreeIndexListSize = higherTickTreeIndexListSizeScenarios[hs];
          for (uint ls = 0; ls < lowerTickTreeIndexListSizeScenarios.length; ++ls) {
            scenario.lowerTickTreeIndexListSize = lowerTickTreeIndexListSizeScenarios[ls];
            runTickTreeIndexScenario(scenario);
          }
        }
      }
    }
  }

  function add_n_offers_to_tick(TickTreeIndex tickTreeIndex, uint n)
    internal
    returns (uint[] memory offerIds, uint gives)
  {
    return add_n_offers_to_tick(tickTreeIndex, n, false);
  }

  function add_n_offers_to_tick(TickTreeIndex tickTreeIndex, uint n, bool offersFail)
    internal
    returns (uint[] memory offerIds, uint gives)
  {
    int tick = TickLib.fromTickTreeIndex(tickTreeIndex, olKey.tickSpacing);
    uint gasreq = 10_000_000;
    gives = getAcceptableGivesForTickTreeIndex(tickTreeIndex, gasreq);
    offerIds = new uint[](n);
    for (uint i = 0; i < n; ++i) {
      if (offersFail) {
        offerIds[i] = mkr.newFailingOfferByTick(tick, gives, gasreq);
      } else {
        offerIds[i] = mkr.newOfferByTick(tick, gives, gasreq);
      }
    }
  }

  // # TickTreeIndex utility functions

  function assertTickTreeIndexAssumptions(
    TickTreeIndex tickTreeIndex,
    uint posInLeaf,
    uint posInLevel0,
    uint posInLevel1,
    uint posInLevel2,
    uint posInRoot
  ) internal {
    string memory tickString = toString(tickTreeIndex);
    assertEq(
      tickTreeIndex.posInLeaf(),
      posInLeaf,
      string.concat(
        "tick's posInLeaf does not match expected value | posInLeaf: ",
        vm.toString(posInLeaf),
        ", tickTreeIndex: ",
        tickString
      )
    );
    assertEq(
      tickTreeIndex.posInLevel0(),
      posInLevel0,
      string.concat(
        "tick's posInLevel0 does not match expected value | posInLevel0: ",
        vm.toString(posInLevel0),
        ", tickTreeIndex: ",
        tickString
      )
    );
    assertEq(
      tickTreeIndex.posInLevel1(),
      posInLevel1,
      string.concat(
        "tick's posInLevel1 does not match expected value | posInLevel1: ",
        vm.toString(posInLevel1),
        ", tickTreeIndex: ",
        tickString
      )
    );
    assertEq(
      tickTreeIndex.posInLevel2(),
      posInLevel2,
      string.concat(
        "tick's posInLevel2 does not match expected value | posInLevel2: ",
        vm.toString(posInLevel2),
        ", tickTreeIndex: ",
        tickString
      )
    );
    assertEq(
      tickTreeIndex.posInRoot(),
      posInRoot,
      string.concat(
        "tick's posInRoot does not match expected value | posInRoot: ",
        vm.toString(posInRoot),
        ", tickTreeIndex: ",
        tickString
      )
    );
  }
}
