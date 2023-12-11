// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MangroveDeployer} from "@mgv/script/core/deployers/MangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";

contract MangroveDeployerTest is BaseMangroveDeployerTest {
  function setUp() public {
    mgvDeployer = new MangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    gasbot = freshAddress("gasbot");
    mgvDeployer.innerRun(chief, gasprice, gasmax, gasbot);
  }
}
