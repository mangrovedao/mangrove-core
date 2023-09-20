// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  MgvStructs,
  MAX_TICK_TREE_INDEX,
  MIN_TICK_TREE_INDEX,
  MAX_TICK_TREE_INDEX_ALLOWED,
  MIN_TICK_TREE_INDEX_ALLOWED,
  TickLib
} from "mgv_src/MgvLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";
import {stdError} from "forge-std/StdError.sol";
import "mgv_lib/Constants.sol";

// In these tests, the testing contract is the market maker.
contract DynamicTickTreeIndexsTest is MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address notAdmin;

  function setUp() public override {
    super.setUp();
  }

  function test_tick_to_tick(int24 _tickTreeIndex, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    TickTreeIndex tickTreeIndex = TickTreeIndex.wrap(_tickTreeIndex);
    assertEq(
      TickLib.fromTickTreeIndex(tickTreeIndex, tickSpacing),
      int(_tickTreeIndex) * int(uint(tickSpacing)),
      "wrong tickTreeIndex -> tick"
    );
  }

  function test_tick_to_nearest_tick(int96 tick, uint16 _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    TickTreeIndex tickTreeIndex = TickTreeIndexLib.nearestHigherTickToTick(tick, _tickSpacing);
    assertGe(
      TickLib.fromTickTreeIndex(tickTreeIndex, _tickSpacing),
      tick,
      "tick -> tickTreeIndex -> tick must give same or lower tick"
    );

    int tickSpacing = int(uint(_tickSpacing));
    int expectedTickTreeIndex = tick / tickSpacing;
    if (tick > 0 && tick % tickSpacing != 0) {
      expectedTickTreeIndex = expectedTickTreeIndex + 1;
    }
    assertEq(TickTreeIndex.unwrap(tickTreeIndex), expectedTickTreeIndex, "wrong tick -> tick");
  }

  function test_aligned_tick_to_tick(int96 tick, uint _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    vm.assume(tick % int(uint(_tickSpacing)) == 0);
    TickTreeIndex tickTreeIndex = TickTreeIndexLib.fromTickTreeIndexAlignedTick(tick, _tickSpacing);
    assertEq(
      TickLib.fromTickTreeIndex(tickTreeIndex, _tickSpacing),
      tick,
      "aligned tick -> tickTreeIndex -> tick must give same tick"
    );
  }

  // get a valid tick from a random int24
  function boundTick(int24 tick) internal view returns (int24) {
    return int24(bound(tick, MIN_LOG_PRICE, MAX_LOG_PRICE));
  }

  // different tickSpacings map to different storage slots
  function test_newOffer_store_and_retrieve(uint16 tickSpacing, uint16 tickSpacing2, int24 tick) public {
    vm.assume(tickSpacing != tickSpacing2);
    vm.assume(tickSpacing != 0);
    olKey.tickSpacing = tickSpacing;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickSpacing2);
    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    tick = boundTick(tick);
    uint gives = 1 ether;

    int insertionTick =
      int24(TickLib.fromTickTreeIndex(TickTreeIndexLib.nearestHigherTickToTick(tick, tickSpacing), tickSpacing));

    vm.assume(TickLib.inRange(insertionTick));

    uint ofr = mgv.newOfferByTick(olKey, tick, gives, 100_000, 30);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "ofr created at tickSpacing but not found there");
    assertFalse(mgv.offers(ol2, ofr).isLive(), "ofr created at tickSpacing but found at tickSpacing2");
    assertEq(mgv.offers(olKey, ofr).tick(), insertionTick, "ofr found at tickSpacing but with wrong ratio");
  }

  // more "tickSpacings do not interfere with one another"
  function test_updateOffer_store_and_retrieve(uint16 tickSpacing, uint16 tickSpacing2, int24 tick) public {
    tick = boundTick(tick);
    vm.assume(tickSpacing != tickSpacing2);
    vm.assume(tickSpacing != 0);
    vm.assume(tickSpacing2 != 0);
    olKey.tickSpacing = tickSpacing;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickSpacing2);
    uint gives = 1 ether;

    int insertionTick =
      int24(TickLib.fromTickTreeIndex(TickTreeIndexLib.nearestHigherTickToTick(tick, tickSpacing), tickSpacing));
    vm.assume(TickLib.inRange(insertionTick));

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    uint ofr = mgv.newOfferByTick(ol2, 0, gives, 100_000, 30);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer created at tickSpacing2 but not found there");
    assertEq(mgv.offers(ol2, ofr).tick(), 0, "offer found at tickSpacing2 but with wrong ratio");
    assertFalse(mgv.offers(olKey, ofr).isLive(), "offer created at tickSpacing2 but found at tickSpacing");

    // test fails if no existing offer
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByTick(olKey, tick, gives, 100_000, 30, ofr);

    // test offers update does not touch another tickSpacing
    uint ofr2 = mgv.newOfferByTick(olKey, 1, gives, 100_000, 30);
    assertEq(ofr, ofr2, "tickSpacing and tickSpacing2 seem to shares offer IDs");
    mgv.updateOfferByTick(olKey, tick, gives, 100_000, 30, ofr2);
    assertTrue(
      mgv.offers(ol2, ofr).isLive(),
      "creating offer with same ID as ofr in a different tickSpacing seems to have deleted ofr"
    );
    assertEq(mgv.offers(ol2, ofr).tick(), 0, "creating offer with same ID as ofr seems to have changed its ratio");
    assertTrue(mgv.offers(olKey, ofr).isLive(), "offer created at new tickSpacing but not found there");
    assertEq(mgv.offers(olKey, ofr).tick(), insertionTick, "offer found at new tickSpacing but with wrong ratio");
  }

  // the storage of offers depends on the chosen tickSpacing
  function test_tickPlacement(uint16 tickSpacing, int24 tick) public {
    olKey.tickSpacing = tickSpacing;
    tick = boundTick(tick);
    vm.assume(tickSpacing != 0);
    uint gives = 1 ether;
    TickTreeIndex insertionTickTreeIndex = TickTreeIndexLib.nearestHigherTickToTick(tick, tickSpacing);
    int insertionTick = int24(TickLib.fromTickTreeIndex(insertionTickTreeIndex, tickSpacing));
    vm.assume(TickLib.inRange(insertionTick));

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.newOfferByTick(olKey, tick, gives, 100_000, 30);
    assertEq(
      mgv.leafs(olKey, insertionTickTreeIndex.leafIndex()).firstOfferPosition(),
      insertionTickTreeIndex.posInLeaf(),
      "wrong pos in leaf"
    );
    assertEq(
      mgv.level0(olKey, insertionTickTreeIndex.level0Index()).firstOnePosition(),
      insertionTickTreeIndex.posInLevel0(),
      "wrong pos in level0"
    );
    assertEq(
      mgv.level1(olKey, insertionTickTreeIndex.level1Index()).firstOnePosition(),
      insertionTickTreeIndex.posInLevel1(),
      "wrong pos in level1"
    );
    assertEq(
      mgv.level2(olKey, insertionTickTreeIndex.level2Index()).firstOnePosition(),
      insertionTickTreeIndex.posInLevel2(),
      "wrong pos in level2"
    );
    assertEq(mgv.root(olKey).firstOnePosition(), insertionTickTreeIndex.posInRoot(), "wrong pos in root");
  }

  // creating offer at zero tickSpacing is impossible
  function test_noOfferAtZeroTickTreeIndexScale(int24 tick, uint96 gives) public {
    vm.assume(gives > 0);
    tick = boundTick(tick);
    olKey.tickSpacing = 0;
    mgv.activate(olKey, 0, 0, 0);

    vm.expectRevert(stdError.divisionError);
    mgv.newOfferByTick(olKey, tick, gives, 100_00, 30);
  }

  function test_id_is_correct(OLKey memory olKey) public {
    assertEq(olKey.hash(), keccak256(abi.encode(olKey)), "id() is hashing incorrect data");
  }

  function test_flipped_is_correct(OLKey memory olKey) public {
    OLKey memory flipped = olKey.flipped();
    assertEq(flipped.inbound, olKey.outbound, "flipped() is incorrect");
    assertEq(flipped.outbound, olKey.inbound, "flipped() is incorrect");
    assertEq(flipped.tickSpacing, olKey.tickSpacing, "flipped() is incorrect");
  }

  // tick given by maker is normalized and aligned to chosen tickSpacing
  function test_insertionTick_normalization(int24 tick, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    vm.assume(int(tick) % int(uint(tickSpacing)) != 0);
    tick = boundTick(tick);
    TickTreeIndex insertionTickTreeIndex = TickTreeIndexLib.nearestHigherTickToTick(tick, tickSpacing);
    int insertionTick = int24(TickLib.fromTickTreeIndex(insertionTickTreeIndex, tickSpacing));
    vm.assume(TickLib.inRange(insertionTick));
    olKey.tickSpacing = tickSpacing;

    mgv.activate(olKey, 0, 100 << 32, 0);
    uint id = mgv.newOfferByTick(olKey, tick, 1 ether, 100_00, 30);
    assertEq(mgv.offers(olKey, id).tick(), insertionTick, "recorded tick does not match nearest lower tick");
    assertEq(
      int(mgv.offers(olKey, id).tick()) % int(uint(tickSpacing)), 0, "recorded tick should be a multiple of tickSpacing"
    );
  }
}
