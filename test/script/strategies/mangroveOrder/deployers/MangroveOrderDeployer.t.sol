// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MangroveDeployer} from "mgv_script/core/deployers/MangroveDeployer.s.sol";
import {
  MangroveOrderDeployer,
  MangroveOrder
} from "mgv_script/strategies/mangroveOrder/deployers/MangroveOrderDeployer.s.sol";

import {BaseMangroveOrderDeployerTest} from "./BaseMangroveOrderDeployer.t.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

contract MangroveOrderDeployerTest is BaseMangroveOrderDeployerTest {
  function setUp() public {
    DeployPermit2 deployPermit2 = new DeployPermit2();
    address permit2 = deployPermit2.deployPermit2();
    fork.set("Permit2", permit2);

    chief = freshAddress("admin");

    address gasbot = freshAddress("gasbot");
    uint gasprice = 42;
    uint gasmax = 8_000_000;
    (new MangroveDeployer()).innerRun(chief, gasprice, gasmax, gasbot);

    mgoDeployer = new MangroveOrderDeployer();
  }
}
