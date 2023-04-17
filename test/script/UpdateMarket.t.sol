// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";

import {Test2} from "mgv_lib/Test2.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

contract UpdateMarketTest is Test2 {
  MangroveDeployer deployer;
  address chief;
  uint gasprice;
  uint gasmax;
  address gasbot;

  function setUp() public {
    deployer = new MangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    gasbot = freshAddress("gasbot");
    deployer.innerRun(chief, gasprice, gasmax, gasbot);
  }

  function test_updater(address tkn0, address tkn1) public {
    Mangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    UpdateMarket updater = new UpdateMarket();

    updater.innerRun(reader, tkn0, tkn1);
    assertEq(reader.isMarketOpen(tkn0, tkn1), false);

    vm.prank(chief);
    mgv.activate(tkn0, tkn1, 1, 1, 1);

    updater.innerRun(reader, tkn0, tkn1);
    assertEq(reader.isMarketOpen(tkn0, tkn1), true);

    vm.prank(chief);
    mgv.deactivate(tkn0, tkn1);

    updater.innerRun(reader, tkn0, tkn1);
    assertEq(reader.isMarketOpen(tkn0, tkn1), false);
  }
}
