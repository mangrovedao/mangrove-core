// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {Ghost} from "mgv_src/toy_strategies/offer_maker/Ghost.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {Deployer} from "./lib/Deployer.sol";

/*  Deploys a Ghost instance
    First test:
 ADMIN=$MUMBAI_PRIVATE_ADDRESS forge script --fork-url mumbai GhostDeployer -vvv
    Then broadcast and verify:
 ADMIN=$MUMBAI_PRIVATE_ADDRESS WRITE_DEPLOY=true forge script --fork-url mumbai GhostDeployer -vvv --broadcast --verify
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
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(address admin, address base, address stable1, address stable2) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));

    try fork.get("Ghost") returns (address payable old_ghost_address) {
      Ghost old_ghost = Ghost(old_ghost_address);
      uint bal = mgv.balanceOf(old_ghost_address);
      if (bal > 0) {
        broadcast();
        old_ghost.withdrawFromMangrove(bal, payable(admin));
        console.log("Retrieved ", bal, "WEIs from old deployment", address(old_ghost));
      }
    } catch {
      console.log("No existing Ghost in ToyENS");
    }
    console.log("Deploying Ghost...");

    broadcast();
    Ghost ghost = new Ghost(mgv, IERC20(base), IERC20(stable1), IERC20(stable2), admin);
    fork.set("Ghost", address(ghost));
    require(ghost.MGV() == mgv, "Smoke test failed.");
    outputDeployment();
    console.log("Deployed!", address(ghost));
  }
}
