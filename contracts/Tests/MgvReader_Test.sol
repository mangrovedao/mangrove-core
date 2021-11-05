// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;

import "../AbstractMangrove.sol";
import "../MgvLib.sol";
import "hardhat/console.sol";
import "@giry/hardhat-test-solidity/test.sol";

import "./Toolbox/TestUtils.sol";

import "./Agents/TestToken.sol";
import "./Agents/TestMaker.sol";
import "./Agents/MakerDeployer.sol";
import "./Agents/TestTaker.sol";
import {MgvReader} from "../periphery/MgvReader.sol";

contract Oracle {
  function read(address base, address quote)
    external
    view
    returns (uint, uint)
  {
    return (23, 2);
  }
}

// In these tests, the testing contract is the market maker.
contract MgvReader_Test is HasMgvEvents {
  receive() external payable {}

  AbstractMangrove mgv;
  TestMaker mkr;
  MgvReader reader;
  address base;
  address quote;
  Oracle oracle;

  function a_beforeAll() public {
    TestToken baseT = TokenSetup.setup("A", "$A");
    TestToken quoteT = TokenSetup.setup("B", "$B");
    oracle = new Oracle();

    base = address(baseT);
    quote = address(quoteT);
    mgv = MgvSetup.setup(baseT, quoteT);
    mkr = MakerSetup.setup(mgv, base, quote);
    reader = new MgvReader(address(mgv));

    address(mkr).transfer(10 ether);

    bool noRevert;
    (noRevert, ) = address(mgv).call{value: 10 ether}("");

    mkr.provisionMgv(5 ether);

    baseT.mint(address(this), 2 ether);
    quoteT.mint(address(mkr), 1 ether);

    baseT.approve(address(mgv), 1 ether);
    quoteT.approve(address(mgv), 1 ether);

    Display.register(msg.sender, "Test Runner");
    Display.register(address(this), "Gatekeeping_Test/maker");
    Display.register(base, "$A");
    Display.register(quote, "$B");
    Display.register(address(mgv), "mgv");
    Display.register(address(mkr), "maker[$A,$B]");
  }

  function read_packed_test() public {
    (
      uint currentId,
      uint[] memory offerIds,
      ML.Offer[] memory offers,
      ML.OfferDetail[] memory details
    ) = reader.offerList(base, quote, 0, 50);

    TestEvents.eq(offerIds.length, 0, "ids: wrong length on 2elem");
    TestEvents.eq(offers.length, 0, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 0, "details: wrong length on 1elem");
    // test 1 elem
    mkr.newOffer(1 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );

    TestEvents.eq(offerIds.length, 1, "ids: wrong length on 1elem");
    TestEvents.eq(offers.length, 1, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 1, "details: wrong length on 1elem");

    // test 2 elem
    mkr.newOffer(0.9 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );

    TestEvents.eq(offerIds.length, 2, "ids: wrong length on 2elem");
    TestEvents.eq(offers.length, 2, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 2, "details: wrong length on 1elem");

    // test 2 elem read from elem 1
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      1,
      50
    );
    TestEvents.eq(
      offerIds.length,
      1,
      "ids: wrong length 2elem start from id 1"
    );
    TestEvents.eq(offers.length, 1, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 1, "details: wrong length on 1elem");

    // test 3 elem read in chunks of 2
    mkr.newOffer(0.8 ether, 1 ether, 10_000, 0);
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      2
    );
    TestEvents.eq(
      offerIds.length,
      2,
      "ids: wrong length on 3elem chunk size 2"
    );
    TestEvents.eq(offers.length, 2, "offers: wrong length on 1elem");
    TestEvents.eq(details.length, 2, "details: wrong length on 1elem");

    // test offer order
    (currentId, offerIds, offers, details) = reader.offerList(
      base,
      quote,
      0,
      50
    );
    TestEvents.eq(offers[0].wants, 0.8 ether, "wrong wants for offers[0]");
    TestEvents.eq(offers[1].wants, 0.9 ether, "wrong wants for offers[0]");
    TestEvents.eq(offers[2].wants, 1 ether, "wrong wants for offers[0]");
  }

  function returns_zero_on_nonexisting_offer_test() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    mkr.retractOffer(ofr);
    (, uint[] memory offerIds, , ) = reader.offerList(base, quote, ofr, 50);
    TestEvents.eq(
      offerIds.length,
      0,
      "should have 0 offers since starting point is out of the book"
    );
  }

  function no_wasted_time_test() public {
    reader.offerList(base, quote, 0, 50); // warming up caches

    uint g = gasleft();
    reader.offerList(base, quote, 0, 50);
    uint used1 = g - gasleft();

    g = gasleft();
    reader.offerList(base, quote, 0, 50000000);
    uint used2 = g - gasleft();

    TestEvents.eq(
      used1,
      used2,
      "gas spent should not depend on maxOffers when offers length < maxOffers"
    );
  }

  function correct_endpoints_0_test() public {
    uint startId;
    uint length;
    (startId, length) = reader.offerListEndPoints(base, quote, 0, 100000);
    TestEvents.eq(startId, 0, "0.0 wrong startId");
    TestEvents.eq(length, 0, "0.0 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 32, 100000);
    TestEvents.eq(startId, 0, "0.1 wrong startId");
    TestEvents.eq(length, 0, "0.1 wrong length");
  }

  function correct_endpoints_1_test() public {
    uint startId;
    uint length;
    uint ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    (startId, length) = reader.offerListEndPoints(base, quote, 0, 0);
    TestEvents.eq(startId, 1, "1.0 wrong startId");
    TestEvents.eq(length, 0, "1.0 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 1, 1);
    TestEvents.eq(startId, 1, "1.1 wrong startId");
    TestEvents.eq(length, 1, "1.1 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 1, 1321);
    TestEvents.eq(startId, 1, "1.2 wrong startId");
    TestEvents.eq(length, 1, "1.2 wrong length");

    (startId, length) = reader.offerListEndPoints(base, quote, 2, 12);
    TestEvents.eq(startId, 0, "1.0 wrong startId");
    TestEvents.eq(length, 0, "1.0 wrong length");
  }

  function try_provision() internal {
    uint prov = reader.getProvision(base, quote, 0, 0);
    uint bal1 = mgv.balanceOf(address(mkr));
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    uint bal2 = mgv.balanceOf(address(mkr));
    TestEvents.eq(bal1 - bal2, prov, "provision computation is wrong");
  }

  function provision_0_test() public {
    try_provision();
  }

  function provision_1_test() public {
    mgv.setGasbase(base, quote, 17_000, 280_000);
    try_provision();
  }

  function provision_oracle_test() public {
    mgv.setMonitor(address(oracle));
    mgv.setUseOracle(true);
    try_provision();
  }
}
