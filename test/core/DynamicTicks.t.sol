// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";
import "@mgv/src/core/MgvLib.sol";
import {DensityLib} from "@mgv/lib/core/DensityLib.sol";
import {stdError} from "@mgv/forge-std/StdError.sol";
import "@mgv/lib/core/Constants.sol";

// In these tests, the testing contract is the market maker.
contract DynamicBinsTest is MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address notAdmin;

  function setUp() public override {
    super.setUp();
  }

  function test_bin_to_tick(int24 _bin, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    Bin bin = Bin.wrap(_bin);
    assertEq(bin.tick(tickSpacing), Tick.wrap(int(_bin) * int(uint(tickSpacing))), "wrong bin -> tick");
  }

  function test_tick_to_nearest_bin(int24 itick, uint16 _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    Bin bin = Tick.wrap(itick).nearestBin(_tickSpacing);
    assertGe(Tick.unwrap(bin.tick(_tickSpacing)), itick, "tick -> bin -> tick must give same or lower bin");

    int tickSpacing = int(uint(_tickSpacing));
    int expectedBin = itick / tickSpacing;
    if (itick > 0 && itick % tickSpacing != 0) {
      expectedBin = expectedBin + 1;
    }
    assertEq(Bin.unwrap(bin), expectedBin, "wrong tick -> bin");
  }

  function test_aligned_tick_to_bin(int96 tick, uint _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    vm.assume(tick % int(uint(_tickSpacing)) == 0);
    Bin bin = Tick.wrap(tick).nearestBin(_tickSpacing);
    assertEq(bin.tick(_tickSpacing), Tick.wrap(tick), "aligned tick -> bin -> tick must give same tick");
  }

  // get a valid tick from a random int24
  function boundTick(int24 tick) internal view returns (int24) {
    return int24(bound(tick, MIN_TICK, MAX_TICK));
  }

  // different tickSpacings map to different storage slots
  function test_newOffer_store_and_retrieve(uint16 tickSpacing, uint16 tickSpacing2, int24 tick) public {
    vm.assume(tickSpacing != tickSpacing2);
    vm.assume(tickSpacing != 0);
    olKey.tickSpacing = tickSpacing;
    OLKey memory ol2 = OLKey(olKey.outbound_tkn, olKey.inbound_tkn, tickSpacing2);
    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    tick = boundTick(tick);
    uint gives = 1 ether;

    Tick insertionTick = Tick.wrap(tick).nearestBin(tickSpacing).tick(tickSpacing);

    vm.assume(insertionTick.inRange());

    uint ofr = mgv.newOfferByTick(olKey, Tick.wrap(tick), gives, 100_000, 30);
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
    OLKey memory ol2 = OLKey(olKey.outbound_tkn, olKey.inbound_tkn, tickSpacing2);
    uint gives = 1 ether;

    Tick insertionTick = Tick.wrap(tick).nearestBin(tickSpacing).tick(tickSpacing);
    vm.assume(insertionTick.inRange());

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    uint ofr = mgv.newOfferByTick(ol2, Tick.wrap(0), gives, 100_000, 30);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer created at tickSpacing2 but not found there");
    assertEq(mgv.offers(ol2, ofr).tick(), Tick.wrap(0), "offer found at tickSpacing2 but with wrong ratio");
    assertFalse(mgv.offers(olKey, ofr).isLive(), "offer created at tickSpacing2 but found at tickSpacing");

    // test fails if no existing offer
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByTick(olKey, Tick.wrap(tick), gives, 100_000, 30, ofr);

    // test offers update does not touch another tickSpacing
    uint ofr2 = mgv.newOfferByTick(olKey, Tick.wrap(1), gives, 100_000, 30);
    assertEq(ofr, ofr2, "tickSpacing and tickSpacing2 seem to shares offer IDs");
    mgv.updateOfferByTick(olKey, Tick.wrap(tick), gives, 100_000, 30, ofr2);
    assertTrue(
      mgv.offers(ol2, ofr).isLive(),
      "creating offer with same ID as ofr in a different tickSpacing seems to have deleted ofr"
    );
    assertEq(
      mgv.offers(ol2, ofr).tick(), Tick.wrap(0), "creating offer with same ID as ofr seems to have changed its ratio"
    );
    assertTrue(mgv.offers(olKey, ofr).isLive(), "offer created at new tickSpacing but not found there");
    assertEq(mgv.offers(olKey, ofr).tick(), insertionTick, "offer found at new tickSpacing but with wrong ratio");
  }

  // the storage of offers depends on the chosen tickSpacing
  function test_tickPlacement(uint16 tickSpacing, int24 tick) public {
    olKey.tickSpacing = tickSpacing;
    tick = boundTick(tick);
    vm.assume(tickSpacing != 0);
    uint gives = 1 ether;
    Bin insertionBin = Tick.wrap(tick).nearestBin(tickSpacing);
    Tick insertionTick = insertionBin.tick(tickSpacing);
    vm.assume(insertionTick.inRange());

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.newOfferByTick(olKey, Tick.wrap(tick), gives, 100_000, 30);
    assertEq(
      mgv.leafs(olKey, insertionBin.leafIndex()).bestNonEmptyBinPos(), insertionBin.posInLeaf(), "wrong pos in leaf"
    );
    assertEq(
      mgv.level3s(olKey, insertionBin.level3Index()).firstOnePosition(),
      insertionBin.posInLevel3(),
      "wrong pos in level3"
    );
    assertEq(
      mgv.level2s(olKey, insertionBin.level2Index()).firstOnePosition(),
      insertionBin.posInLevel2(),
      "wrong pos in level2"
    );
    assertEq(
      mgv.level1s(olKey, insertionBin.level1Index()).firstOnePosition(),
      insertionBin.posInLevel1(),
      "wrong pos in level1"
    );
    assertEq(mgv.root(olKey).firstOnePosition(), insertionBin.posInRoot(), "wrong pos in root");
  }

  function test_id_is_correct(OLKey memory olKey) public {
    assertEq(olKey.hash(), keccak256(abi.encode(olKey)), "id() is hashing incorrect data");
  }

  function test_flipped_is_correct(OLKey memory olKey) public {
    OLKey memory flipped = olKey.flipped();
    assertEq(flipped.inbound_tkn, olKey.outbound_tkn, "flipped() is incorrect");
    assertEq(flipped.outbound_tkn, olKey.inbound_tkn, "flipped() is incorrect");
    assertEq(flipped.tickSpacing, olKey.tickSpacing, "flipped() is incorrect");
  }

  // tick given by maker is normalized and aligned to chosen tickSpacing
  function test_insertionTick_normalization(int24 tick, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    vm.assume(int(tick) % int(uint(tickSpacing)) != 0);
    tick = boundTick(tick);
    Bin insertionBin = Tick.wrap(tick).nearestBin(tickSpacing);
    Tick insertionTick = insertionBin.tick(tickSpacing);
    vm.assume(insertionTick.inRange());
    olKey.tickSpacing = tickSpacing;

    mgv.activate(olKey, 0, 100 << 32, 0);
    uint id = mgv.newOfferByTick(olKey, Tick.wrap(tick), 1 ether, 100_00, 30);
    assertEq(mgv.offers(olKey, id).tick(), insertionTick, "recorded tick does not match nearest lower tick");
    assertEq(
      Tick.unwrap(mgv.offers(olKey, id).tick()) % int(uint(tickSpacing)),
      0,
      "recorded tick should be a multiple of tickSpacing"
    );
  }
}
