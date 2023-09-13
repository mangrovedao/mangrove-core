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
  MAX_LEAF_POSITION,
  MAX_LEVEL0_POSITION,
  MAX_LEVEL1_POSITION,
  MAX_LEVEL2_POSITION,
  MAX_LEVEL3_POSITION
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

  function setUp() public virtual override {
    super.setUp();

    // Density is irrelevant when testing the tick tree data structure,
    // so we set it to 0 to avoid having to deal with it
    mgv.setDensity(olKey, 0);
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

  // FIXME: I think this is no longer needed since density is now 0
  // Calculates gives that Mangrove will accept for a tick & gasreq
  function getAcceptableGivesForTick(Tick tick, uint gasreq) internal pure returns (uint gives) {
    tick; //shh
    gasreq; //shh
    return 1;
    // // First, try minVolume
    // gives = reader.minVolume(olKey, gasreq);
    // gives = gives == 0 ? 1 : gives;
    // uint wants = LogPriceLib.inboundFromOutbound(LogPriceLib.fromTick(tick, olKey.tickScale), gives);
    // if (wants > 0 && uint96(wants) == wants) {
    //   return gives;
    // }
    // // Else, try max
    // gives = type(uint96).max;
  }

  // # Tick scenario utility structs and functions

  struct TickScenario {
    int tick;
    bool hasHigherTick;
    int higherTick;
    uint higherTickListSize;
    bool hasLowerTick;
    int lowerTick;
    uint lowerTickListSize;
  }

  // FIXME: Update with level3
  function generateHigherTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    Tick higherTick;
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() < MAX_LEAF_POSITION) {
      // higher leaf position
      higherTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1(), _tick.posInLevel0(), _tick.posInLeaf() + 1
      );
      ticks[next++] = Tick.unwrap(higherTick);
    }
    if (_tick.posInLevel0() < MAX_LEVEL0_POSITION) {
      // higher level0 position
      higherTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1(), _tick.posInLevel0() + 1, _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(higherTick);
    }
    if (_tick.posInLevel1() < MAX_LEVEL1_POSITION) {
      // higher level1 position
      higherTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1() + 1, _tick.posInLevel0(), _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(higherTick);
    }
    if (_tick.posInLevel2() < MAX_LEVEL2_POSITION) {
      // higher level2 position
      higherTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2() + 1, _tick.posInLevel1(), _tick.posInLevel0(), _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(higherTick);
    }
    if (_tick.posInLevel3() < MAX_LEVEL3_POSITION) {
      // higher level3 position
      // Choosing MIN POSITION for level2, level1, level0, leaf to avoid hitting logPrice limits.
      // The important thing is to have a higher position in level3.
      higherTick = TickTreeUtil.tickFromBranch(_tick.posInLevel3() + 1, 0, 0, 0, 0);
      ticks[next++] = Tick.unwrap(higherTick);
    }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  // FIXME: Update with level3
  function generateLowerTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    Tick lowerTick;
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() > 0) {
      // lower leaf position
      lowerTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1(), _tick.posInLevel0(), _tick.posInLeaf() - 1
      );
      ticks[next++] = Tick.unwrap(lowerTick);
    }
    if (_tick.posInLevel0() > 0) {
      // lower level0 position
      lowerTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1(), _tick.posInLevel0() - 1, _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(lowerTick);
    }
    if (_tick.posInLevel1() > 0) {
      // lower level1 position
      lowerTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2(), _tick.posInLevel1() - 1, _tick.posInLevel0(), _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(lowerTick);
    }
    if (_tick.posInLevel2() > 0) {
      // lower level2 position
      lowerTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3(), _tick.posInLevel2() - 1, _tick.posInLevel1(), _tick.posInLevel0(), _tick.posInLeaf()
      );
      ticks[next++] = Tick.unwrap(lowerTick);
    }
    if (_tick.posInLevel3() > 0) {
      // lower level3 position
      // Choosing MAX POSITION for level2, level1, level0, leaf to avoid hitting logPrice limits.
      // The important thing is to have a lower position in level3.
      lowerTick = TickTreeUtil.tickFromBranch(
        _tick.posInLevel3() - 1, MAX_LEVEL2_POSITION, MAX_LEVEL1_POSITION, MAX_LEVEL0_POSITION, MAX_LEAF_POSITION
      );
      ticks[next++] = Tick.unwrap(lowerTick);
    }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateTickScenarios(
    int tick,
    uint[] storage higherTickListSizeScenarios,
    uint[] storage lowerTickListSizeScenarios
  ) internal view returns (TickScenario[] memory) {
    int[] memory higherTicks = generateHigherTickScenarios(tick);
    int[] memory lowerTicks = generateLowerTickScenarios(tick);
    TickScenario[] memory tickScenarios =
    new TickScenario[](1 + higherTicks.length * higherTickListSizeScenarios.length + lowerTicks.length * lowerTickListSizeScenarios.length + higherTicks.length * lowerTicks.length * higherTickListSizeScenarios.length * lowerTickListSizeScenarios.length);
    uint next = 0;
    tickScenarios[next++] = TickScenario({
      tick: tick,
      hasHigherTick: false,
      higherTick: 0,
      higherTickListSize: 0,
      hasLowerTick: false,
      lowerTick: 0,
      lowerTickListSize: 0
    });
    for (uint h = 0; h < higherTicks.length; ++h) {
      for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
        tickScenarios[next++] = TickScenario({
          tick: tick,
          hasHigherTick: true,
          higherTick: higherTicks[h],
          higherTickListSize: higherTickListSizeScenarios[hs],
          hasLowerTick: false,
          lowerTick: 0,
          lowerTickListSize: 0
        });
      }
    }
    for (uint l = 0; l < lowerTicks.length; ++l) {
      for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
        tickScenarios[next++] = TickScenario({
          tick: tick,
          hasHigherTick: false,
          higherTick: 0,
          higherTickListSize: 0,
          hasLowerTick: true,
          lowerTick: lowerTicks[l],
          lowerTickListSize: lowerTickListSizeScenarios[ls]
        });
      }
    }
    for (uint h = 0; h < higherTicks.length; ++h) {
      for (uint l = 0; l < lowerTicks.length; ++l) {
        for (uint hs = 0; hs < higherTickListSizeScenarios.length; ++hs) {
          for (uint ls = 0; ls < lowerTickListSizeScenarios.length; ++ls) {
            tickScenarios[next++] = TickScenario({
              tick: tick,
              hasHigherTick: true,
              higherTick: higherTicks[h],
              higherTickListSize: higherTickListSizeScenarios[hs],
              hasLowerTick: true,
              lowerTick: lowerTicks[l],
              lowerTickListSize: lowerTickListSizeScenarios[ls]
            });
          }
        }
      }
    }
    return tickScenarios;
  }

  function add_n_offers_to_tick(int tick, uint n) internal returns (uint[] memory offerIds, uint gives) {
    return add_n_offers_to_tick(tick, n, false);
  }

  function add_n_offers_to_tick(int tick, uint n, bool offersFail)
    internal
    returns (uint[] memory offerIds, uint gives)
  {
    Tick _tick = Tick.wrap(tick);
    int logPrice = LogPriceLib.fromTick(_tick, olKey.tickScale);
    uint gasreq = 10_000_000;
    gives = getAcceptableGivesForTick(_tick, gasreq);
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
    int leafIndex,
    uint posInLevel0,
    int level0Index,
    uint posInLevel1,
    int level1Index,
    uint posInLevel2
  ) internal {
    assertEq(tick.posInLeaf(), posInLeaf, "tick's posInLeaf does not match expected value");
    assertEq(tick.leafIndex(), leafIndex, "tick's leafIndex does not match expected value");
    assertEq(tick.posInLevel0(), posInLevel0, "tick's posInLevel0 does not match expected value");
    assertEq(tick.level0Index(), level0Index, "tick's level0Index does not match expected value");
    assertEq(tick.posInLevel1(), posInLevel1, "tick's posInLevel1 does not match expected value");
    assertEq(tick.level1Index(), level1Index, "tick's level1Index does not match expected value");
    assertEq(tick.posInLevel2(), posInLevel2, "tick's posInLevel2 does not match expected value");
  }
}
