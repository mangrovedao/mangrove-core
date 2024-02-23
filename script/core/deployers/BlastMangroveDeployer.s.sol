// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {BlastMangrove} from "@mgv/src/chains/blast/core/BlastMangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IBlastMangrove} from "@mgv/src/chains/blast/IBlastMangrove.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MgvReaderDeployer} from "@mgv/script/periphery/deployers/MgvReaderDeployer.s.sol";
import {BlastLib} from "@mgv/src/chains/blast/lib/BlastLib.sol";
import {MangroveDeployer} from "./MangroveDeployer.s.sol";

contract BlastMangroveDeployer is MangroveDeployer {
  function innerRun(address chief, uint gasprice, uint gasmax, address gasbot) public override {
    super.innerRun(chief, gasprice, gasmax, gasbot);
    broadcast();
    BlastLib.BLAST.configureGovernorOnBehalf(chief, address(mgv));
  }

  function deployMangrove(address governance, uint gasprice, uint gasmax) public override {
    if (forMultisig) {
      mgv = IBlastMangrove(
        payable(address(new BlastMangrove{salt: salt}({governance: governance, gasprice: gasprice, gasmax: gasmax})))
      );
    } else {
      mgv = IBlastMangrove(
        payable(address(new BlastMangrove({governance: governance, gasprice: gasprice, gasmax: gasmax})))
      );
    }
  }
}
