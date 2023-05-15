// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {CopyOpenSemibooks} from "mgv_script/periphery/CopyOpenSemibooks.s.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import "forge-std/console.sol";

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
    mgv.activate(tkn0, tkn1, 3, 4, 2);
    reader.updateMarket(tkn0, tkn1);

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(tkn0, tkn1), true, "market should be open");
    assertEq(
      MgvStructs.LocalPacked.unwrap(reader2.local(tkn0, tkn1)), MgvStructs.LocalPacked.unwrap(reader.local(tkn0, tkn1))
    );
  }

  function test_copy_already_open(address tkn0, address tkn1) public {
    uint expectedFee = 3;
    uint expectedDensity = 4;
    uint expectedOfferGasbase = 2;
    vm.prank(chief);
    mgv.activate(tkn0, tkn1, expectedFee, expectedDensity, expectedOfferGasbase);
    reader.updateMarket(tkn0, tkn1);

    vm.prank(chief2);
    mgv2.activate(tkn0, tkn1, 1, 1, 1);
    reader2.updateMarket(tkn0, tkn1);

    copier.broadcaster(chief2);
    copier.innerRun(reader, reader2);

    assertEq(reader.numOpenMarkets(), 1, "changes in previous reader");
    assertEq(reader2.numOpenMarkets(), 1, "wrong changes in current reader");
    assertEq(reader2.isMarketOpen(tkn0, tkn1), true, "market should be open");
    assertEq(reader2.local(tkn0, tkn1).active(), true, "should be active");
    if (tkn1 != tkn0) {
      assertEq(reader2.local(tkn1, tkn0).active(), false, "should be inactive");
    }
    assertEq(reader2.local(tkn0, tkn1).fee(), expectedFee, "wrong fee");
    assertEq(reader2.local(tkn0, tkn1).density(), expectedDensity, "wrong density");
    assertEq(reader2.local(tkn0, tkn1).offer_gasbase(), expectedOfferGasbase, "wrong gasbase");
  }
}
