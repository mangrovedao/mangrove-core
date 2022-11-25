// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Amplifier, AbstractRouter, IERC20, IMangrove} from "mgv_src/toy_strategies/offer_maker/Amplifier.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a Amplifier instance
    First test:
 ADMIN=$MUMBAI_PUBLIC_KEY forge script --fork-url mumbai AmplifierDeployer -vvv
    Then broadcast and verify:
 ADMIN=$MUMBAI_PUBLIC_KEY WRITE_DEPLOY=true forge script --fork-url mumbai AmplifierDeployer -vvv --broadcast --verify
    Remember to activate it using Activate*/
contract AmplifierDeployer is Deployer {
  function run() public {
    innerRun({
      admin: vm.envAddress("ADMIN"),
      base: fork.get("WETH"),
      stable1: fork.get("USDC"),
      stable2: fork.get("DAI")
    });
  }

  /**
   * @param admin address of the admin on Amplifier after deployment
   * @param base address of the base on Amplifier after deployment
   * @param stable1 address of the first stable coin on Amplifier after deployment
   * @param stable2 address of the second stable coin on Amplifier after deployment
   */
  function innerRun(address admin, address base, address stable1, address stable2) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));

    try fork.get("Amplifier") returns (address payable old_amplifier_address) {
      Amplifier old_amplifier = Amplifier(old_amplifier_address);
      uint bal = mgv.balanceOf(old_amplifier_address);
      if (bal > 0) {
        broadcast();
        old_amplifier.withdrawFromMangrove(bal, payable(admin));
      }
      uint old_balance = old_amplifier.admin().balance;
      broadcast();
      old_amplifier.retractOffers(true);
      uint new_balance = old_amplifier.admin().balance;
      console.log("Retrieved ", new_balance - old_balance + bal, "WEIs from old deployment", address(old_amplifier));
    } catch {
      console.log("No existing Amplifier in ToyENS");
    }
    console.log("Deploying Amplifier...");
    broadcast();
    Amplifier amplifier = new Amplifier(mgv, IERC20(base), IERC20(stable1), IERC20(stable2), admin );
    fork.set("Amplifier", address(amplifier));
    require(amplifier.MGV() == mgv, "Smoke test failed.");
    outputDeployment();
    console.log("Deployed!", address(amplifier));
    console.log("Activating Amplifier");
    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = IERC20(base);
    tokens[1] = IERC20(stable1);
    tokens[2] = IERC20(stable2);
    broadcast();
    amplifier.activate(tokens);
    AbstractRouter router = amplifier.router();
    broadcast();
    IERC20(base).approve(address(router), type(uint).max);
    IERC20[] memory tokens2 = new IERC20[](1);
    tokens2[0] = IERC20(base);
    vm.prank(amplifier.admin());
    amplifier.checkList(tokens2);
  }
}
