// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/MangroveDeployer.s.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {MangroveOrderDeployer, MangroveOrder} from "mgv_script/strategies/mangroveOrder/MangroveOrderDeployer.s.sol";

contract MangroveOrderDeployerTest is Deployer, Test2 {
  MangroveOrderDeployer mgoDeployer;
  address chief;
  uint gasprice;
  uint gasmax;
  address gasbot;

  function setUp() public {
    mgoDeployer = new MangroveOrderDeployer();

    chief = freshAddress("admin");
    gasprice = 42;
    gasmax = 8_000_000;
    gasbot = freshAddress("gasbot");
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);
  }

  function test_normal_deploy() public {
    // MangroveOrder - verify mgv is used and admin is chief
    address mgv = fork.get("Mangrove");
    mgoDeployer.innerRun(IMangrove(payable(mgv)), chief);
    MangroveOrder mgoe = MangroveOrder(fork.get("MangroveOrder"));
    address mgvOrderRouter = fork.get("MangroveOrder-Router");

    assertEq(mgoe.admin(), chief);
    assertEq(address(mgoe.MGV()), mgv);
    assertEq(address(mgoe.router()), mgvOrderRouter);
  }
}
