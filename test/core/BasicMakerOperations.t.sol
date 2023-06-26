// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

contract BasicMakerOperationsTest is MangroveTest {
  TestMaker mkr;
  TestMaker mkr2;
  TestTaker tkr;

  function setUp() public override {
    super.setUp();

    mkr = setupMaker($(base), $(quote), "maker");
    mkr2 = setupMaker($(base), $(quote), "maker2");
    tkr = setupTaker($(base), $(quote), "taker");

    mkr.approveMgv(base, 10 ether);
    mkr2.approveMgv(base, 10 ether);

    deal($(quote), address(tkr), 1 ether);
    tkr.approveMgv(quote, 1 ether);
  }

  function test_basic_newOffer_sets_best() public {
    mkr.provisionMgv(1 ether);
    uint ofr = mkr.newOffer(0.1 ether, 0.05 ether, 200_000, 0);
    assertEq(mgv.best($(base), $(quote)), ofr);
  }
}
