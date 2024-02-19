// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {BlastMangroveDeployer} from "@mgv/script/core/deployers/BlastMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {Test2, Test, console} from "@mgv/lib/Test2.sol";

import "@mgv/src/core/MgvLib.sol";
import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";

import {BlastSepoliaFork} from "@mgv/test/lib/forks/BlastSepolia.sol";

contract MangroveDeployerTest is BaseMangroveDeployerTest {
  function setUp() public {
    deployCodeTo("Blast.sol", address(BlastLib.BLAST));
    mgvDeployer = new BlastMangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    gasbot = freshAddress("gasbot");
    mgvDeployer.innerRun(chief, gasprice, gasmax, gasbot);
  }

  function test_governor_blast() public {
    address mgv = address(mgvDeployer.mgv());
    vm.prank(chief);
    assertTrue(BlastLib.BLAST.isAuthorized(mgv));
  }
}
