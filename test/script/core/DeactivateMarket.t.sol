// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";
import "mgv_script/core/DeactivateMarket.s.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

import {Test2} from "mgv_lib/Test2.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OL} from "mgv_src/MgvLib.sol";

contract DeactivateMarketTest is Test2 {
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

  function test_deactivate(Market memory market) public {
    Mangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    vm.prank(chief);
    mgv.activate(toOL(market), 1, 1, 1);

    (new UpdateMarket()).innerRun(reader, market);

    assertEq(reader.isMarketOpen(market), true, "market should be open");

    DeactivateMarket deactivator = new DeactivateMarket();
    // the script self-tests, so no need to test here. This file is only for
    // incorporating testing the script into the CI.
    deactivator.broadcaster(chief);
    deactivator.innerRun(mgv, reader, market);
  }
}
