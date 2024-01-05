// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {SepoliaMangroveDeployer} from "@mgv/script/core/deployers/SepoliaMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

contract SepoliaMangroveDeployerTest is BaseMangroveDeployerTest {
  function setUp() public {
    chief = broadcaster();
    gasbot = freshAddress("Gasbot");
    fork.set("Gasbot", gasbot);

    SepoliaMangroveDeployer sepoliaMangroveDeployer = new SepoliaMangroveDeployer();

    gasprice = sepoliaMangroveDeployer.gasprice();
    gasmax = sepoliaMangroveDeployer.gasmax();

    sepoliaMangroveDeployer.runWithChainSpecificParams();

    mgvDeployer = sepoliaMangroveDeployer.mangroveDeployer();
  }
}
