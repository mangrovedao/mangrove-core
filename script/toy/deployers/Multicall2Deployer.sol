// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Multicall2} from "@mgv/src/toy/Multicall2.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

contract Multicall2Deployer is Deployer {
  function run() public virtual {
    innerRun();
    outputDeployment();
  }

  function innerRun() public {
    Multicall2 multicall2;

    broadcast();
    multicall2 = new Multicall2();
    fork.set("Multicall2", address(multicall2));
  }
}
