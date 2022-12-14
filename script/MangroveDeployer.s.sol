// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "./lib/Deployer.sol";
import {MgvCleanerDeployer} from "./periphery/MgvCleaner.s.sol";
import {MgvReaderDeployer} from "./periphery/MgvReader.s.sol";

contract MangroveDeployer is Deployer {
  Mangrove public mgv;
  MgvReader public reader;
  MgvCleaner public cleaner;
  MgvOracle public oracle;

  function run() public {
    innerRun({
      chief: envHas("CHIEF") ? vm.envAddress("CHIEF") : msg.sender,
      gasprice: envHas("GASPRICE") ? vm.envUint("GASPRICE") : 1,
      gasmax: envHas("GASMAX") ? vm.envUint("GASMAX") : 2_000_000
    });
    outputDeployment();
  }

  function innerRun(address chief, uint gasprice, uint gasmax) public {
    broadcast();
    if (forMultisig) {
      mgv = new Mangrove{salt:salt}({governance: chief, gasprice: gasprice, gasmax: gasmax});
    } else {
      mgv = new Mangrove({governance: chief, gasprice: gasprice, gasmax: gasmax});
    }
    fork.set("Mangrove", address(mgv));

    (new MgvReaderDeployer()).innerRun(address(mgv));
    reader = MgvReader(fork.get("MgvReader"));

    (new MgvCleanerDeployer()).innerRun(address(mgv));
    cleaner = MgvCleaner(fork.get("MgvCleaner"));

    broadcast();
    if (forMultisig) {
      oracle = new MgvOracle{salt: salt}({governance_: chief, initialMutator_: chief});
    } else {
      oracle = new MgvOracle({governance_: chief, initialMutator_: chief});
    }
    fork.set("MgvOracle", address(oracle));
  }
}
