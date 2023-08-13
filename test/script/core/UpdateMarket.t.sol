// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

import {Test2} from "mgv_lib/Test2.sol";

import {Mangrove} from "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OL} from "mgv_src/MgvLib.sol";

contract UpdateMarketTest is Test2 {
  uint constant DEFAULT_TICKSCALE = 1;
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

  function test_updater(OL memory ol) public {
    Market memory market = Market(ol.outbound, ol.inbound, ol.tickScale);
    Mangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    UpdateMarket updater = new UpdateMarket();

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), false);

    vm.prank(chief);
    mgv.activate(ol, 1, 1, 1);

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), true);

    vm.prank(chief);
    mgv.deactivate(ol);

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), false);
  }
}
