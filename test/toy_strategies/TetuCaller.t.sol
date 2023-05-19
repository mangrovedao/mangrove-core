// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {TetuCaller} from "mgv_test/lib/agents/TetuCaller.sol";
import {IController} from "mgv_src/strategies/vendor/tetu/IController.sol";
import {IStrategy} from "mgv_src/strategies/vendor/tetu/IStrategy.sol";
import {console} from "forge-std/console.sol";

contract TetuCallerTest is MangroveTest {
  IERC20 internal usdt;
  PolygonFork internal fork;
  TetuCaller caller;
  IController internal constant CONTROLLER = IController(0x6678814c273d5088114B6E40cC49C8DB04F9bC29);
  address internal constant GOVERNANCE = 0xcc16d636dD05b52FF1D8B9CE09B09BC62b11412B;
  // USDT vault with AAVE/DFORCE strategy
  // alwaysInvest <- false
  address internal constant USDTVAULT = 0xE680e0317402ad3CB37D5ed9fc642702658Ef57F;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();
    usdt = IERC20(fork.get("USDT"));
    caller = new TetuCaller(USDTVAULT);
    vm.prank(GOVERNANCE);
    CONTROLLER.changeWhiteListStatus(dynamic([address(caller)]), true);
    assertTrue(CONTROLLER.isAllowedUser(address(caller)), "White listing failed");
    logStatus();
  }

  function logStatus() internal view {
    string memory investStatus = "false";
    if (caller.VAULT().doHardWorkOnInvest()) {
      investStatus = "true";
    }
    console.log("* doHardWorkOnInvest:", investStatus);
    console.log("* overlying:", caller.OVERLYING().name());
    console.log("* In vault: ", toUnit(caller.VAULT().underlyingBalanceInVault(), 6), "USDT");
    console.log(
      "* strategy:",
      IStrategy(caller.VAULT().strategy()).STRATEGY_NAME(),
      toUnit(IStrategy(caller.VAULT().strategy()).underlyingBalance(), 6),
      "currently invested USDT"
    );
    console.log("* invest buffer:", toUnit(caller.VAULT().availableToInvestOut(), 6));
  }

  function test_doHardWork() public {
    depositFor(1000000, address(this));
    vm.startPrank(GOVERNANCE);
    _gas();
    caller.VAULT().doHardWork();
    gas_();
    vm.stopPrank();
    logStatus();
  }

  function test_can_talk_to_vault() public view {
    assert(address(caller.UNDERLYING()) != address(0));
  }

  function depositFor(uint amount, address onBehalf) internal {
    deal($(usdt), address(caller), amount * 10 ** 6);
    caller.approveLender(usdt, amount * 10 ** 6);
    caller.supply(amount * 10 ** 6, onBehalf);
  }
  // assume this is whitelisted

  function test_deposit_to_vault() public {
    uint balBefore = caller.OVERLYING().totalSupply();
    depositFor(1000000, address(this));
    uint balAfter = caller.OVERLYING().totalSupply();
    assertEq(balBefore + caller.OVERLYING().balanceOf(address(this)), balAfter, "Incorrect minted amount");
    assertEq(caller.UNDERLYING().balanceOf(address(this)), 0, "USDT not transferred");
    logStatus();
  }

  function test_withdraw_from_vault() public {}
}
