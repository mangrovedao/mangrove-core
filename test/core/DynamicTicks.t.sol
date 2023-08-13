// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs, MAX_TICK, MIN_TICK, LogPriceLib} from "mgv_src/MgvLib.sol";
import {DensityLib} from "mgv_lib/DensityLib.sol";
import {stdError} from "forge-std/stdError.sol";

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

  function test_logPrice_to_tick(int96 logPrice, uint96 tickScale) public {
    Tick tick = Tick.wrap(logPrice);
    assertEq(LogPriceLib.fromTick(tick, tickScale), int(logPrice) * int(uint(tickScale)), "wrong tick -> logPrice");
  }

  function test_regress() public {
    test_tick_to_logPrice(-7293364022, 7);
  }

  function test_tick_to_logPrice(int96 logPrice, uint96 _tickScale) public {
    vm.assume(_tickScale != 0);
    Tick tick = TickLib.fromLogPrice(logPrice, _tickScale);
    int tickScale = int(uint(_tickScale));
    int expectedTick = logPrice / tickScale;
    if (logPrice < 0 && expectedTick % tickScale != 0) {
      expectedTick = expectedTick - 1;
    }
    assertEq(Tick.unwrap(tick), expectedTick, "wrong logPrice -> tick");
  }

  function boundLogPrice(int24 logPrice) internal view returns (int24) {
    return int24(bound(logPrice, LogPriceLib.MIN_LOG_PRICE, LogPriceLib.MAX_LOG_PRICE));
  }

  function test_newOffer_store_and_retrieve(uint24 tickScale, uint24 tickScale2, int24 logPrice) public {
    vm.assume(tickScale != tickScale2);
    vm.assume(tickScale != 0);
    ol.tickScale = tickScale;
    OL memory ol2 = OL(ol.outbound, ol.inbound, tickScale2);
    mgv.activate(ol, 0, 100, 0);
    mgv.activate(ol2, 0, 100, 0);
    logPrice = boundLogPrice(logPrice);
    uint gives = 1 ether;
    uint wants = LogPriceLib.inboundFromOutbound(logPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    uint ofr = mgv.newOfferByLogPrice(ol, logPrice, gives, 100_000, 30);
    assertEq(mgv.offers(ol2, ofr).gives(), 0, "offer should not be at other tickscale");
    assertEq(mgv.offers(ol, ofr).logPrice(), logPrice, "offer not saved");
  }

  function test_updateOffer_store_and_retrieve(uint24 tickScale, uint24 tickScale2, int24 logPrice) public {
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickScale != tickScale2);
    vm.assume(tickScale != 0);
    vm.assume(tickScale2 != 0);
    ol.tickScale = tickScale;
    OL memory ol2 = OL(ol.outbound, ol.inbound, tickScale2);
    uint gives = 1 ether;
    uint wants = LogPriceLib.inboundFromOutbound(logPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    mgv.activate(ol, 0, 100, 0);
    mgv.activate(ol2, 0, 100, 0);
    uint ofr = mgv.newOfferByLogPrice(ol2, 0, gives, 100_000, 30);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer should be at tickScale2");
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "offer should have correct price");
    assertEq(mgv.offers(ol, ofr).gives(), 0, "offer should not be at tickScale");

    // test fails if no existing offer
    vm.expectRevert("mgv/updateOffer/unauthorized");
    mgv.updateOfferByLogPrice(ol, logPrice, gives, 100_000, 30, ofr);

    // test offers update does not touch another tickScale
    uint ofr2 = mgv.newOfferByLogPrice(ol, 1, gives, 100_000, 30);
    assertEq(ofr, ofr2, "offer ids should be equal");
    mgv.updateOfferByLogPrice(ol, logPrice, gives, 100_000, 30, ofr2);
    assertTrue(mgv.offers(ol2, ofr).isLive(), "offer should still be at tickScale2");
    assertEq(mgv.offers(ol2, ofr).logPrice(), 0, "offer should still have correct price");
    assertTrue(mgv.offers(ol, ofr).isLive(), "offer should be at tickScale");
    assertEq(mgv.offers(ol, ofr).logPrice(), logPrice, "offer should have logPrice");
  }

  function test_tickPlacement(uint24 tickScale, int24 logPrice) public {
    ol.tickScale = tickScale;
    logPrice = boundLogPrice(logPrice);
    vm.assume(tickScale != 0);
    uint gives = 1 ether;
    uint wants = LogPriceLib.inboundFromOutbound(logPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    mgv.activate(ol, 0, 100, 0);
    mgv.newOfferByLogPrice(ol, logPrice, gives, 100_000, 30);
    Tick tick = TickLib.fromLogPrice(logPrice, tickScale);
    assertEq(mgv.leafs(ol, tick.leafIndex()).firstOfferPosition(), tick.posInLeaf());
    assertEq(mgv.level0(ol, tick.level0Index()).firstOnePosition(), tick.posInLevel0());
    assertEq(mgv.level1(ol, tick.level1Index()).firstOnePosition(), tick.posInLevel1());
    assertEq(mgv.level2(ol).firstOnePosition(), tick.posInLevel2());
  }

  function test_noOfferAtZeroTickScale(int24 logPrice, uint96 gives) public {
    // TODO is it really necessary to constraint wants < 96 bits? Or can it go to any size no problem?
    ol.tickScale = 0;
    logPrice = boundLogPrice(logPrice);
    mgv.activate(ol, 0, 100, 0);
    uint wants = LogPriceLib.inboundFromOutbound(logPrice, gives);
    vm.assume(wants > 0);
    vm.assume(wants <= type(uint96).max);
    vm.expectRevert(stdError.divisionError);
    mgv.newOfferByLogPrice(ol, logPrice, gives, 100_00, 30);
  }

  // FIXME think of more tests

  function test_id_is_correct(OL memory ol) public {
    assertEq(ol.id(), keccak256(abi.encode(ol)), "id() is hashing incorrect data");
  }
}
