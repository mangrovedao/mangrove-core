// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {TetuCaller} from "mgv_test/lib/agents/TetuCaller.sol";
import {IController} from "mgv_src/strategies/vendor/tetu/IController.sol";
import {IStrategy} from "mgv_src/strategies/vendor/tetu/IStrategy.sol";
import {IStrategySplitter} from "mgv_src/strategies/vendor/tetu/IStrategySplitter.sol";
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
    logStatus(false);
  }

  function logStatus(bool balanceOnly) internal view {
    IStrategy strategy = IStrategy(caller.VAULT().strategy());
    uint stratBalance = strategy.underlyingBalance();
    console.log("* In vault: ", toUnit(caller.VAULT().underlyingBalanceInVault(), 6), caller.UNDERLYING().name());
    console.log(
      "* strategy: %s %s [balance] %s [invested]",
      strategy.STRATEGY_NAME(),
      toUnit(stratBalance, 6),
      toUnit(strategy.investedUnderlyingBalance() - stratBalance, 6)
    );
    address[] memory strats = IStrategySplitter(caller.VAULT().strategy()).allStrategies();
    for (uint i; i < strats.length; i++) {
      console.log(
        "\t strat[%d]: %s",
        i,
        IStrategy(strats[i]).STRATEGY_NAME(),
        toUnit(IStrategy(strats[i]).investedUnderlyingBalance(), 6)
      );
    }
    console.log("* invest buffer:", toUnit(caller.VAULT().availableToInvestOut(), 6));
    if (!balanceOnly) {
      console.log("* doHardWorkOnInvest:", caller.VAULT().doHardWorkOnInvest());
      console.log("* lockAllowed:", caller.VAULT().lockAllowed());
      console.log("* lockPenalty:", caller.VAULT().lockPenalty());
    }
    console.log("----------------------");
  }

  function test_doHardWork() public {
    depositFor(1000000, address(this));
    vm.startPrank(GOVERNANCE);
    _gas();
    // call below transfers funds to strategy (splitter)
    caller.VAULT().doHardWork();
    gas_();
    vm.stopPrank();
    logStatus(true);
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
    logStatus(true);
  }

  function test_withdraw_from_vault() public {
    IERC20 tUSDT = caller.OVERLYING();
    // `this` receives tUSDT
    depositFor(1_000_000, address(this));
    uint tUSDTBal = tUSDT.balanceOf(address(this));
    uint USDTBal = usdt.balanceOf(address(this));
    logStatus(true);
    // since `this` is not approved by TETU governance, it cannot withdraw the tokens and needs to send tUSDT to caller first
    tUSDT.transfer(address(caller), tUSDTBal);
    caller.redeem(tUSDTBal, address(this));
    logStatus(true);
    assertApproxEqAbs(usdt.balanceOf(address(this)), 1_000_000 * 10 ** 6 + USDTBal, 10 ** 6);
  }

  function test_withdraw_from_strategy() public {
    IERC20 tUSDT = caller.OVERLYING();
    // `this` receives tUSDT
    depositFor(1_000_000, address(this));
    vm.startPrank(GOVERNANCE);
    caller.VAULT().doHardWork();
    vm.stopPrank();

    uint tUSDTBal = tUSDT.balanceOf(address(this));
    uint USDTBal = usdt.balanceOf(address(this));
    logStatus(true);
    // since `this` is not approved by TETU governance, it cannot withdraw the tokens and needs to send tUSDT to caller first
    tUSDT.transfer(address(caller), tUSDTBal);
    // this withdraws more than what's available in the vault
    // only the fraction of the strat funds that are necessary should be transfered (here 1_000_000)
    // but the smartVault overestimates what needs to be pulled from the strat
    // as a consequence all the funds of the strat are withdrawn to the vault!
    caller.redeem(tUSDTBal, address(this));
    logStatus(true);
    assertApproxEqAbs(usdt.balanceOf(address(this)), 1_000_000 * 10 ** 6 + USDTBal, 10 ** 6, "funds not received");
  }
}
