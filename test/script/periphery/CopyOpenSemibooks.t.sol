// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";

import "mgv_test/lib/MangroveTest.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {CopyOpenSemibooks} from "mgv_script/periphery/CopyOpenSemibooks.s.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

contract CopyOpenSemibooksTest is MangroveTest {
  // MangroveDeployer deployer;
  address chief;

  Mangrove mgv2;
  MgvReader reader2;
  address chief2;

  CopyOpenSemibooks copier;

  function setUp() public override {
    super.setUp();

    chief = freshAddress("chief");
    mgv.setGovernance(chief);

    chief2 = freshAddress("chief2");
    mgv2 = new Mangrove(chief2,reader.global().gasprice(),reader.global().gasmax());
    reader2 = new MgvReader(address(mgv2));

    copier = new CopyOpenSemibooks();
  }

  function test_copy_simple(Market memory market) public {
    vm.prank(chief);
    mgv.activate(toOLKey(market), 3, 4, 2);
    reader.updateMarket(market);

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(market), true, "market should be open");
    assertEq(
      MgvStructs.LocalPacked.unwrap(reader2.local(toOLKey(market))),
      MgvStructs.LocalPacked.unwrap(reader.local(toOLKey(market)))
    );
  }

  function test_copy_already_open(Market memory market) public {
    uint expectedFee = 3;
    uint expectedDensity = 4;
    uint expectedOfferGasbase = 2000;
    vm.prank(chief);
    mgv.activate(toOLKey(market), expectedFee, expectedDensity >> 32, expectedOfferGasbase);

    reader.updateMarket(market);

    vm.prank(chief2);
    mgv2.activate(toOLKey(market), 1, 1, 1);
    reader2.updateMarket(market);

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(market), true, "market should be open");
    assertEq(reader2.local(toOLKey(market)).active(), true, "should be active");
    if (market.tkn1 != market.tkn0) {
      assertEq(reader2.local(toOLKey(flipped(market))).active(), false, "should be inactive");
    }
    console.log(toString(reader2.local(toOLKey(market))));
    assertEq(reader2.local(toOLKey(market)).fee(), expectedFee, "wrong fee");
    assertEq(reader2.local(toOLKey(market)).density().toFixed(), expectedDensity >> 32, "wrong density");
    assertEq(reader2.local(toOLKey(market)).offer_gasbase(), expectedOfferGasbase, "wrong gasbase");
  }
}
