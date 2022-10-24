// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";

import {MgvReader, VolumeData} from "src/periphery/MgvReader.sol";
import {MgvStructs} from "src/MgvLib.sol";

// In these tests, the testing contract is the market maker.
contract MgvReaderTest is MangroveTest {
  TestMaker mkr;
  address oracle;

  function setUp() public override {
    super.setUp();

    mkr = setupMaker($(base), $(quote), "maker");
    mkr.provisionMgv(5 ether);

    deal($(quote), address(mkr), 1 ether);
  }

  function test_read_packed() public {
    (
      uint currentId,
      uint[] memory offerIds,
      MgvStructs.OfferUnpacked[] memory offers,
      MgvStructs.OfferDetailUnpacked[] memory details
    ) = reader.offerList($(base), $(quote), 0, 50);

    assertEq(offerIds.length, 0, "ids: wrong length on 2elem");
    assertEq(offers.length, 0, "offers: wrong length on 1elem");
    assertEq(details.length, 0, "details: wrong length on 1elem");
    // test 1 elem
    mkr.newOffer(1 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList($(base), $(quote), 0, 50);

    assertEq(offerIds.length, 1, "ids: wrong length on 1elem");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 2 elem
    mkr.newOffer(0.9 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList($(base), $(quote), 0, 50);

    assertEq(offerIds.length, 2, "ids: wrong length on 2elem");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test 2 elem read from elem 1
    (currentId, offerIds, offers, details) = reader.offerList($(base), $(quote), 1, 50);
    assertEq(offerIds.length, 1, "ids: wrong length 2elem start from id 1");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 3 elem read in chunks of 2
    mkr.newOffer(0.8 ether, 1 ether, 10_000, 0);
    (currentId, offerIds, offers, details) = reader.offerList($(base), $(quote), 0, 2);
    assertEq(offerIds.length, 2, "ids: wrong length on 3elem chunk size 2");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test offer order
    (currentId, offerIds, offers, details) = reader.offerList($(base), $(quote), 0, 50);
    assertEq(offers[0].wants, 0.8 ether, "wrong wants for offers[0]");
    assertEq(offers[1].wants, 0.9 ether, "wrong wants for offers[0]");
    assertEq(offers[2].wants, 1 ether, "wrong wants for offers[0]");
  }

  function test_returns_zero_on_nonexisting_offer() public {
    uint ofr = mkr.newOffer(1 ether, 1 ether, 10_000, 0);
    mkr.retractOffer(ofr);
    (, uint[] memory offerIds,,) = reader.offerList($(base), $(quote), ofr, 50);
    assertEq(offerIds.length, 0, "should have 0 offers since starting point is out of the book");
  }

  function test_no_wasted_time() public {
    reader.offerList($(base), $(quote), 0, 50); // warming up caches

    uint g = gasleft();
    reader.offerList($(base), $(quote), 0, 50);
    uint used1 = g - gasleft();

    g = gasleft();
    reader.offerList($(base), $(quote), 0, 50000000);
    uint used2 = g - gasleft();

    assertEq(used1, used2, "gas spent should not depend on maxOffers when offers length < maxOffers");
  }

  function test_correct_endpoints_0() public {
    uint startId;
    uint length;
    (startId, length) = reader.offerListEndPoints($(base), $(quote), 0, 100000);
    assertEq(startId, 0, "0.0 wrong startId");
    assertEq(length, 0, "0.0 wrong length");

    (startId, length) = reader.offerListEndPoints($(base), $(quote), 32, 100000);
    assertEq(startId, 0, "0.1 wrong startId");
    assertEq(length, 0, "0.1 wrong length");
  }

  function test_correct_endpoints_1() public {
    uint startId;
    uint length;
    uint ofr;
    ofr = mkr.newOffer(1 ether, 1 ether, 50_000, 0);

    (startId, length) = reader.offerListEndPoints($(base), $(quote), 0, 0);
    assertEq(startId, 1, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");

    (startId, length) = reader.offerListEndPoints($(base), $(quote), 1, 1);
    assertEq(startId, 1, "1.1 wrong startId");
    assertEq(length, 1, "1.1 wrong length");

    (startId, length) = reader.offerListEndPoints($(base), $(quote), 1, 1321);
    assertEq(startId, 1, "1.2 wrong startId");
    assertEq(length, 1, "1.2 wrong length");

    (startId, length) = reader.offerListEndPoints($(base), $(quote), 2, 12);
    assertEq(startId, 0, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");
  }

  function try_provision() internal {
    uint prov = reader.getProvision($(base), $(quote), 0, 0);
    uint bal1 = mgv.balanceOf(address(mkr));
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    uint bal2 = mgv.balanceOf(address(mkr));
    assertEq(bal1 - bal2, prov, "provision computation is wrong");
  }

  function test_provision_0() public {
    try_provision();
  }

  function test_provision_1() public {
    mgv.setGasbase($(base), $(quote), 17_000);
    try_provision();
  }

  function test_provision_oracle() public {
    oracle = freshAddress("oracle");
    vm.mockCall(oracle, bytes(""), abi.encode(0, 0));
    mgv.setMonitor(oracle);
    mgv.setUseOracle(true);
    try_provision();
  }

  function test_marketOrder_0() public {
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 1 ether, 1 ether, true);

    assertEq(vd.length, 0);
  }

  function test_marketOrder_no_match() public {
    mkr.newOffer(1.1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 1 ether, 1 ether, true);

    assertEq(vd.length, 0);
  }

  function test_marketOrder_partial_fillWants() public {
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 0.8 ether, 0.9 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 0.8 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 0.8 ether, "bad totalGave");
  }

  function test_marketOrder_partial_noFillWants() public {
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 0.3 ether, 0.9 ether, false);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 0.9 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 0.9 ether, "bad totalGave");
  }

  function test_marketOrder_full_fillWants() public {
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 1 ether, 1 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 1 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 1 ether, "bad totalGave");
  }

  function test_marketOrder_full_noFillWants() public {
    mkr.newOffer(1 ether, 1.1 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 0.5 ether, 1 ether, false);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 1.1 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 1 ether, "bad totalGave");
  }

  function test_marketOrder_partial_due_to_price_fillWants() public {
    mkr.newOffer(1 ether, 1 ether, 0, 0);
    mkr.newOffer(1 ether, 0.8 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 1.4 ether, 1.5 ether, true);
    assertEq(vd.length, 2, "bad vd length");
    assertEq(vd[0].totalGot, 1 ether, "bad totalGot[0]");
    assertEq(vd[0].totalGave, 1 ether, "bad totalGave[0]");
    assertEq(vd[1].totalGot, 1.4 ether, "bad totalGot[1]");
    assertEq(vd[1].totalGave, 1.5 ether, "bad totalGave[1]");
  }

  function test_marketOrder_gas() public {
    mkr.newOffer(1 ether, 1 ether, 214_000, 0);
    mkr.newOffer(1 ether, 1 ether, 216_000, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 1.4 ether, 1.5 ether, true);
    assertEq(vd.length, 2, "bad vd length");
    assertEq(vd[0].totalGasreq, 214_000, "bad totalGasreq[0]");
    assertEq(vd[1].totalGasreq, 214_000 + 216_000, "bad totalGasreq[1]");
  }

  function test_marketOrder_fee(uint8 fee) public {
    vm.assume(fee <= 500);
    mgv.setFee($(base), $(quote), fee);
    mkr.newOffer(0.3 ether, 0.3 ether, 0, 0);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), 0.3 ether, 0.3 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, reader.minusFee($(base), $(quote), 0.3 ether), "bad totalGot");
    assertEq(vd[0].totalGave, 0.3 ether, "bad totalGave");
  }

  function prepareOffers(uint numOffers) internal returns (uint) {
    uint unitVolume = 0.1 ether;
    for (uint i = 0; i < numOffers; i++) {
      mkr.newOffer(unitVolume, unitVolume, 200_000, 0);
    }
    return unitVolume * numOffers;
  }

  function test_marketOrder_volumeData_length(uint8 numOffers) public {
    vm.assume(numOffers < 12);
    prepareOffers(numOffers);
    VolumeData[] memory vd = reader.marketOrder($(base), $(quote), numOffers * 0.1 ether, numOffers * 0.1 ether, true);
    assertEq(vd.length, numOffers, "bad vd length");
    for (uint i = 0; i < numOffers; i++) {
      assertEq(vd[i].totalGot, (i + 1) * 0.1 ether, string.concat("bad totalGot ", vm.toString(i)));
      assertEq(vd[i].totalGave, (i + 1) * 0.1 ether, string.concat("bad totalGave", vm.toString(i)));
    }
  }

  function marketOrderMaybeSimThenReal(bool doSim, uint numOffers) internal {
    uint sumGas;
    deal($(base), address(mkr), 10 ether);
    mkr.approveMgv(base, 10 ether);
    deal($(quote), address(this), 10 ether);
    uint volume = prepareOffers(numOffers);
    if (doSim) {
      _gas();
      reader.marketOrder($(base), $(quote), volume, volume, true, true);
      sumGas += gas_("simulation");
    }
    _gas();
    mgv.marketOrder($(base), $(quote), volume, volume, true);
    sumGas += gas_("real");
    console.log("Total: %s", sumGas);
  }

  function test_marketOrder_gas_cost_1_with_sim() public {
    marketOrderMaybeSimThenReal(true, 1);
  }

  function test_marketOrder_gas_cost_1_real() public {
    marketOrderMaybeSimThenReal(false, 1);
  }

  function test_marketOrder_gas_cost_5_with_sim() public {
    marketOrderMaybeSimThenReal(true, 5);
  }

  function test_marketOrder_gas_cost_5_real() public {
    marketOrderMaybeSimThenReal(false, 5);
  }

  function test_marketOrder_gas_cost_15_with_sim() public {
    marketOrderMaybeSimThenReal(true, 15);
  }

  function test_marketOrder_gas_cost_15_real() public {
    marketOrderMaybeSimThenReal(false, 15);
  }
}

function printVolumeData(VolumeData[] memory vd) view {
  console.log("====================");
  console.log("Volume Data size: %s", vd.length);
  for (uint i = 0; i < vd.length; i++) {
    console.log("got %s", vd[i].totalGot);
    console.log("gave %s", vd[i].totalGave);
    console.log("___________");
  }
  console.log("====================");
}
