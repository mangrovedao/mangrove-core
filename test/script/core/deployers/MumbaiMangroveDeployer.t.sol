// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MumbaiMangroveDeployer} from "mgv_script/core/deployers/MumbaiMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "mgv_lib/Test2.sol";

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

contract MumbaiMangroveDeployerTest is BaseMangroveDeployerTest {
  function setUp() public {
    chief = broadcaster();
    gasbot = freshAddress("Gasbot");
    fork.set("Gasbot", gasbot);

    MumbaiMangroveDeployer mumbaiMangroveDeployer = new MumbaiMangroveDeployer();

    gasprice = mumbaiMangroveDeployer.gasprice();
    gasmax = mumbaiMangroveDeployer.gasmax();

    mumbaiMangroveDeployer.runWithChainSpecificParams();

    mgvDeployer = mumbaiMangroveDeployer.mangroveDeployer();
  }
}
