// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Ghost, AbstractRouter, IERC20, IMangrove} from "mgv_src/toy_strategies/offer_maker/Ghost.sol";
import {Deployer} from "./lib/Deployer.sol";

/*  Deploys a Ghost instance
    First test:
 ADMIN=$MUMBAI_PUBLIC_KEY forge script --fork-url mumbai GhostDeployer -vvv
    Then broadcast and verify:
 ADMIN=$MUMBAI_PUBLIC_KEY WRITE_DEPLOY=true forge script --fork-url mumbai GhostDeployer -vvv --broadcast --verify
    Remember to activate it using Activate
*/
contract GhostDeployer is Deployer {
  function run() public {
    innerRun({
      admin: vm.envAddress("ADMIN"),
      base: fork.get("WETH"),
      stable1: fork.get("USDC"),
      stable2: fork.get("DAI")
    });
  }

  /**
   * @param admin address of the admin on Ghost after deployment
   * @param base address of the base on Ghost after deployment
   * @param stable1 address of the first stable coin on Ghost after deployment
   * @param stable2 address of the second stable coin on Ghost after deployment
   */
  function innerRun(address admin, address base, address stable1, address stable2) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));

    try fork.get("Ghost") returns (address payable old_ghost_address) {
      Ghost old_ghost = Ghost(old_ghost_address);
      uint bal = mgv.balanceOf(old_ghost_address);
      if (bal > 0) {
        broadcast();
        old_ghost.withdrawFromMangrove(bal, payable(admin));
      }
      uint old_balance = old_ghost.admin().balance;
      broadcast();
      old_ghost.retractOffers(true);
      uint new_balance = old_ghost.admin().balance;
      console.log("Retrieved ", new_balance - old_balance + bal, "WEIs from old deployment", address(old_ghost));
    } catch {
      console.log("No existing Ghost in ToyENS");
    }
    console.log("Deploying Ghost...");
    broadcast();
    Ghost ghost = new Ghost(mgv, IERC20(base), IERC20(stable1), IERC20(stable2), admin );
    fork.set("Ghost", address(ghost));
    require(ghost.MGV() == mgv, "Smoke test failed.");
    outputDeployment();
    console.log("Deployed!", address(ghost));
    console.log("Activating Ghost");
    IERC20[] memory tokens = new IERC20[](3);
    tokens[0] = IERC20(base);
    tokens[1] = IERC20(stable1);
    tokens[2] = IERC20(stable2);
    broadcast();
    ghost.activate(tokens);
    AbstractRouter router = ghost.router();
    broadcast();
    IERC20(base).approve(address(router), type(uint).max);
    IERC20[] memory tokens2 = new IERC20[](1);
    tokens2[0] = IERC20(base);
    vm.prank(ghost.admin());
    ghost.checkList(tokens2);
  }
}
