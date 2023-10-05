// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MumbaiMangroveDeployer} from "@mgv/script/core/deployers/MumbaiMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

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
