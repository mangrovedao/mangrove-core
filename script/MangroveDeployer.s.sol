// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Mangrove} from "mgv_src/Mangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "./lib/Deployer.sol";
import {MgvCleanerDeployer} from "./periphery/MgvCleanerDeployer.s.sol";
import {MgvReaderDeployer} from "./periphery/MgvReaderDeployer.s.sol";

contract MangroveDeployer is Deployer {
  Mangrove public mgv;
  MgvReader public reader;
  MgvCleaner public cleaner;
  MgvOracle public oracle;

  function run() public {
    innerRun({
      chief: envAddressOrName("CHIEF", broadcaster()),
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000,
      gasbot: envAddressOrName("GASBOT", fork.get("Gasbot"))
    });
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax, address gasbot) public {
    broadcast();
    if (forMultisig) {
      oracle = new MgvOracle{salt: salt}({governance_: chief, initialMutator_: gasbot});
    } else {
      oracle = new MgvOracle({governance_: chief, initialMutator_: gasbot});
    }
    fork.set("MgvOracle", address(oracle));

    broadcast();
    if (forMultisig) {
      mgv = new Mangrove{salt:salt}({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax});
    } else {
      mgv = new Mangrove({governance: broadcaster(), gasprice: gasprice, gasmax: gasmax});
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

    (new MgvCleanerDeployer()).innerRun(mgv);
    cleaner = MgvCleaner(fork.get("MgvCleaner"));
  }
}
