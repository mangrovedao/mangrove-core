// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvReader} from "mgv_src/periphery/MgvReader.sol";

/**
 * @notice deploys a MgvReader instance
 */

contract MgvReaderDeployer is Deployer {
  function run() public {
    innerRun({mgv: IMangrove(envAddressOrName("MGV", "Mangrove"))});
    outputDeployment();
  }

  function innerRun(IMangrove mgv) public {
    MgvReader reader;
    broadcast();
    if (forMultisig) {
      reader = new MgvReader{salt:salt}({mgv: address(mgv)});
    } else {
      reader = new MgvReader({mgv: address(mgv)});
    }
    fork.set("MgvReader", address(reader));
  }
}
