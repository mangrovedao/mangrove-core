// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {PolygonMangroveDeployer} from "mgv_script/core/deployers/PolygonMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

contract PolygonMangroveDeployerTest is BaseMangroveDeployerTest {
  function setUp() public {
    chief = freshAddress("MgvGovernance");
    fork.set("MgvGovernance", chief);
    gasbot = freshAddress("Gasbot");
    fork.set("Gasbot", gasbot);

    PolygonMangroveDeployer polygonMangroveDeployer = new PolygonMangroveDeployer();

    polygonMangroveDeployer.runWithChainSpecificParams();

    gasprice = polygonMangroveDeployer.gasprice();
    gasmax = polygonMangroveDeployer.gasmax();
    mgvDeployer = polygonMangroveDeployer.mangroveDeployer();
  }
}
