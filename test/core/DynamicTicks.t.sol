// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, MAX_TICK, MIN_TICK, LogPriceLib} from "mgv_src/MgvLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";
import {stdError} from "forge-std/StdError.sol";
import "mgv_lib/Constants.sol";

// In these tests, the testing contract is the market maker.
contract DynamicTicksTest is MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  TestMaker dual_mkr;
  address notAdmin;

  function setUp() public override {
    super.setUp();
  }

  function test_logPrice_to_tick(int96 logPrice, uint16 tickScale) public {
    Tick tick = Tick.wrap(logPrice);
    assertEq(LogPriceLib.fromTick(tick, tickScale), int(logPrice) * int(uint(tickScale)), "wrong tick -> logPrice");
  }

  function test_tick_to_logPrice(int96 logPrice, uint16 _tickScale) public {
    vm.assume(_tickScale != 0);
    Tick tick = TickLib.closestLowerTickToLogPrice(logPrice, _tickScale);
    int tickScale = int(uint(_tickScale));
    int expectedTick = logPrice / tickScale;
    if (logPrice < 0 && logPrice % tickScale != 0) {
      expectedTick = expectedTick - 1;
    }
    assertEq(Tick.unwrap(tick), expectedTick, "wrong logPrice -> tick");
  }

  // get a valid logPrice from a random int24
  function boundLogPrice(int24 logPrice) internal view returns (int24) {
    return int24(bound(logPrice, MIN_LOG_PRICE, MAX_LOG_PRICE));
  }

  // different tickScales map to different storage slots
  function test_newOffer_store_and_retrieve(uint16 tickScale, uint16 tickScale2, int24 logPrice) public {
    vm.assume(tickScale != tickScale2);
    vm.assume(tickScale != 0);
    olKey.tickScale = tickScale;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickScale2);
    mgv.activate(olKey, 0, 100, 0);
    mgv.activate(ol2, 0, 100, 0);
    logPrice = boundLogPrice(logPrice);
    uint gives = 1 ether;

    int insertionLogPrice =
      int24(LogPriceLib.fromTick(TickLib.closestLowerTickToLogPrice(logPrice, tickScale), tickScale));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));
    uint wants = LogPriceLib.inboundFromOutbound(insertionLogPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    uint ofr = mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_000, 30);
    assertTrue(mgv.offers(olKey, ofr).isLive(), "ofr created at tickScale but not found there");
    assertFalse(mgv.offers(ol2, ofr).isLive(), "ofr created at tickScale but found at tickScale2");
    assertEq(mgv.offers(olKey, ofr).logPrice(), insertionLogPrice, "ofr found at tickScale but with wrong price");
  }

  // more "tickScales do not interfere with one another"
  function test_updateOffer_store_and_retrieve(uint16 tickScale, uint16 tickScale2, int24 logPrice) public {
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickScale != tickScale2);
    vm.assume(tickScale != 0);
    vm.assume(tickScale2 != 0);
    olKey.tickScale = tickScale;
    OLKey memory ol2 = OLKey(olKey.outbound, olKey.inbound, tickScale2);
    uint gives = 1 ether;

    int insertionLogPrice =
      int24(LogPriceLib.fromTick(TickLib.closestLowerTickToLogPrice(logPrice, tickScale), tickScale));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));
    uint wants = LogPriceLib.inboundFromOutbound(insertionLogPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    mgv.activate(olKey, 0, 100, 0);
    mgv.activate(ol2, 0, 100, 0);
    uint ofr = mgv.newOfferByLogPrice(ol2, 0, gives, 100_000, 30);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer created at tickScale2 but not found there");
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "offer found at tickScale2 but with wrong price");
    assertFalse(mgv.offers(olKey, ofr).isLive(), "offer created at tickScale2 but found at tickScale");

    // test fails if no existing offer
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByLogPrice(olKey, logPrice, gives, 100_000, 30, ofr);

    // test offers update does not touch another tickScale
    uint ofr2 = mgv.newOfferByLogPrice(olKey, 1, gives, 100_000, 30);
    assertEq(ofr, ofr2, "tickScale and tickScale2 seem to shares offer IDs");
    mgv.updateOfferByLogPrice(olKey, logPrice, gives, 100_000, 30, ofr2);
    assertTrue(
      mgv.offers(ol2, ofr).isLive(),
      "creating offer with same ID as ofr in a different tickScale seems to have deleted ofr"
    );
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "creating offer with same ID as ofr seems to have changed its price");
    assertTrue(mgv.offers(olKey, ofr).isLive(), "offer created at new tickScale but not found there");
    assertEq(mgv.offers(olKey, ofr).logPrice(), insertionLogPrice, "offer found at new tickScale but with wrong price");
  }

  // the storage of offers depends on the chosen tickScale
  function test_tickPlacement(uint16 tickScale, int24 logPrice) public {
    olKey.tickScale = tickScale;
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickScale != 0);
    uint gives = 1 ether;
    Tick insertionTick = TickLib.closestLowerTickToLogPrice(logPrice, tickScale);
    int insertionLogPrice = int24(LogPriceLib.fromTick(insertionTick, tickScale));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));
    uint wants = LogPriceLib.inboundFromOutbound(insertionLogPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    mgv.activate(olKey, 0, 100, 0);
    mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_000, 30);
    assertEq(
      mgv.leafs(olKey, insertionTick.leafIndex()).firstOfferPosition(), insertionTick.posInLeaf(), "wrong pos in leaf"
    );
    assertEq(
      mgv.level0(olKey, insertionTick.level0Index()).firstOnePosition(),
      insertionTick.posInLevel0(),
      "wrong pos in level0"
    );
    assertEq(
      mgv.level1(olKey, insertionTick.level1Index()).firstOnePosition(),
      insertionTick.posInLevel1(),
      "wrong pos in level1"
    );
    assertEq(
      mgv.level2(olKey, insertionTick.level2Index()).firstOnePosition(),
      insertionTick.posInLevel2(),
      "wrong pos in level2"
    );
    assertEq(mgv.level3(olKey).firstOnePosition(), insertionTick.posInLevel3(), "wrong pos in level2");
  }

  // creating offer at zero tickScale is impossible
  function test_noOfferAtZeroTickScale(int24 logPrice, uint96 gives) public {
    // TODO is it really necessary to constraint wants < 96 bits? Or can it go to any size no problem?
    olKey.tickScale = 0;
    logPrice = boundLogPrice(logPrice);
    mgv.activate(olKey, 0, 100, 0);
    uint wants = LogPriceLib.inboundFromOutbound(logPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    vm.expectRevert(stdError.divisionError);
    mgv.newOfferByLogPrice(olKey, logPrice, gives, 100_00, 30);
  }

  // FIXME think of more tests

  function test_id_is_correct(OLKey memory olKey) public {
    assertEq(olKey.hash(), keccak256(abi.encode(olKey)), "id() is hashing incorrect data");
  }

  function test_flipped_is_correct(OLKey memory olKey) public {
    OLKey memory flipped = olKey.flipped();
    assertEq(flipped.inbound, olKey.outbound, "flipped() is incorrect");
    assertEq(flipped.outbound, olKey.inbound, "flipped() is incorrect");
    assertEq(flipped.tickScale, olKey.tickScale, "flipped() is incorrect");
  }

  // logPrice given by taker is normalized and aligned to chosen tickScale
  function test_insertionLogPrice_normalization(int24 logPrice, uint16 tickScale) public {
    vm.assume(tickScale != 0);
    vm.assume(int(logPrice) % int(uint(tickScale)) != 0);
    logPrice = boundLogPrice(logPrice);
    Tick insertionTick = TickLib.closestLowerTickToLogPrice(logPrice, tickScale);
    int insertionLogPrice = int24(LogPriceLib.fromTick(insertionTick, tickScale));
    vm.assume(LogPriceLib.inRange(insertionLogPrice));
    olKey.tickScale = tickScale;
    uint wants = LogPriceLib.inboundFromOutbound(insertionLogPrice, 1 ether);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    mgv.activate(olKey, 0, 100, 0);
    uint id = mgv.newOfferByLogPrice(olKey, logPrice, 1 ether, 100_00, 30);
    assertEq(mgv.offers(olKey, id).logPrice(), insertionLogPrice, "recorded logPrice does not match closest lower tick");
    assertEq(
      int(mgv.offers(olKey, id).logPrice()) % int(uint(tickScale)),
      0,
      "recorded logPrice should be a multiple of tickScale"
    );
  }
}
