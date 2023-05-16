// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {TetuCaller} from "mgv_test/lib/agents/TetuCaller.sol";
import {IController} from "mgv_src/strategies/vendor/tetu/IController.sol";
import {console} from "forge-std/console.sol";

contract TetuCallerTest is MangroveTest {
  IERC20 internal usdt;
  PolygonFork internal fork;
  TetuCaller caller;
  IController controller;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    usdt = IERC20(fork.get("USDT"));
    caller = new TetuCaller(0xE680e0317402ad3CB37D5ed9fc642702658Ef57F);
    controller = IController(0x6678814c273d5088114B6E40cC49C8DB04F9bC29);
    vm.prank(0xcc16d636dD05b52FF1D8B9CE09B09BC62b11412B);
    controller.changeWhiteListStatus(dynamic([address(caller)]), true);
    assertTrue(controller.isAllowedUser(address(caller)), "White listing failed");
  }

  function test_can_talk_to_vault() public view {
    assert(address(caller.underlying()) != address(0));
  }

  // assume this is whitelisted
  function test_deposit_to_vault() public {
    deal($(usdt), address(caller), 1000 * 10 ** 18);
    caller.approveLender(usdt, type(uint).max);
    _gas();
    caller.supply(1000 * 10 ** 18, address(this));
    gas_();
  }
}
