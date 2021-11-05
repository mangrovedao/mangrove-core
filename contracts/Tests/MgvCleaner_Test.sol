// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../periphery/MgvCleaner.sol";

import "../MgvLib.sol";
import "hardhat/console.sol";
import "@giry/hardhat-test-solidity/test.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
// import "./Agents/TestMoriartyMaker.sol";
import "./Agents/TestTaker.sol";

// In these tests, the testing contract is the market maker.
contract MgvCleaner_Test is HasMgvEvents {
  receive() external payable {}

  AbstractMangrove mgv;
  TestTaker tkr;
  TestMaker mkr;
  address outbound;
  address inbound;
  MgvCleaner cleaner;

  function a_beforeAll() public {
    TestToken Outbound = TokenSetup.setup("A", "$A");
    TestToken Inbound = TokenSetup.setup("B", "$B");
    outbound = address(Outbound);
    inbound = address(Inbound);
    mgv = MgvSetup.setup(Outbound, Inbound);
    mkr = MakerSetup.setup(mgv, outbound, inbound);
    cleaner = new MgvCleaner(mgv);

    address(mkr).transfer(10 ether);

    mkr.provisionMgv(5 ether);

    Inbound.mint(address(this), 2 ether);
    Outbound.mint(address(mkr), 1 ether);

    Outbound.approve(address(mgv), 1 ether);
    Inbound.approve(address(mgv), 1 ether);
    mkr.approveMgv(Outbound, 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "MgvCleaner_Test");
    Display.register(outbound, "$A");
    Display.register(inbound, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(mkr), "maker[$A,$B]");
    Display.register(address(cleaner), "cleaner");
  }

  /* # Test Config */

  function single_failing_offer_test() public {
    mgv.approve(outbound, inbound, address(cleaner), type(uint).max);

    mkr.shouldFail(true);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    uint oldBal = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];
    cleaner.collect(outbound, inbound, targets, true);

    uint newBal = address(this).balance;

    TestEvents.more(newBal, oldBal, "balance should have increased");
  }

  function mult_failing_offer_test() public {
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

    TestEvents.more(newBal, oldBal, "balance should have increased");
  }

  function no_fail_no_cleaning_test() public {
    mgv.approve(outbound, inbound, address(cleaner), type(uint).max);
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    uint oldBal = address(this).balance;

    uint[4][] memory targets = new uint[4][](1);
    targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];
    try cleaner.collect(outbound, inbound, targets, true) {
      TestEvents.fail("collect should fail since offer succeeded");
    } catch Error(string memory reason) {
      TestEvents.eq(
        "mgvCleaner/anOfferDidNotFail",
        reason,
        "fail should be due to offer execution succeeding"
      );
    }

    uint newBal = address(this).balance;

    TestEvents.eq(newBal, oldBal, "balance should be the same");
  }

  // For now there is no need to approve
  // function no_approve_no_cleaning_test() public {
  //   uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000,0);

  //   uint[4][] memory targets = new uint[4][](1);
  //   targets[0] = [ofr, 1 ether, 1 ether, type(uint).max];

  //   try cleaner.collect(outbound, inbound,targets,true) {
  //     TestEvents.fail("collect should fail since cleaner was not approved");
  //   } catch Error(string memory reason) {
  //     TestEvents.eq("mgv/lowAllowance",reason,"Fail should be due to no allowance");
  //   }
  // }
}
