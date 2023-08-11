// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, TestTaker, TestMaker} from "mgv_test/lib/MangroveTest.sol";
// pragma experimental ABIEncoderV2;

import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {Tick} from "mgv_lib/TickLib.sol";

// In these tests, the testing contract is the market maker.
contract MgvCleanerTest is MangroveTest {
  receive() external payable {}

  TestTaker tkr;
  TestMaker mkr;
  MgvCleaner cleaner;

  function setUp() public override {
    super.setUp();
    mkr = setupMaker($(base), $(quote), "maker");
    cleaner = new MgvCleaner($(mgv));
    vm.label(address(cleaner), "cleaner");

    mkr.provisionMgv(5 ether);

    deal($(base), address(mkr), 1 ether);

    mkr.approveMgv(base, 1 ether);
    mgv.approve($(base), $(quote), address(cleaner), type(uint).max);
  }

  function test_single_failing_offer() public {
    deal($(quote), $(this), 10 ether);
    mkr.shouldFail(true);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers($(base), $(quote), ofr).tick();

    uint oldBal = $(this).balance;

    cleaner.collect($(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(tick)), 1 ether, type(uint).max]), true);

    uint newBal = $(this).balance;

    assertGt(newBal, oldBal, "balance should have increased");
  }

  function setupTaker() internal returns (address taker) {
    taker = freshAddress();
    deal($(quote), taker, 10 ether);
    vm.prank(taker);
    quote.approve($(mgv), type(uint).max);
    return taker;
  }

  function test_single_failing_offer_impersonation() public {
    mkr.shouldFail(true);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers($(base), $(quote), ofr).tick();

    address taker = setupTaker();

    uint oldBal = $(this).balance;

    cleaner.collectByImpersonation(
      $(base), $(quote), wrap_dynamic([ofr, uint(Tick.unwrap(tick)), 1 ether, type(uint).max]), true, taker
    );

    uint newBal = $(this).balance;

    assertGt(newBal, oldBal, "balance should have increased");
  }

  function test_mult_failing_offer() public {
    deal($(quote), $(this), 10 ether);
    mkr.shouldFail(true);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers($(base), $(quote), ofr).tick();
    uint ofr2 = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick2 = mgv.offers($(base), $(quote), ofr2).tick();

    uint oldBal = $(this).balance;

    uint[4][] memory targets = new uint[4][](2);
    targets[0] = [ofr, uint(Tick.unwrap(tick)), 1 ether, type(uint).max];
    targets[1] = [ofr2, uint(Tick.unwrap(tick2)), 1 ether, type(uint).max];
    cleaner.collect($(base), $(quote), targets, true);

    uint newBal = $(this).balance;

    assertGt(newBal, oldBal, "balance should have increased");
  }

  function test_no_fail_no_cleaning() public {
    deal($(quote), $(this), 10 ether);
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);
    Tick tick = mgv.offers($(base), $(quote), ofr).tick();

    uint oldBal = $(this).balance;

    uint[4][] memory targets = wrap_dynamic([ofr, uint(Tick.unwrap(tick)), 1 ether, type(uint).max]);

    (uint successes,) = cleaner.collect($(base), $(quote), targets, true);
    assertTrue(successes == 0, "cleaning should not succeed");

    uint newBal = $(this).balance;

    assertEq(newBal, oldBal, "balance should be the same");
  }

  function test_cleans_failing_offers_despite_one_not_failing() public {
    deal($(quote), $(this), 10 ether);
    uint ofr = mkr.newFailingOfferByTick(0, 1 ether, 50_000);
    uint ofr2 = mkr.newOfferByTick(0, 1 ether, 50_000);
    uint ofr3 = mkr.newFailingOfferByTick(0, 1 ether, 50_000);

    uint oldBal = $(this).balance;

    uint[4][] memory targets = new uint[4][](3);
    targets[0] = [ofr, 0, 1 ether, type(uint).max];
    targets[1] = [ofr2, 0, 1 ether, type(uint).max];
    targets[2] = [ofr3, 0, 1 ether, type(uint).max];
    (uint successes, uint bounty) = cleaner.collect($(base), $(quote), targets, false);

    uint newBal = $(this).balance;

    assertEq(successes, 2, "cleaning should succeed for all but one offer");
    assertEq(newBal, oldBal + bounty, "balance should have increased by bounty");
  }

  // For now there is no need to approve
  // function test_no_approve_no_cleaning() public {
  //   uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000,0);

  //   uint[4][] memory targets = new uint[4][](1);
  //   targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];

  //   try cleaner.collect($(base), $(quote),targets,true) {
  //     fail("collect should fail since cleaner was not approved");
  //   } catch Error(string memory reason) {
  //     assertEq("mgv/lowAllowance",reason,"Fail should be due to no allowance");
  //   }
  // }
}
