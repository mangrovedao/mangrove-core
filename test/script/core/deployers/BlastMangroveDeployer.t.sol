// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

import {BlastMangroveDeployer} from "@mgv/script/core/deployers/BlastMangroveDeployer.s.sol";

import {BaseMangroveDeployerTest} from "./BaseMangroveDeployer.t.sol";

import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

// TODO: Should be changed to a fork test against Blast or Blast Sepolia
//   to avoid maintaining copies of the Blast contracts
contract BlastMangroveDeployerTest is BaseMangroveDeployerTest {
  BlastMangroveDeployer blastMgvDeployer;

  IBlast public blastContract;
  IBlastPoints public blastPointsContract;

  address public blastGovernor;
  address public blastPointsOperator;

  function setUp() public {
    blastContract = IBlast(freshAddress("Blast"));
    blastPointsContract = IBlastPoints(freshAddress("BlastPoints"));
    blastGovernor = freshAddress("BlastGovernor");
    blastPointsOperator = freshAddress("BlastPointsOperator");

    deployCodeTo("Blast.sol", address(blastContract));
    deployCodeTo("BlastPoints.sol", address(blastPointsContract));

    mgvDeployer = blastMgvDeployer = new BlastMangroveDeployer();

    chief = freshAddress("chief");
    gasprice = 42;
    gasmax = 8_000_000;
    gasbot = freshAddress("gasbot");
    blastMgvDeployer.innerRun(
      chief, gasprice, gasmax, gasbot, blastContract, blastGovernor, blastPointsContract, blastPointsOperator
    );
  }

  function test_blast_governor() public {
    address mgv = address(mgvDeployer.mgv());
    vm.prank(blastGovernor);
    assertTrue(blastContract.isAuthorized(mgv));
  }

  function test_blast_points_operator() public {
    address mgv = address(mgvDeployer.mgv());
    vm.prank(blastPointsOperator);
    assertTrue(blastPointsContract.isOperator(mgv));
  }

  // TODO: Test that yield and gas fees are configured correctly
}
