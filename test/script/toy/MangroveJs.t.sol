// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer, SINGLETON_BROADCASTER} from "mgv_script/lib/Deployer.sol";
import {MangroveJsDeploy} from "mgv_script/toy/MangroveJs.s.sol";

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import "forge-std/console.sol";

contract MangroveJsDeployTest is MangroveTest {
  function test_runs(address chief, uint gasprice, uint gasmax, address gasbot, uint mintA, uint mintB) public {
    vm.assume(chief != address(0));
    gasprice = bound(gasprice, 0, type(uint16).max);
    gasmax = bound(gasmax, 0, type(uint24).max);
    // execution
    MangroveJsDeploy deployer = new MangroveJsDeploy();
    deployer.broadcaster(chief);
    deployer.innerRun(gasprice, gasmax, gasbot);
    // mintability of test tokens
    deployer.tokenA().mint(mintA);
    deployer.tokenB().mint(mintB);
  }
}
