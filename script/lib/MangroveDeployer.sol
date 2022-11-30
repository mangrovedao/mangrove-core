// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "./Deployer.sol";

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
    mgv = new Mangrove({governance: chief, gasprice: gasprice, gasmax: gasmax});
    fork.set("Mangrove", address(mgv));

    broadcast();
    reader = new MgvReader({mgv: payable(mgv)});
    fork.set("MgvReader", address(reader));

    broadcast();
    cleaner = new MgvCleaner({mgv: address(mgv)});
    fork.set("MgvCleaner", address(cleaner));

    broadcast();
    oracle = new MgvOracle({governance_: chief, initialMutator_: chief});
    fork.set("MgvOracle", address(oracle));
  }
}
