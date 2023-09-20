// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {
  MgvStructs,
  MAX_TICK_TREE_INDEX,
  MIN_TICK_TREE_INDEX,
  MAX_TICK_TREE_INDEX_ALLOWED,
  MIN_TICK_TREE_INDEX_ALLOWED,
  LogPriceLib
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

  function test_tick_to_logPrice(int24 _tickTreeIndex, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    TickTreeIndex tickTreeIndex = TickTreeIndex.wrap(_tickTreeIndex);
    assertEq(
      LogPriceLib.fromTickTreeIndex(tickTreeIndex, tickSpacing),
      int(_tickTreeIndex) * int(uint(tickSpacing)),
      "wrong tickTreeIndex -> logPrice"
    );
  }

  function test_logPrice_to_nearest_tick(int96 logPrice, uint16 _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    TickTreeIndex tickTreeIndex = TickTreeIndexLib.nearestHigherTickToLogPrice(logPrice, _tickSpacing);
    assertGe(
      LogPriceLib.fromTickTreeIndex(tickTreeIndex, _tickSpacing),
      logPrice,
      "logPrice -> tickTreeIndex -> logPrice must give same or lower logPrice"
    );

    int tickSpacing = int(uint(_tickSpacing));
    int expectedTickTreeIndex = logPrice / tickSpacing;
    if (logPrice > 0 && logPrice % tickSpacing != 0) {
      expectedTickTreeIndex = expectedTickTreeIndex + 1;
    }
    assertEq(TickTreeIndex.unwrap(tickTreeIndex), expectedTickTreeIndex, "wrong logPrice -> tick");
  }

  function test_aligned_logPrice_to_tick(int96 logPrice, uint _tickSpacing) public {
    vm.assume(_tickSpacing != 0);
    vm.assume(logPrice % int(uint(_tickSpacing)) == 0);
    TickTreeIndex tickTreeIndex = TickTreeIndexLib.fromTickTreeIndexAlignedLogPrice(logPrice, _tickSpacing);
    assertEq(
      LogPriceLib.fromTickTreeIndex(tickTreeIndex, _tickSpacing),
      logPrice,
      "aligned logPrice -> tickTreeIndex -> logPrice must give same logPrice"
    );
  }

  // get a valid logPrice from a random int24
  function boundLogPrice(int24 logPrice) internal view returns (int24) {
    return int24(bound(logPrice, MIN_LOG_PRICE, MAX_LOG_PRICE));
  }

  // different tickSpacings map to different storage slots
  function test_newOffer_store_and_retrieve(uint16 tickSpacing, uint16 tickSpacing2, int24 logPrice) public {
    vm.assume(tickSpacing != tickSpacing2);
    vm.assume(tickSpacing != 0);
    olKey.tickSpacing = tickSpacing;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickSpacing2);
    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    logPrice = boundLogPrice(logPrice);
    uint gives = 1 ether;

    int insertionLogPrice = int24(
      LogPriceLib.fromTickTreeIndex(TickTreeIndexLib.nearestHigherTickToLogPrice(logPrice, tickSpacing), tickSpacing)
    );

    vm.assume(LogPriceLib.inRange(insertionLogPrice));

    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_000, 30);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "ofr created at tickSpacing but not found there");
    assertFalse(mgv.offers(ol2, ofr).isLive(), "ofr created at tickSpacing but found at tickSpacing2");
    assertEq(mgv.offers(olKey, ofr).logPrice(), insertionLogPrice, "ofr found at tickSpacing but with wrong ratio");
  }

  // more "tickSpacings do not interfere with one another"
  function test_updateOffer_store_and_retrieve(uint16 tickSpacing, uint16 tickSpacing2, int24 logPrice) public {
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickSpacing != tickSpacing2);
    vm.assume(tickSpacing != 0);
    vm.assume(tickSpacing2 != 0);
    olKey.tickSpacing = tickSpacing;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickSpacing2);
    uint gives = 1 ether;

    int insertionLogPrice = int24(
      LogPriceLib.fromTickTreeIndex(TickTreeIndexLib.nearestHigherTickToLogPrice(logPrice, tickSpacing), tickSpacing)
    );
    vm.assume(LogPriceLib.inRange(insertionLogPrice));

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.activate(ol2, 0, 100 << 32, 0);
    uint ofr = mgv.newOfferByLogPrice(ol2, 0, gives, 100_000, 30);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer created at tickSpacing2 but not found there");
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "offer found at tickSpacing2 but with wrong ratio");
    assertFalse(mgv.offers(olKey, ofr).isLive(), "offer created at tickSpacing2 but found at tickSpacing");

    // test fails if no existing offer
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByLogPrice(olKey, logPrice, gives, 100_000, 30, ofr);

    // test offers update does not touch another tickSpacing
    uint ofr2 = mgv.newOfferByLogPrice(olKey, 1, gives, 100_000, 30);
    assertEq(ofr, ofr2, "tickSpacing and tickSpacing2 seem to shares offer IDs");
    mgv.updateOfferByLogPrice(olKey, logPrice, gives, 100_000, 30, ofr2);
    assertTrue(
      mgv.offers(ol2, ofr).isLive(),
      "creating offer with same ID as ofr in a different tickSpacing seems to have deleted ofr"
    );
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "creating offer with same ID as ofr seems to have changed its ratio");
    assertTrue(mgv.offers(olKey, ofr).isLive(), "offer created at new tickSpacing but not found there");
    assertEq(
      mgv.offers(olKey, ofr).logPrice(), insertionLogPrice, "offer found at new tickSpacing but with wrong ratio"
    );
  }

  // the storage of offers depends on the chosen tickSpacing
  function test_tickPlacement(uint16 tickSpacing, int24 logPrice) public {
    olKey.tickSpacing = tickSpacing;
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickSpacing != 0);
    uint gives = 1 ether;
    TickTreeIndex insertionTickTreeIndex = TickTreeIndexLib.nearestHigherTickToLogPrice(logPrice, tickSpacing);
    int insertionLogPrice = int24(LogPriceLib.fromTickTreeIndex(insertionTickTreeIndex, tickSpacing));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));

    mgv.activate(olKey, 0, 100 << 32, 0);
    mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_000, 30);
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
  function test_noOfferAtZeroTickTreeIndexScale(int24 logPrice, uint96 gives) public {
    vm.assume(gives > 0);
    logPrice = boundLogPrice(logPrice);
    olKey.tickSpacing = 0;
    mgv.activate(olKey, 0, 0, 0);

    vm.expectRevert(stdError.divisionError);
    mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_00, 30);
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

  // logPrice given by maker is normalized and aligned to chosen tickSpacing
  function test_insertionLogPrice_normalization(int24 logPrice, uint16 tickSpacing) public {
    vm.assume(tickSpacing != 0);
    vm.assume(int(logPrice) % int(uint(tickSpacing)) != 0);
    logPrice = boundLogPrice(logPrice);
    TickTreeIndex insertionTickTreeIndex = TickTreeIndexLib.nearestHigherTickToLogPrice(logPrice, tickSpacing);
    int insertionLogPrice = int24(LogPriceLib.fromTickTreeIndex(insertionTickTreeIndex, tickSpacing));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));
    olKey.tickSpacing = tickSpacing;

    mgv.activate(olKey, 0, 100 << 32, 0);
    uint id = mgv.newOfferByLogPrice(olKey, logPrice, 1 ether, 100_00, 30);
    assertEq(mgv.offers(olKey, id).logPrice(), insertionLogPrice, "recorded logPrice does not match nearest lower tick");
    assertEq(
      int(mgv.offers(olKey, id).logPrice()) % int(uint(tickSpacing)),
      0,
      "recorded logPrice should be a multiple of tickSpacing"
    );
  }
}
