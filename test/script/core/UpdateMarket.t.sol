// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";

import {Test2} from "mgv_lib/Test2.sol";

import {Mangrove} from "mgv_src/core/Mangrove.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_lib/IERC20.sol";
import "mgv_src/core/MgvLib.sol";

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

  function test_updater(OLKey memory olKey) public {
    Market memory market = Market(olKey.outbound, olKey.inbound, olKey.tickSpacing);
    IMangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    UpdateMarket updater = new UpdateMarket();

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), false);

    vm.prank(chief);
    mgv.activate(olKey, 1, 1, 1);

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), true);

    vm.prank(chief);
    mgv.deactivate(olKey);

    updater.innerRun(reader, market);
    assertEq(reader.isMarketOpen(market), false);
  }
}
