// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";

import "mgv_src/Mangrove.sol";
import "mgv_src/periphery/MgvReader.sol";
import {MangroveOrderEnriched} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {MgvCleaner} from "mgv_src/periphery/MgvCleaner.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Deployer} from "./Deployer.sol";

contract MangroveDeployer is Deployer {
  Mangrove public mgv;
  MgvReader public reader;
  MgvCleaner public cleaner;
  MgvOracle public oracle;
  MangroveOrderEnriched public mgoe;

  function run() public {
    innerRun({chief: msg.sender, gasprice: 1, gasmax: 2_000_000});
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
    oracle = new MgvOracle({_governance: chief, _initialMutator: chief});
    fork.set("MgvOracle", address(oracle));

    broadcast();
    mgoe = new MangroveOrderEnriched({
      mgv: IMangrove(payable(mgv)),
      deployer: chief
    });
    fork.set("MangroveOrderEnriched", address(mgoe));
  }
}
