// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {PolygonMangroveDeployer} from "@mgv/script/core/deployers/PolygonMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

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
