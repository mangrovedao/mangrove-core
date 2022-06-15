// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/tools/MangroveTest.sol";

import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

contract Oracle {
  function read(
    address, /*base*/
    address /*quote*/
  ) external pure returns (uint, uint) {
    return (23, 2);
  }
}

// In these tests, the testing contract is the market maker.
contract MgvReaderTest is MangroveTest {
  //receive() external payable {}

  AbstractMangrove mgv;
  TestMaker mkr;
  MgvReader reader;
  address base;
  address quote;
  Oracle oracle;

  function setUp() public {
    TestToken baseT = setupToken("A", "$A");
    TestToken quoteT = setupToken("B", "$B");
    oracle = new Oracle();

    base = address(baseT);
    quote = address(quoteT);
    mgv = setupMangrove(baseT, quoteT);
    mkr = setupMaker(mgv, base, quote);
    reader = new MgvReader(address(mgv));

    payable(mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    mkr.provisionMgv(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(mkr), 1 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);

    vm.label(msg.sender, "Test Runner");
    vm.label(address(this), "Gatekeeping_Test/maker");
    vm.label(base, "$A");
    vm.label(quote, "$B");
    vm.label(address(mgv), "mgv");
    vm.label(address(mkr), "maker[$A,$B]");
  }

  function test_read_packed() public {
    (
      uint currentId,
      uint[] memory offerIds,
      P.OfferStruct[] memory offers,
      P.OfferDetailStruct[] memory details
    ) = reader.offerList(base, quote, 0, 50);

    assertEq(offerIds.length, 0, "ids: wrong length on 2elem");
    assertEq(offers.length, 0, "offers: wrong length on 1elem");
    assertEq(details.length, 0, "details: wrong length on 1elem");
    // test 1 elem
    mkr.newOffer(1 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );

    assertEq(offerIds.length, 1, "ids: wrong length on 1elem");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 2 elem
    mkr.newOffer(0.9 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );

    assertEq(offerIds.length, 2, "ids: wrong length on 2elem");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test 2 elem read from elem 1
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      1,
      50
    );
    assertEq(offerIds.length, 1, "ids: wrong length 2elem start from id 1");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 3 elem read in chunks of 2
    mkr.newOffer(0.8 ether, 1 ether, 10_000, 0);
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      2
    );
    assertEq(offerIds.length, 2, "ids: wrong length on 3elem chunk size 2");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test offer order
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );
    assertEq(offers[0].wants, 0.8 ether, "wrong wants for offers[0]");
    assertEq(offers[1].wants, 0.9 ether, "wrong wants for offers[0]");
    assertEq(offers[2].wants, 1 ether, "wrong wants for offers[0]");
  }

  function test_returns_zero_on_nonexisting_offer() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    mkr.retractOffer(ofr);
    (, uint[] memory offerIds, , ) = reader.offerList(base, quote, ofr, 50);
    assertEq(
      offerIds.length,
      0,
      "should have 0 offers since starting point is out of the book"
    );
  }

  function test_no_wasted_time() public {
    reader.offerList(base, quote, 0, 50); // warming up caches

    uint g = gasleft();
    reader.offerList(base, quote, 0, 50);
    uint used1 = g - gasleft();

    g = gasleft();
    reader.offerList(base, quote, 0, 50000000);
    uint used2 = g - gasleft();

    assertEq(
      used1,
      used2,
      "gas spent should not depend on maxOffers when offers length < maxOffers"
    );
  }

  function test_correct_endpoints_0() public {
    uint startId;
    uint length;
    (startId, length) = reader.offerListEndPoints(base, quote, 0, 100000);
    assertEq(startId, 0, "0.0 wrong startId");
    assertEq(length, 0, "0.0 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 32, 100000);
    assertEq(startId, 0, "0.1 wrong startId");
    assertEq(length, 0, "0.1 wrong length");
  }

  function test_correct_endpoints_1() public {
    uint startId;
    uint length;
    uint ofr;
    ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    (startId, length) = reader.offerListEndPoints(base, quote, 0, 0);
    assertEq(startId, 1, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 1, 1);
    assertEq(startId, 1, "1.1 wrong startId");
    assertEq(length, 1, "1.1 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 1, 1321);
    assertEq(startId, 1, "1.2 wrong startId");
    assertEq(length, 1, "1.2 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 2, 12);
    assertEq(startId, 0, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");
  }

  function try_provision() internal {
    uint prov = reader.getProvision(base, quote, 0, 0);
    uint bal1 = mgv.balanceOf(address(mkr));
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    uint bal2 = mgv.balanceOf(address(mkr));
    assertEq(bal1 - bal2, prov, "provision computation is wrong");
  }

  function test_provision_0() public {
    try_provision();
  }

  function test_provision_1() public {
    mgv.setGasbase(base, quote, 17_000);
    try_provision();
  }

  function test_provision_oracle() public {
    mgv.setMonitor(address(oracle));
    mgv.setUseOracle(true);
    try_provision();
  }
}
