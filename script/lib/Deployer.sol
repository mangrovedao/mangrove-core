// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;
import {Script, console} from "forge-std/Script.sol";
import {ToyENS} from "./ToyENS.sol";

/* Outputs deployments as follows:

   To a toy ENS instance. Useful for testing when the server & testing script
   are both spawned in-process. Holds additional info on the contracts (whether
   it's a token). In the future, could be either removed (in favor of a
   file-based solution), or expanded (if an onchain addressProvider appears).

   How to use:
   1. Inherit Deployer.
   2. In run(), call outputDeployment() after deploying.

   Do not inherit other deployer scripts, just instantiate them and call their
   .deploy();
*/
abstract contract Deployer is Script {
  ToyENS ens; // singleton local ens instance
  ToyENS remoteEns; // out-of-band agreed upon toy ens address

  constructor() {
    // enforce singleton ENS, so all deploys can be collected in outputDeployment
    // otherwise Deployer scripts would need to inherit from one another
    // which would prevent deployer script composition
    ens = ToyENS(address(bytes20(hex"decaf1")));
    remoteEns = ToyENS(address(bytes20(hex"decaf0")));

    if (address(ens).code.length == 0) {
      vm.etch(address(ens), address(new ToyENS()).code);
    }
  }

  function outputDeployment() internal {
    (string[] memory names, address[] memory addrs, bool[] memory isToken) = ens
      .all();

    // toy ens is set, use it
    if (address(remoteEns).code.length > 0) {
      vm.broadcast();
      remoteEns.set(names, addrs, isToken);
    }
  }
}
