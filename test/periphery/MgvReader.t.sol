// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.10;

import "@mgv/test/lib/MangroveTest.sol";

import "@mgv/src/periphery/MgvReader.sol";
import "@mgv/src/core/MgvLib.sol";
import {stdError} from "@mgv/forge-std/StdError.sol";

// In these tests, the testing contract is the market maker.
contract MgvReaderTest is MangroveTest {
  TestMaker mkr;
  address oracle;

  function setUp() public override {
    super.setUp();

    mkr = setupMaker(olKey, "maker");
    mkr.provisionMgv(5 ether);

    deal($(quote), address(mkr), 1 ether);
  }

  function test_read_packed() public {
    (uint currentId, uint[] memory offerIds, OfferUnpacked[] memory offers, OfferDetailUnpacked[] memory details) =
      reader.offerList(olKey, 0, 50);

    assertEq(offerIds.length, 0, "ids: wrong length on 2elem");
    assertEq(offers.length, 0, "offers: wrong length on 1elem");
    assertEq(details.length, 0, "details: wrong length on 1elem");
    // test 1 elem
    mkr.newOfferByVolume(1 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(olKey, 0, 50);

    assertEq(offerIds.length, 1, "ids: wrong length on 1elem");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 2 elem
    mkr.newOfferByVolume(0.9 ether, 1 ether, 10_000, 0);

    (currentId, offerIds, offers, details) = reader.offerList(olKey, 0, 50);

    assertEq(offerIds.length, 2, "ids: wrong length on 2elem");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test 2 elem read from elem 1
    (currentId, offerIds, offers, details) = reader.offerList(olKey, 1, 50);
    assertEq(offerIds.length, 1, "ids: wrong length 2elem start from id 1");
    assertEq(offers.length, 1, "offers: wrong length on 1elem");
    assertEq(details.length, 1, "details: wrong length on 1elem");

    // test 3 elem read in chunks of 2
    mkr.newOfferByVolume(0.8 ether, 1 ether, 10_000, 0);
    (currentId, offerIds, offers, details) = reader.offerList(olKey, 0, 2);
    assertEq(offerIds.length, 2, "ids: wrong length on 3elem chunk size 2");
    assertEq(offers.length, 2, "offers: wrong length on 1elem");
    assertEq(details.length, 2, "details: wrong length on 1elem");

    // test offer order
    (currentId, offerIds, offers, details) = reader.offerList(olKey, 0, 50);
    assertApproxEqRel(offers[0].wants(), 0.8 ether, relError(10), "wrong wants for offers[0]");
    assertApproxEqRel(offers[1].wants(), 0.9 ether, relError(10), "wrong wants for offers[0]");
    assertApproxEqRel(offers[2].wants(), 1 ether, relError(10), "wrong wants for offers[0]");
  }

  function test_returns_zero_on_nonexisting_offer() public {
    uint ofr = mkr.newOfferByVolume(1 ether, 1 ether, 10_000, 0);
    mkr.retractOffer(ofr);
    (, uint[] memory offerIds,,) = reader.offerList(olKey, ofr, 50);
    assertEq(offerIds.length, 0, "should have 0 offers since starting point is out of the book");
  }

  function test_no_wasted_time() public {
    reader.offerList(olKey, 0, 50); // warming up caches

    uint g = gasleft();
    reader.offerList(olKey, 0, 50);
    uint used1 = g - gasleft();

    g = gasleft();
    reader.offerList(olKey, 0, 50000000);
    uint used2 = g - gasleft();

    assertEq(used1, used2, "gas spent should not depend on maxOffers when offers length < maxOffers");
  }

  function test_correct_endpoints_0() public {
    uint startId;
    uint length;
    (startId, length) = reader.offerListEndPoints(olKey, 0, 100000);
    assertEq(startId, 0, "0.0 wrong startId");
    assertEq(length, 0, "0.0 wrong length");

    (startId, length) = reader.offerListEndPoints(olKey, 32, 100000);
    assertEq(startId, 0, "0.1 wrong startId");
    assertEq(length, 0, "0.1 wrong length");
  }

  function test_correct_endpoints_1() public {
    uint startId;
    uint length;
    uint ofr;
    ofr = mkr.newOfferByVolume(1 ether, 1 ether, 50_000, 0);

    (startId, length) = reader.offerListEndPoints(olKey, 0, 0);
    assertEq(startId, 1, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");

    (startId, length) = reader.offerListEndPoints(olKey, 1, 1);
    assertEq(startId, 1, "1.1 wrong startId");
    assertEq(length, 1, "1.1 wrong length");

    (startId, length) = reader.offerListEndPoints(olKey, 1, 1321);
    assertEq(startId, 1, "1.2 wrong startId");
    assertEq(length, 1, "1.2 wrong length");

    (startId, length) = reader.offerListEndPoints(olKey, 2, 12);
    assertEq(startId, 0, "1.0 wrong startId");
    assertEq(length, 0, "1.0 wrong length");
  }

  function try_provision() internal {
    uint prov = reader.getProvision(olKey, 0, 0);
    uint bal1 = mgv.balanceOf(address(mkr));
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    uint bal2 = mgv.balanceOf(address(mkr));
    assertEq(bal1 - bal2, prov, "provision computation is wrong");
  }

  function test_provision_0() public {
    try_provision();
  }

  function test_provision_1() public {
    mgv.setGasbase(olKey, 17_000);
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
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 1 ether, 1 ether, true);

    assertEq(vd.length, 0);
  }

  function test_marketOrder_no_match() public {
    mkr.newOfferByVolume(1.1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 1 ether, 1 ether, true);

    assertEq(vd.length, 0);
  }

  function test_marketOrder_partial_fillWants() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 0.8 ether, 0.9 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 0.8 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 0.8 ether, "bad totalGave");
  }

  function test_marketOrder_partial_noFillWants() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 0.3 ether, 0.9 ether, false);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 0.9 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 0.9 ether, "bad totalGave");
  }

  function test_marketOrder_full_fillWants() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 1 ether, 1 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 1 ether, "bad totalGot");
    assertEq(vd[0].totalGave, 1 ether, "bad totalGave");
  }

  function test_marketOrder_full_noFillWants() public {
    mkr.newOfferByVolume(1 ether, 1.1 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 0.5 ether, 1 ether, false);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, 1.1 ether, "bad totalGot");
    assertApproxEqRel(vd[0].totalGave, 1 ether, relError(10), "bad totalGave");
  }

  function test_marketOrder_multiple_offers_last_partial_fillWants() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 0, 0);
    mkr.newOfferByVolume(1 ether, 0.8 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 1.4 ether, 1.8 ether, true);
    assertEq(vd.length, 2, "bad vd length");
    assertEq(vd[0].totalGot, 1 ether, "bad totalGot[0]");
    assertEq(vd[0].totalGave, 1 ether, "bad totalGave[0]");
    assertEq(vd[1].totalGot, 1.4 ether, "bad totalGot[1]");
    assertApproxEqRel(vd[1].totalGave, 1.5 ether, relError(10), "bad totalGave[1]");
  }

  function test_marketOrder_gas() public {
    mkr.newOfferByVolume(1 ether, 1 ether, 214_000, 0);
    mkr.newOfferByVolume(1 ether, 1 ether, 216_000, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 1.4 ether, 1.5 ether, true);
    assertEq(vd.length, 2, "bad vd length");
    assertEq(vd[0].totalGasreq, 214_000, "bad totalGasreq[0]");
    assertEq(vd[1].totalGasreq, 214_000 + 216_000, "bad totalGasreq[1]");
  }

  function test_marketOrder_fee(uint8 fee) public {
    vm.assume(fee <= 500);
    mgv.setFee(olKey, fee);
    mkr.newOfferByVolume(0.3 ether, 0.3 ether, 0, 0);
    VolumeData[] memory vd = reader.simulateMarketOrderByVolume(olKey, 0.3 ether, 0.3 ether, true);
    assertEq(vd.length, 1, "bad vd length");
    assertEq(vd[0].totalGot, reader.minusFee(olKey, 0.3 ether), "bad totalGot");
    assertEq(vd[0].totalGave, 0.3 ether, "bad totalGave");
  }

  function prepareOffers(uint numOffers) internal returns (uint) {
    uint unitVolume = 0.1 ether;
    for (uint i = 0; i < numOffers; i++) {
      mkr.newOfferByVolume(unitVolume, unitVolume, 200_000, 0);
    }
    return unitVolume * numOffers;
  }

  function test_marketOrder_volumeData_length(uint numOffers) public {
    numOffers = bound(numOffers, 0, 11);
    prepareOffers(numOffers);
    VolumeData[] memory vd =
      reader.simulateMarketOrderByVolume(olKey, numOffers * 0.1 ether, numOffers * 0.1 ether, true);
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
      reader.simulateMarketOrderByVolume(olKey, volume, volume, true, true);
      sumGas += gas_("simulation");
    }
    _gas();
    mgv.marketOrderByVolume(olKey, volume, volume, true);
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

  /* Market tracking test */
  /* Utility stuff */
  Market[] expectedMarkets;
  bool[2][] expectedActives;

  function resetExpectedMarkets() internal {
    expectedMarkets = new Market[](0);
    expectedActives = new bool[2][](0);
  }

  function pushExpectedMarket(Market memory market, bool activeAB, bool activeBA) internal {
    address tkn0 = market.tkn0;
    order(market);
    expectedMarkets.push(market);
    expectedActives.push(tkn0 == market.tkn0 ? [activeAB, activeBA] : [activeBA, activeAB]);
  }

  function checkMarkets() internal {
    (Market[] memory actualMarkets, MarketConfig[] memory config) = reader.openMarkets();
    assertEq(actualMarkets.length, expectedMarkets.length, "markets lengths differ");
    for (uint i = 0; i < actualMarkets.length; i++) {
      string memory suffix = string.concat(": unexpected for market ", vm.toString(i));
      assertEq(actualMarkets[i].tkn0, expectedMarkets[i].tkn0, string.concat("token 0", suffix));
      assertEq(config[i].config01.active, expectedActives[i][0], string.concat("active 01", suffix));
      assertEq(actualMarkets[i].tkn1, expectedMarkets[i].tkn1, string.concat("token 1", suffix));
      assertEq(config[i].config10.active, expectedActives[i][1], string.concat("active 10", suffix));
    }
  }

  function assumeDifferentPairs(address tknA, address tknB, address tkn0, address tkn1) internal pure {
    (tknA, tknB) = order(tknA, tknB);
    (tkn0, tkn1) = order(tkn0, tkn1);
    vm.assume(tknA != tkn0 || tknB != tkn1);
  }

  // low-level market activation
  function activateOfferList(OLKey memory olKey) internal {
    mgv.activate(olKey, 0, 0, 0);
  }

  function activateMarket(Market memory market) internal {
    activateOfferList(toOLKey(market));
    activateOfferList(toOLKey(flipped(market)));
  }

  /* Tests */
  function test_initial_market_state_fuzz(Market memory market) public {
    assertEq(reader.isMarketOpen(market), false);
  }

  function test_initial_market_state_length() public {
    assertEq(reader.numOpenMarkets(), 0);
    checkMarkets();
  }

  function test_simple_add(Market memory market) public {
    // order(market);
    activateMarket(market);
    reader.updateMarket(market);
    assertEq(reader.numOpenMarkets(), 1, "initial length wrong");
    assertEq(reader.isMarketOpen(market), true, "open failed");
    pushExpectedMarket(market, true, true);
    checkMarkets();
  }

  function test_multi_add_1(Market memory mktA, Market memory mktB) public {
    // address tknA, address tknB, address tkn0, address tkn1) public {
    activateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    assertEq(reader.numOpenMarkets(), 2, "length wrong");
    assertEq(reader.isMarketOpen(mktA), true, "open failed for tkn0,tkn1");
    assertEq(reader.isMarketOpen(mktB), true, "open failed for tkn0,tkn1");
    pushExpectedMarket(mktA, true, true);
    pushExpectedMarket(mktB, true, true);
    checkMarkets();
  }

  // function test_multi_add_2(address tknA, address tknB, address tkn0, address tkn1) public {
  function test_multi_add_2(Market memory mktA, Market memory mktB) public {
    activateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    assertEq(reader.numOpenMarkets(), 2, "length wrong");
    assertEq(reader.isMarketOpen(mktA), true, "open failed for tkn0,tkn1");
    assertEq(reader.isMarketOpen(mktB), true, "open failed for tkn0,tkn1");
    pushExpectedMarket(mktA, true, true);
    pushExpectedMarket(mktB, true, true);
    checkMarkets();
  }

  function test_multi_add_triangle(address tkn0, address tkn1, address tkn2, uint tickSpacing) public {
    Market memory mktA = Market(tkn0, tkn1, tickSpacing);
    Market memory mktB = Market(tkn1, tkn2, tickSpacing);
    Market memory mktC = Market(tkn2, tkn0, tickSpacing);
    activateMarket(mktA);
    activateMarket(mktB);
    activateMarket(mktC);
    reader.updateMarket(mktC);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    assertEq(reader.isMarketOpen(mktA), true, "open failed for tkn0,tkn1");
    assertEq(reader.isMarketOpen(mktB), true, "open failed for tkn1,tkn2");
    assertEq(reader.isMarketOpen(mktC), true, "open failed for tkn2,tkn0");
    pushExpectedMarket(mktC, true, true);
    if (tkn1 != tkn2) {
      pushExpectedMarket(mktA, true, true);
    }
    if (tkn1 != tkn0 && tkn2 != tkn0) {
      pushExpectedMarket(mktB, true, true);
    }
    checkMarkets();
  }

  function test_no_double_add(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    reader.updateMarket(market);
    assertEq(reader.numOpenMarkets(), 1, "length should not have changed");
    assertEq(reader.isMarketOpen(market), true, "open status should not have changed");
    pushExpectedMarket(market, true, true);
    checkMarkets();
  }

  function test_no_double_add_with_swap(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    reader.updateMarket(market);
    assertEq(reader.numOpenMarkets(), 1, "length should not have changed");
    assertEq(reader.isMarketOpen(market), true, "open status should not have changed");
    pushExpectedMarket(market, true, true);
    checkMarkets();
  }

  function test_remove(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(market));
    mgv.deactivate(toOLKey(flipped(market)));
    reader.updateMarket(market);
    assertEq(reader.numOpenMarkets(), 0, "wrong length");
    assertEq(reader.isMarketOpen(market), false, "status should be closed");
    checkMarkets();
  }

  function test_add_partial(Market memory market) public {
    activateOfferList(toOLKey(market));
    reader.updateMarket(market);
    assertEq(reader.numOpenMarkets(), 1, "wrong length");
    assertEq(reader.isMarketOpen(market), true, "status should be closed");
    pushExpectedMarket(market, true, market.tkn0 == market.tkn1);
    checkMarkets();
  }

  function test_remove_partial_1(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(flipped(market)));
    reader.updateMarket(market);
    if (market.tkn0 == market.tkn1) {
      assertEq(reader.numOpenMarkets(), 0, "wrong length");
      assertEq(reader.isMarketOpen(market), false, "status should be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 1, "wrong length");
      assertEq(reader.isMarketOpen(market), true, "status should be closed");
      pushExpectedMarket(market, true, false);
    }
    checkMarkets();
  }

  function test_remove_partial_2(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(flipped(market)));
    reader.updateMarket(flipped(market));
    if (market.tkn0 == market.tkn1) {
      assertEq(reader.numOpenMarkets(), 0, "wrong length");
      assertEq(reader.isMarketOpen(market), false, "status should be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 1, "wrong length");
      assertEq(reader.isMarketOpen(market), true, "status should be closed");
      pushExpectedMarket(market, true, false);
    }
    checkMarkets();
  }

  function test_no_double_remove(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(flipped(market)));
    reader.updateMarket(market);
    reader.updateMarket(market);
    if (market.tkn0 == market.tkn1) {
      assertEq(reader.numOpenMarkets(), 0, "length should still be 0");
      assertEq(reader.isMarketOpen(market), false, "status should still be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 1, "length should still be 0");
      assertEq(reader.isMarketOpen(market), true, "status should still be closed");
      pushExpectedMarket(market, true, false);
    }
    checkMarkets();
  }

  function test_no_double_remove_long(Market memory mktA, Market memory mktB) public {
    // address tknA, address tknB, address tkn0, address tkn1) public {
    assumeDifferentPairs(mktA.tkn0, mktA.tkn1, mktB.tkn0, mktB.tkn1);
    activateMarket(mktA);
    reader.updateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktB);
    mgv.deactivate(toOLKey(mktB));
    reader.updateMarket(mktB);
    reader.updateMarket(mktB);
    pushExpectedMarket(mktA, true, true);

    if (mktB.tkn0 == mktB.tkn1) {
      assertEq(reader.numOpenMarkets(), 1, "wrong length");
      assertEq(reader.isMarketOpen(mktB), false, "status should still be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 2, "wrong length");
      assertEq(reader.isMarketOpen(mktB), true, "status should still be closed");
      pushExpectedMarket(mktB, false, true);
    }

    checkMarkets();
  }

  function test_no_double_remove_swap(Market memory market) public {
    activateMarket(market);
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(market));
    reader.updateMarket(market);
    reader.updateMarket(flipped(market));

    if (market.tkn0 == market.tkn1) {
      assertEq(reader.numOpenMarkets(), 0, "length should still be 0");
      assertEq(reader.isMarketOpen(market), false, "status should still be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 1, "length should still be 0");
      assertEq(reader.isMarketOpen(market), true, "status should still be closed");
      pushExpectedMarket(market, false, true);
    }

    checkMarkets();
  }

  function test_openMarkets_overloads(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    assumeDifferentPairs(tknA, tknB, tkn0, tkn1);
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateMarket(mktB);
    reader.updateMarket(mktB);
    activateMarket(mktA);
    reader.updateMarket(mktA);
    MarketConfig[] memory configs;
    (, configs) = reader.openMarkets(true);
    assertEq(configs.length, 2, "full: wrong config length");
    (, configs) = reader.openMarkets(false);
    assertEq(configs.length, 0, "none: wrong config length");
    (, configs) = reader.openMarkets(0, 1, true);
    assertEq(configs.length, 1, "slice0_full: wrong config length");
    (, configs) = reader.openMarkets(0, 1, false);
    assertEq(configs.length, 0, "slice0_none: wrong config length");
    (, configs) = reader.openMarkets(1, 1, true);
    assertEq(configs.length, 1, "slice1_full: wrong config length");
    (, configs) = reader.openMarkets(1, 1, false);
    assertEq(configs.length, 0, "slice1_none: wrong config length");
    (, configs) = reader.openMarkets(1, 10, true);
    assertEq(configs.length, 1, "sliceN_full: wrong config length");
    (, configs) = reader.openMarkets(1, 10, false);
    assertEq(configs.length, 0, "sliceN_none: wrong config length");
    (, configs) = reader.openMarkets(2, 10, true);
    assertEq(configs.length, 0, "sliceX_full: wrong config length");
    (, configs) = reader.openMarkets(2, 10, false);
    assertEq(configs.length, 0, "sliceX_none: wrong config length");
  }

  function test_marketConfig(Market memory market) public {
    activateOfferList(toOLKey(market));
    MarketConfig memory config = reader.marketConfig(market);
    assertEq(config.config01.active, true, "01-config01 wrong");
    if (market.tkn0 != market.tkn1) {
      assertEq(config.config10.active, false, "01-config10 wrong");
    }
    config = reader.marketConfig(flipped(market));
    if (market.tkn0 != market.tkn1) {
      assertEq(config.config01.active, false, "10-config01 wrong");
    }
    assertEq(config.config10.active, true, "10-config10 wrong");
  }

  function test_no_double_remove_long_swap(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing)
    public
  {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    assumeDifferentPairs(tknA, tknB, tkn0, tkn1);
    activateMarket(mktA);
    reader.updateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktB);
    mgv.deactivate(toOLKey(mktB));
    reader.updateMarket(mktB);
    reader.updateMarket(flipped(mktB));
    pushExpectedMarket(mktA, true, true);

    if (mktB.tkn0 == mktB.tkn1) {
      assertEq(reader.numOpenMarkets(), 1, "wrong length");
      assertEq(reader.isMarketOpen(mktB), false, "status should still be closed");
    } else {
      assertEq(reader.numOpenMarkets(), 2, "wrong length");
      assertEq(reader.isMarketOpen(mktB), true, "status should still be closed");
      pushExpectedMarket(mktB, false, true);
    }

    checkMarkets();
  }

  function test_market_slice_zero(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    (Market[] memory slice,) = reader.openMarkets(0, 0);
    assertEq(slice.length, 0);
  }

  function test_market_slice_multi(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    Market[] memory slice;
    // first
    (slice,) = reader.openMarkets(0, 1);
    assertEq(slice.length, 1, "first: wrong slice length");
    (tknA, tknB) = order(tknA, tknB);
    assertEq(slice[0].tkn0, tknA, "first: wrong tkn0");
    assertEq(slice[0].tkn1, tknB, "first: wrong tkn1");
    // last
    (slice,) = reader.openMarkets(1, 1);
    assertEq(slice.length, 1, "last: wrong slice length");
    (tkn0, tkn1) = order(tkn0, tkn1);
    assertEq(slice[0].tkn0, tkn0, "last: wrong tkn0");
    assertEq(slice[0].tkn1, tkn1, "last: wrong tkn1");
    // full
    (slice,) = reader.openMarkets(0, 2);
    assertEq(slice.length, 2, "full: wrong slice length");
    assertEq(slice[0].tkn0, tknA, "full 1: wrong tkn0");
    assertEq(slice[0].tkn1, tknB, "full 1: wrong tkn1");
    assertEq(slice[1].tkn0, tkn0, "full 2: wrong tkn0");
    assertEq(slice[1].tkn1, tkn1, "full 2: wrong tkn1");
    // overflow
    (slice,) = reader.openMarkets(0, 3);
    assertEq(slice.length, 2, "overflow: wrong slice length");
    assertEq(slice[0].tkn0, tknA, "overflow 1: wrong tkn0");
    assertEq(slice[0].tkn1, tknB, "overflow 1: wrong tkn1");
    assertEq(slice[1].tkn0, tkn0, "overflow 2: wrong tkn0");
    assertEq(slice[1].tkn1, tkn1, "overflow 2: wrong tkn1");
  }

  function test_market_slice_revert(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateMarket(mktA);
    activateMarket(mktB);
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    vm.expectRevert(stdError.arithmeticError);
    reader.openMarkets(3, 0);
  }

  function test_remove_2nd_to_last(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    assumeDifferentPairs(tknA, tknB, tkn0, tkn1);
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateOfferList(toOLKey(mktA));
    activateOfferList(toOLKey(mktB));
    // remove 2nd-to-last
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    mgv.deactivate(toOLKey(mktA));
    reader.updateMarket(mktA);
    pushExpectedMarket(mktB, true, tkn0 == tkn1);
    checkMarkets();
  }

  function test_remove_last_and_only(Market memory market) public {
    activateOfferList(toOLKey(market));
    // remove 2nd-to-last
    reader.updateMarket(market);
    mgv.deactivate(toOLKey(market));
    reader.updateMarket(market);
    checkMarkets();
  }

  function test_remove_last_not_only(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateOfferList(toOLKey(mktA));
    activateOfferList(toOLKey(mktB));
    // remove 2nd-to-last
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    mgv.deactivate(toOLKey(mktB));
    reader.updateMarket(mktB);
    pushExpectedMarket(mktA, true, tknA == tknB);
    checkMarkets();
  }

  function test_update_already_absent(address tknA, address tknB, address tkn0, address tkn1, uint tickSpacing) public {
    Market memory mktA = Market(tknA, tknB, tickSpacing);
    Market memory mktB = Market(tkn0, tkn1, tickSpacing);
    activateOfferList(toOLKey(mktA));
    reader.updateMarket(mktA);
    reader.updateMarket(mktB);
    pushExpectedMarket(mktA, true, tknA == tknB);
    checkMarkets();
  }
}

function printVolumeData(VolumeData[] memory vd) pure {
  console.log("====================");
  console.log("Volume Data size: %s", vd.length);
  for (uint i = 0; i < vd.length; i++) {
    console.log("got %s", vd[i].totalGot);
    console.log("gave %s", vd[i].totalGave);
    console.log("___________");
  }
  console.log("====================");
}
