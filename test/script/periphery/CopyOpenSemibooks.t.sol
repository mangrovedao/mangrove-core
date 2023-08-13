// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";

import "mgv_test/lib/MangroveTest.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
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

  function test_copy_simple(address tkn0, address tkn1) public {
    vm.prank(chief);
    mgv.activate(OL(tkn0, tkn1, DEFAULT_TICKSCALE), 3, 4, 2);
    reader.updateMarket(MgvReader.Market(tkn0, tkn1, DEFAULT_TICKSCALE));

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(MgvReader.Market(tkn0, tkn1, DEFAULT_TICKSCALE)), true, "market should be open");
    assertEq(
      MgvStructs.LocalPacked.unwrap(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE))),
      MgvStructs.LocalPacked.unwrap(reader.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE)))
    );
  }

  function test_copy_already_open(address tkn0, address tkn1) public {
    uint expectedFee = 3;
    uint expectedDensity = 4;
    uint expectedOfferGasbase = 2000;
    vm.prank(chief);
    mgv.activate(OL(tkn0, tkn1, DEFAULT_TICKSCALE), expectedFee, expectedDensity >> 32, expectedOfferGasbase);
    reader.updateMarket(MgvReader.Market(tkn0, tkn1, DEFAULT_TICKSCALE));

    vm.prank(chief2);
    mgv2.activate(OL(tkn0, tkn1, DEFAULT_TICKSCALE), 1, 1, 1);
    reader2.updateMarket(MgvReader.Market(tkn0, tkn1, DEFAULT_TICKSCALE));

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(MgvReader.Market(tkn0, tkn1, DEFAULT_TICKSCALE)), true, "market should be open");
    assertEq(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE)).active(), true, "should be active");
    if (tkn1 != tkn0) {
      assertEq(reader2.local(OL(tkn1, tkn0, DEFAULT_TICKSCALE)).active(), false, "should be inactive");
    }
    console.log(toString(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE))));
    assertEq(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE)).fee(), expectedFee, "wrong fee");
    assertEq(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE)).density().toFixed(), expectedDensity >> 32, "wrong density");
    assertEq(reader2.local(OL(tkn0, tkn1, DEFAULT_TICKSCALE)).offer_gasbase(), expectedOfferGasbase, "wrong gasbase");
  }
}
