// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.18;

import {TestTickTree} from "mgv_test/lib/TestTickTree.sol";
import {AbstractMangrove, TestTaker, MangroveTest, IMaker, TestMaker} from "mgv_test/lib/MangroveTest.sol";
import "mgv_src/MgvLib.sol";
import "mgv_lib/Debug.sol";

int constant MIN_LEAF_INDEX = -NUM_LEAFS / 2;
int constant MAX_LEAF_INDEX = -MIN_LEAF_INDEX - 1;
int constant MIN_LEVEL0_INDEX = -NUM_LEVEL0 / 2;
int constant MAX_LEVEL0_INDEX = -MIN_LEVEL0_INDEX - 1;
int constant MIN_LEVEL1_INDEX = -NUM_LEVEL1 / 2;
int constant MAX_LEVEL1_INDEX = -MIN_LEVEL1_INDEX - 1;
uint constant MAX_LEAF_POSITION = uint(LEAF_SIZE - 1);
uint constant MAX_LEVEL0_POSITION = uint(LEVEL0_SIZE - 1);
uint constant MAX_LEVEL1_POSITION = uint(LEVEL1_SIZE - 1);
uint constant MAX_LEVEL2_POSITION = uint(LEVEL2_SIZE - 1);

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
// 5. Compare Mangrove's tick tree to the snapshot tick tree using `assertEqToMgvOffer`
//
// See README.md in this folder for more details.
abstract contract TickTreeTest is MangroveTest {
  TestMaker mkr;

  receive() external payable {}

  function setUp() public virtual override {
    super.setUp();

    mkr = setupMaker(olKey, "maker");
    mkr.approveMgv(base, type(uint).max);
    mkr.provisionMgv(1 ether);

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

  // Calculates gives that Mangrove will accept for a tick & gasreq
  function getAcceptableGivesForTick(Tick tick, uint gasreq) internal view returns (uint gives) {
    // First, try minVolume
    gives = mgv.minVolume(olKey, gasreq);
    uint wants = LogPriceLib.inboundFromOutbound(LogPriceLib.fromTick(tick, olKey.tickScale), gives);
    if (wants > 0 && uint96(wants) == wants) {
      return gives;
    }
    // Else, try max
    gives = type(uint96).max;
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

  function generateHigherTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() < MAX_LEAF_POSITION) {
      ticks[next++] = tick + 1; // in leaf
    }
    if (_tick.posInLevel0() < MAX_LEVEL0_POSITION) {
      ticks[next++] = tick + LEAF_SIZE; // in level0
    }
    if (_tick.posInLevel1() < MAX_LEVEL1_POSITION) {
      ticks[next++] = tick + LEAF_SIZE * LEVEL0_SIZE; // in level1
    }
    if (_tick.posInLevel2() < MAX_LEVEL2_POSITION) {
      ticks[next++] = tick + LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE; // in level2
    }
    if (tick < MAX_TICK) {
      ticks[next++] = MAX_TICK; // at max tick
    }

    int[] memory res = new int[](next);
    for (uint i = 0; i < next; ++i) {
      res[i] = ticks[i];
    }
    return res;
  }

  function generateLowerTickScenarios(int tick) internal pure returns (int[] memory) {
    Tick _tick = Tick.wrap(tick);
    uint next = 0;
    int[] memory ticks = new int[](10);
    if (_tick.posInLeaf() > 0) {
      ticks[next++] = tick - 1; // in leaf
    }
    if (_tick.posInLevel0() > 0) {
      ticks[next++] = tick - LEAF_SIZE; // in level0
    }
    if (_tick.posInLevel1() > 0) {
      ticks[next++] = tick - LEAF_SIZE * LEVEL0_SIZE; // in level1
    }
    if (_tick.posInLevel2() > 0) {
      ticks[next++] = tick - LEAF_SIZE * LEVEL0_SIZE * LEVEL1_SIZE; // in level2
    }
    if (tick > MIN_TICK) {
      ticks[next++] = MIN_TICK; // at min tick
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
    gives = getAcceptableGivesForTick(_tick, 100_000);
    offerIds = new uint[](n);
    for (uint i = 0; i < n; ++i) {
      if (offersFail) {
        offerIds[i] = mkr.newFailingOfferByLogPrice(logPrice, gives, 100_000);
      } else {
        offerIds[i] = mkr.newOfferByLogPrice(logPrice, gives, 100_000);
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
