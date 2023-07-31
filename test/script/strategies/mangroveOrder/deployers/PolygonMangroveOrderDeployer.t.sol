// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {PolygonMangroveDeployer} from "mgv_script/core/deployers/PolygonMangroveDeployer.s.sol";

import {BaseMangroveOrderDeployerTest} from "./BaseMangroveOrderDeployer.t.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {
  PolygonMangroveOrderDeployer,
  MangroveOrder
} from "mgv_script/strategies/mangroveOrder/deployers/PolygonMangroveOrderDeployer.s.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";

contract PolygonMangroveOrderDeployerTest is BaseMangroveOrderDeployerTest {
  function setUp() public {
    DeployPermit2 deployPermit2 = new DeployPermit2();
    address permit2 = deployPermit2.deployPermit2();
    fork.set("Permit2", permit2);

    chief = freshAddress("chief");
    fork.set("MgvGovernance", chief);

    fork.set("Gasbot", freshAddress("gasbot"));
    (new PolygonMangroveDeployer()).runWithChainSpecificParams();

    PolygonMangroveOrderDeployer polygonMgoDeployer = new PolygonMangroveOrderDeployer();
    polygonMgoDeployer.runWithChainSpecificParams();
    mgoDeployer = polygonMgoDeployer.mangroveOrderDeployer();
  }
}
