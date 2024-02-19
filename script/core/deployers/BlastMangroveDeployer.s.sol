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
  function run() public override {
    innerRun({
      chief: envAddressOrName("CHIEF", broadcaster()),
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000,
      gasbot: envAddressOrName("GASBOT", "Gasbot")
    });
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax, address gasbot) public override {
    broadcast();
    if (forMultisig) {
      oracle = new MgvOracle{salt: salt}({governance_: chief, initialMutator_: gasbot, initialGasPrice_: gasprice});
    } else {
      oracle = new MgvOracle({governance_: chief, initialMutator_: gasbot, initialGasPrice_: gasprice});
    }
    fork.set("MgvOracle", address(oracle));

    broadcast();
    if (forMultisig) {
      mgv = IBlastMangrove(
        payable(address(new BlastMangrove{salt: salt}({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax})))
      );
    } else {
      mgv = IBlastMangrove(
        payable(address(new BlastMangrove({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax})))
      );
    }
    fork.set("Mangrove", address(mgv));

    broadcast();
    mgv.setMonitor(address(oracle));
    broadcast();
    mgv.setUseOracle(true);
    broadcast();
    mgv.setGovernance(chief);
    broadcast();
    BlastLib.BLAST.configureGovernorOnBehalf(chief, address(mgv));

    (new MgvReaderDeployer()).innerRun(mgv);
    reader = MgvReader(fork.get("MgvReader"));
  }
}
