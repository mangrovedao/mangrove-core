// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";
import "@mgv/script/core/DeactivateMarket.s.sol";
import {UpdateMarket} from "@mgv/script/periphery/UpdateMarket.s.sol";

import {Test2} from "@mgv/lib/Test2.sol";

import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {IERC20} from "@mgv/lib/IERC20.sol";
import "@mgv/src/core/MgvLib.sol";

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
    IMangrove mgv = deployer.mgv();
    MgvReader reader = deployer.reader();

    vm.prank(chief);
    mgv.activate(toOLKey(market), 1, 1, 1);

    (new UpdateMarket()).innerRun(reader, market);

    assertEq(reader.isMarketOpen(market), true, "market should be open");

    DeactivateMarket deactivator = new DeactivateMarket();
    // the script self-tests, so no need to test here. This file is only for
    // incorporating testing the script into the CI.
    deactivator.broadcaster(chief);
    deactivator.innerRun(mgv, reader, market);
  }
}
