// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {BeefyCaller} from "mgv_test/lib/agents/BeefyCaller.sol";
import {IStrategyComplete} from "mgv_src/strategies/vendor/beefy/IStrategyComplete.sol";
import {console} from "forge-std/console.sol";

contract TetuCallerTest is MangroveTest {
  IERC20 internal usdt;

  PolygonFork internal fork;
  BeefyCaller internal caller;
  // Stargate USDT vault
  address internal constant VAULT = 0x1C480521100c962F7da106839a5A504B5A7457a1;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    usdt = IERC20(fork.get("USDT"));

    caller = new BeefyCaller(VAULT);
  }
}
