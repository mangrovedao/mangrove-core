// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BlastMangrove} from "@mgv/src/chains/blast/core/BlastMangrove.sol";
import {IBlastMangrove} from "@mgv/src/chains/blast/IBlastMangrove.sol";
import {IBlast} from "@mgv/src/chains/blast/interfaces/IBlast.sol";
import {IBlastPoints} from "@mgv/src/chains/blast/interfaces/IBlastPoints.sol";

import {MangroveDeployer} from "./MangroveDeployer.s.sol";

contract BlastMangroveDeployer is MangroveDeployer {
  IBlast public blastContract;
  IBlastPoints public blastPointsContract;

  address public blastGovernor;
  address public blastPointsOperator;

  function run() public override {
    blastContract = IBlast(envAddressOrName("BLAST_CONTRACT", "Blast"));
    blastPointsContract = IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints"));
    blastGovernor = envAddressOrName("BLAST_GOVERNOR", "BlastGovernor");
    blastPointsOperator = envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator");

    innerRun({
      chief: envAddressOrName("CHIEF", broadcaster()),
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000,
      gasbot: envAddressOrName("GASBOT", "Gasbot"),
      _blastContract: IBlast(envAddressOrName("BLAST_CONTRACT", "Blast")),
      _blastPointsContract: IBlastPoints(envAddressOrName("BLAST_POINTS_CONTRACT", "BlastPoints")),
      _blastGovernor: envAddressOrName("BLAST_GOVERNOR", "BlastGovernor"),
      _blastPointsOperator: envAddressOrName("BLAST_POINTS_OPERATOR", "BlastPointsOperator")
    });
    outputDeployment();
  }

  function innerRun(
    address chief,
    uint gasprice,
    uint gasmax,
    address gasbot,
    IBlast _blastContract,
    address _blastGovernor,
    IBlastPoints _blastPointsContract,
    address _blastPointsOperator
  ) public {
    blastContract = _blastContract;
    blastPointsContract = _blastPointsContract;
    blastGovernor = _blastGovernor;
    blastPointsOperator = _blastPointsOperator;

    super.innerRun(chief, gasprice, gasmax, gasbot);
  }

  function deployMangrove(address governance, uint gasprice, uint gasmax) public override {
    if (forMultisig) {
      mgv = IBlastMangrove(
        payable(
          address(
            new BlastMangrove{salt: salt}({
              governance: governance,
              gasprice: gasprice,
              gasmax: gasmax,
              blastContract: blastContract,
              blastGovernor: blastGovernor,
              blastPointsContract: blastPointsContract,
              blastPointsOperator: blastPointsOperator
            })
          )
        )
      );
    } else {
      mgv = IBlastMangrove(
        payable(
          address(
            new BlastMangrove({
              governance: governance,
              gasprice: gasprice,
              gasmax: gasmax,
              blastContract: blastContract,
              blastGovernor: blastGovernor,
              blastPointsContract: blastPointsContract,
              blastPointsOperator: blastPointsOperator
            })
          )
        )
      );
    }
  }
}
