// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import {MgvReaderDeployer} from "@mgv/script/periphery/deployers/MgvReaderDeployer.s.sol";

contract MangroveDeployer is Deployer {
  IMangrove public mgv;
  MgvReader public reader;
  MgvOracle public oracle;

  function run() public {
    innerRun({
      chief: envAddressOrName("CHIEF", broadcaster()),
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000,
      gasbot: envAddressOrName("GASBOT", "Gasbot")
    });
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax, address gasbot) public {
    broadcast();
    if (forMultisig) {
      oracle = new MgvOracle{salt: salt}({governance_: chief, initialMutator_: gasbot, initialGasPrice_: gasprice});
    } else {
      oracle = new MgvOracle({governance_: chief, initialMutator_: gasbot, initialGasPrice_: gasprice});
    }
    fork.set("MgvOracle", address(oracle));

    broadcast();
    if (forMultisig) {
      mgv = IMangrove(
        payable(address(new Mangrove{salt:salt}({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax})))
      );
    } else {
      mgv = IMangrove(payable(address(new Mangrove({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax}))));
    }
    fork.set("Mangrove", address(mgv));

    broadcast();
    mgv.setMonitor(address(oracle));
    broadcast();
    mgv.setUseOracle(true);
    broadcast();
    mgv.setGovernance(chief);

    (new MgvReaderDeployer()).innerRun(mgv);
    reader = MgvReader(fork.get("MgvReader"));
  }
}
