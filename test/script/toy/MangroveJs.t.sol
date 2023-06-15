// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {Deployer, SINGLETON_BROADCASTER} from "mgv_script/lib/Deployer.sol";
import {MangroveJsDeploy} from "mgv_script/toy/MangroveJs.s.sol";

import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import "forge-std/console.sol";

contract MangroveJsDeployTest is MangroveTest {
  function test_somefoo() public {
    this.test_runs(
      0x257A9A2C5a7Cb791165a580bdD8eFc81973D1E1b,
      44566091758772537392099623289872258789475110185694143407000399511060737909642,
      1117384713810346522239161599483756589296041293890,
      0x89cc65A219E651Bb0db1B805107eD94663847f78,
      890163712994538631907798187850391801921009753035,
      102462659576709094466902874625942507586384897682649685070626246935815539699467
    );
  }

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
