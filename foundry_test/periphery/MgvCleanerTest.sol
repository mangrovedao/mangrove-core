// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;
import "mgv_test/tools/MangroveTest.sol";
// pragma experimental ABIEncoderV2;

import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";

// In these tests, the testing contract is the market maker.
contract MgvCleanerTest is MangroveTest {
  receive() external payable {}

  AbstractMangrove mgv;
  TestTaker tkr;
  TestMaker mkr;
  address outbound;
  address inbound;
  MgvCleaner cleaner;

  function setUp() public {
    TestToken Outbound = setupToken("A", "$A");
    TestToken Inbound = setupToken("B", "$B");
    outbound = address(Outbound);
    inbound = address(Inbound);
    mgv = setupMangrove(Outbound, Inbound);
    mkr = setupMaker(mgv, outbound, inbound);
    cleaner = new MgvCleaner(address(mgv));

    payable(mkr).transfer(10 ether);

    mkr.provisionMgv(5 ether);

    Inbound.mint(address(this), 2 ether);
    Outbound.mint(address(mkr), 1 ether);

    Outbound.approve(address(mgv), 1 ether);
    Inbound.approve(address(mgv), 1 ether);
    mkr.approveMgv(Outbound, 1 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "MgvCleaner_Test");
    vm.label(outbound, "$A");
    vm.label(inbound, "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(mkr), "maker[$A,$B]");
    vm.label(address(cleaner), "cleaner");
  }

  /* # Test Config */

  function test_single_failing_offer() public {
    mgv.approve(outbound, inbound, address(cleaner), type(uint).max);

    mkr.shouldFail(true);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    uint oldBal = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];
    cleaner.collect(outbound, inbound, targets, true);

    uint newBal = address(this).balance;

    assertGt(newBal, oldBal, "balance should have increased");
  }

  function test_mult_failing_offer() public {
    mgv.approve(outbound, inbound, address(cleaner), type(uint).max);

    mkr.shouldFail(true);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);
    uint ofr2 = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    uint oldBal = address(this).balance;

    uint[4][] memory targets = new uint[4][](2);
    targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];
    targets[1] = [ofr2, 1 ether, 1 ether, type(uint).max];
    cleaner.collect(outbound, inbound, targets, true);

    uint newBal = address(this).balance;

    assertGt(newBal, oldBal, "balance should have increased");
  }

  function test_no_fail_no_cleaning() public {
    mgv.approve(outbound, inbound, address(cleaner), type(uint).max);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    uint oldBal = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];
    try cleaner.collect(outbound, inbound, targets, true) {
      fail("collect should fail since offer succeeded");
    } catch Error(string memory reason) {
      assertEq(
        "mgvCleaner/anOfferDidNotFail",
        reason,
        "fail should be due to offer execution succeeding"
      );
    }

    uint newBal = address(this).balance;

    assertEq(newBal, oldBal, "balance should be the same");
  }

  // For now there is no need to approve
  // function test_no_approve_no_cleaning() public {
  //   uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000,0);

  //   uint[4][] memory targets = new uint[4][](1);
  //   targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];

  //   try cleaner.collect(outbound, inbound,targets,true) {
  //     fail("collect should fail since cleaner was not approved");
  //   } catch Error(string memory reason) {
  //     assertEq("mgv/lowAllowance",reason,"Fail should be due to no allowance");
  //   }
  // }
}
