// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {
  TestTickTree,
  TickTreeUtil,
  MIN_LEAF_INDEX,
  MIN_LEVEL2_INDEX,
  MIN_LEVEL1_INDEX,
  MAX_LEAF_INDEX,
  MAX_LEVEL2_INDEX,
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

// Base class for test of Mangrove's bin tree data structure
//
// Provides a simple bin tree data structure and operations on it that can be used to simulate Mangrove's bin tree
// and then be compared to the actual bin tree.
//
// The test bin tree operations uses simpler (and less efficient) code to manipulate the bin tree, which should make
// it clearer what is going on and easier to convince yourself that the bin tree is manipulated correctly.
//
// In contrast, Mangrove's bin tree operations are optimized and interleaved with other code, which makes it harder to
// reason about.
//
// tl;dr: We use a simple bin tree operations to verify Mangrove's complex bin tree operations.
//
// Basic test flow:
// 1. Set up Mangrove's initial state, ie post offers at relevant ticks
// 2. Take a snapshot of Mangrove's bin tree using `snapshotTickTree` which returns a `TickTree` struct
// 3. Perform some operation on Mangrove (eg add or remove an offer)
// 4. Perform equivalent operation on the snapshot bin tree
// 5. Compare Mangrove's bin tree to the snapshot bin tree using `assertEqToMgvTickTree`
//
// See README.md in this folder for more details.
abstract contract TickTreeTest is MangroveTest {
  TestMaker mkr;

  receive() external payable {}

  // # Bins of interest
  // Levels&leaf are assumed independent, so we can test multiple equivalence clases with one bin.
  //
  // Equivalence classes to test:
  // - leaf: min, max, mid
  // - levelX: min, max, mid
  //
  // In addition, we test the min and max ticks allowed by (log)Ratio math.

  // min ROOT, max L2-0, max leaf
  // We use this bin to test the case where the bin is at the max position in all levels except root:
  // Max in all positions isn't supported by (log)ratio math.
  Bin immutable BIN_MIN_ROOT_MAX_OTHERS =
    TickTreeUtil.binFromPositions(MIN_ROOT_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEAF_POS);

  // max ROOT, min L2-0, min leaf
  // We use this bin to test the case where the bin is at the min position in all levels except root:
  // Min in all positions isn't supported by (log)ratio math.
  Bin immutable BIN_MAX_ROOT_MIN_OTHERS =
    TickTreeUtil.binFromPositions(MAX_ROOT_POS, MIN_LEVEL_POS, MIN_LEVEL_POS, MIN_LEVEL_POS, MIN_LEAF_POS);

  // middle ROOT-0, middle leaf
  Bin immutable BIN_MIDDLE =
    TickTreeUtil.binFromPositions(MID_ROOT_POS, MID_LEVEL_POS, MID_LEVEL_POS, MID_LEVEL_POS, MID_LEAF_POS);

  // min bin allowed by (log)ratio math
  Bin immutable BIN_MIN_ALLOWED = Bin.wrap(MIN_BIN_ALLOWED);

  // max bin allowed by (log)ratio math
  Bin immutable BIN_MAX_ALLOWED = Bin.wrap(MAX_BIN_ALLOWED);

  function setUp() public virtual override {
    super.setUp();

    // Density is irrelevant when testing the bin tree data structure,
    // so we set it to 0 to avoid having to deal with it
    mgv.setDensity96X32(olKey, 0);
    mgv.setGasmax(10_000_000);

    mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, type(uint).max);
    mkr.provisionMgv(100 ether);

    deal($(base), $(mkr), type(uint).max);
    deal($(quote), $(this), type(uint).max);
  }

  // # Test bin tree utility functions

  // Creates a snapshot of the Mangrove bin tree
  function snapshotTickTree() internal returns (TestTickTree) {
    TestTickTree tickTree = new TestTickTree(mgv, reader, olKey);
    tickTree.snapshotMgvTickTree();
    return tickTree;
  }

  // # Offer utility functions

  // Calculates gives that Mangrove will accept and can handle (eg in ratio math) for a bin & gasreq
  function getAcceptableGivesForBin(Bin bin, uint gasreq) internal pure returns (uint gives) {
    bin; //shh
    gasreq; //shh
    // With density=0, Mangrove currently accepts and can handle gives=1 for both high and low ratios
    return 1;
  }

  // # Bin scenario utility structs and functions

  struct BinScenario {
    Bin bin;
    bool hasHigherBin;
    Bin higherBin;
    uint higherBinListSize;
    bool hasLowerBin;
    Bin lowerBin;
    uint lowerBinListSize;
  }

  function generateHigherBinScenarios(Bin bin) internal view returns (Bin[] memory) {
    uint next = 0;
    Bin[] memory ticks = new Bin[](10);
    if (bin.posInLeaf() < MAX_LEAF_POS) {
      // higher leaf position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1(), bin.posInLevel2(), bin.posInLeaf() + 1
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel2() < MAX_LEVEL_POS) {
      // higher level2 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1(), bin.posInLevel2() + 1, bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel1() < MAX_LEVEL_POS) {
      // higher level1 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1() + 1, bin.posInLevel2(), bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel0() < MAX_LEVEL_POS) {
      // higher level0 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0() + 1, bin.posInLevel1(), bin.posInLevel2(), bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInRoot() < MAX_ROOT_POS) {
      // higher root position
      // Choosing MIN POSITION for level0, level1, level2, leaf to avoid hitting tick limits.
      // The important thing is to have a higher position in root.
      ticks[next++] = TickTreeUtil.binFromPositions(bin.posInRoot() + 1, 0, 0, 0, 0);
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }

    Bin[] memory res = new Bin[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateLowerBinScenarios(Bin bin) internal view returns (Bin[] memory) {
    uint next = 0;
    Bin[] memory ticks = new Bin[](10);
    if (bin.posInLeaf() > 0) {
      // lower leaf position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1(), bin.posInLevel2(), bin.posInLeaf() - 1
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel2() > 0) {
      // lower level2 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1(), bin.posInLevel2() - 1, bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel1() > 0) {
      // lower level1 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0(), bin.posInLevel1() - 1, bin.posInLevel2(), bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInLevel0() > 0) {
      // lower level0 position
      ticks[next++] = TickTreeUtil.binFromPositions(
        bin.posInRoot(), bin.posInLevel0() - 1, bin.posInLevel1(), bin.posInLevel2(), bin.posInLeaf()
      );
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }
    if (bin.posInRoot() > 0) {
      // lower root position
      // Choosing MAX POSITION for level0, level1, level2, leaf to avoid hitting tick limits.
      // The important thing is to have a lower position in root.
      ticks[next++] =
        TickTreeUtil.binFromPositions(bin.posInRoot() - 1, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEVEL_POS, MAX_LEAF_POS);
      if (!isAllowedByRatioMath(ticks[next - 1])) {
        next--;
      }
    }

    Bin[] memory res = new Bin[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function isAllowedByRatioMath(Bin bin) internal view returns (bool) {
    return Bin.unwrap(BIN_MIN_ALLOWED) <= Bin.unwrap(bin) && Bin.unwrap(bin) <= Bin.unwrap(BIN_MAX_ALLOWED);
  }

  // Implement this in subclasses and then call `runBinScenarios` to generate and run all scenarios
  function runBinScenario(BinScenario memory scenario) internal virtual {}

  // Generates all bin scenarios and calls `runBinScenario` for each one
  function runBinScenarios(Bin bin, uint[] storage higherBinListSizeScenarios, uint[] storage lowerBinListSizeScenarios)
    internal
  {
    Bin[] memory higherBins = generateHigherBinScenarios(bin);
    Bin[] memory lowerBins = generateLowerBinScenarios(bin);
    BinScenario memory scenario;

    scenario.bin = bin;
    scenario.hasHigherBin = false;
    scenario.higherBin = Bin.wrap(0);
    scenario.higherBinListSize = 0;
    scenario.hasLowerBin = false;
    scenario.lowerBin = Bin.wrap(0);
    scenario.lowerBinListSize = 0;

    runBinScenario(scenario);

    scenario.hasHigherBin = true;
    for (uint h = 0; h < higherBins.length; ++h) {
      scenario.higherBin = higherBins[h];
      for (uint hs = 0; hs < higherBinListSizeScenarios.length; ++hs) {
        scenario.higherBinListSize = higherBinListSizeScenarios[hs];
        runBinScenario(scenario);
      }
    }

    scenario.hasHigherBin = false;
    scenario.higherBin = Bin.wrap(0);
    scenario.higherBinListSize = 0;
    scenario.hasLowerBin = true;
    for (uint l = 0; l < lowerBins.length; ++l) {
      scenario.lowerBin = lowerBins[l];
      for (uint ls = 0; ls < lowerBinListSizeScenarios.length; ++ls) {
        scenario.lowerBinListSize = lowerBinListSizeScenarios[ls];
        runBinScenario(scenario);
      }
    }

    scenario.hasHigherBin = true;
    scenario.hasLowerBin = true;
    for (uint h = 0; h < higherBins.length; ++h) {
      scenario.higherBin = higherBins[h];
      for (uint l = 0; l < lowerBins.length; ++l) {
        scenario.lowerBin = lowerBins[l];
        for (uint hs = 0; hs < higherBinListSizeScenarios.length; ++hs) {
          scenario.higherBinListSize = higherBinListSizeScenarios[hs];
          for (uint ls = 0; ls < lowerBinListSizeScenarios.length; ++ls) {
            scenario.lowerBinListSize = lowerBinListSizeScenarios[ls];
            runBinScenario(scenario);
          }
        }
      }
    }
  }

  function add_n_offers_to_tick(Bin bin, uint n) internal returns (uint[] memory offerIds, uint gives) {
    return add_n_offers_to_tick(bin, n, false);
  }

  function add_n_offers_to_tick(Bin bin, uint n, bool offersFail) internal returns (uint[] memory offerIds, uint gives) {
    int tick = TickLib.fromBin(bin, olKey.tickSpacing);
    uint gasreq = 10_000_000;
    gives = getAcceptableGivesForBin(bin, gasreq);
    offerIds = new uint[](n);
    for (uint i = 0; i < n; ++i) {
      if (offersFail) {
        offerIds[i] = mkr.newFailingOfferByTick(tick, gives, gasreq);
      } else {
        offerIds[i] = mkr.newOfferByTick(tick, gives, gasreq);
      }
    }
  }

  // # Bin utility functions

  function assertBinAssumptions(
    Bin bin,
    uint posInLeaf,
    uint posInLevel2,
    uint posInLevel1,
    uint posInLevel0,
    uint posInRoot
  ) internal {
    string memory tickString = toString(bin);
    assertEq(
      bin.posInLeaf(),
      posInLeaf,
      string.concat(
        "tick's posInLeaf does not match expected value | posInLeaf: ", vm.toString(posInLeaf), ", bin: ", tickString
      )
    );
    assertEq(
      bin.posInLevel2(),
      posInLevel2,
      string.concat(
        "tick's posInLevel2 does not match expected value | posInLevel2: ",
        vm.toString(posInLevel2),
        ", bin: ",
        tickString
      )
    );
    assertEq(
      bin.posInLevel1(),
      posInLevel1,
      string.concat(
        "tick's posInLevel1 does not match expected value | posInLevel1: ",
        vm.toString(posInLevel1),
        ", bin: ",
        tickString
      )
    );
    assertEq(
      bin.posInLevel0(),
      posInLevel0,
      string.concat(
        "tick's posInLevel0 does not match expected value | posInLevel0: ",
        vm.toString(posInLevel0),
        ", bin: ",
        tickString
      )
    );
    assertEq(
      bin.posInRoot(),
      posInRoot,
      string.concat(
        "tick's posInRoot does not match expected value | posInRoot: ", vm.toString(posInRoot), ", bin: ", tickString
      )
    );
  }
}
