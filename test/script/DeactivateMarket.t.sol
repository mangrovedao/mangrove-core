// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";

import {Test2} from "mgv_lib/Test2.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {DeactivateMarket} from "mgv_script/DeactivateMarket.s.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

contract DeactivateMarketTest is Test2 {
  MangroveDeployer deployer;
  address chief;
  uint gasprice;
  uint gasmax;

  function setUp() public {
    deployer = new MangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    deployer.innerRun(chief, gasprice, gasmax);
  }

  function test_deactivate(address tkn0, address tkn1) public {
    Mangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    vm.prank(chief);
    mgv.activate(tkn0, tkn1, 1, 1, 1);

    (new UpdateMarket()).innerRun(tkn0, tkn1, address(reader));

    assertEq(reader.isMarketOpen(tkn0, tkn1), true, "market should be open");

    DeactivateMarket deactivator = new DeactivateMarket();
    // the script self-tests, so no need to test here. This file is only for
    // incorporating testing the script into the CI.
    deactivator.broadcaster(chief);
    deactivator.innerRun(tkn0, tkn1);
  }
}
