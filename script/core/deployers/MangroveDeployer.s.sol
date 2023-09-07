// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvReaderDeployer} from "mgv_script/periphery/deployers/MgvReaderDeployer.s.sol";

contract MangroveDeployer is Deployer {
  IMangrove public mgv;
  MgvReader public reader;
  MgvOracle public oracle;

  function run() public {
    uint gasmax = envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000;
    innerRun({
      chief: envAddressOrName("CHIEF", broadcaster()),
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: gasmax,
      maxGasreqForFailingOffers: envHas("MAX_GASREQ_FOR_FAILING_OFFERS")
        ? vm.envUint("MAX_GASREQ_FOR_FAILING_OFFERS")
        : gasmax * 10,
      gasbot: envAddressOrName("GASBOT", "Gasbot")
    });
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax, uint maxGasreqForFailingOffers, address gasbot) public {
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
        payable(
          address(
            new Mangrove{salt:salt}({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax, maxGasreqForFailingOffers:maxGasreqForFailingOffers})
          )
        )
      );
    } else {
      mgv = IMangrove(
        payable(
          address(
            new Mangrove({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax, maxGasreqForFailingOffers:maxGasreqForFailingOffers})
          )
        )
      );
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
