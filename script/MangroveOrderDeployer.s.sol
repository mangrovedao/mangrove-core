// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {Deployer} from "./lib/Deployer.sol";

/**
 * @notice deploys a MangroveOrder instance
 * @notice First test:
 * ADMIN=$MUMBAI_PRIVATE_ADDRESS forge script --fork-url mumbai MumbaiDeploy -vvv MangroveOrderDeployer
 * @notice Then broadcast and verify:
 * ADMIN=$MUMBAI_PRIVATE_ADDRESS WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
 */
contract MangroveOrderDeployer is Deployer {
  function run() public {
    innerRun({admin: vm.envAddress("ADMIN")});
  }

  /**
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(address admin) public {
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    MangroveOrderEnriched old_mgo = MangroveOrderEnriched(fork.get("MangroveOrderEnriched"));
    if (address(old_mgo) != address(0)) {
      uint bal = mgv.balanceOf(address(old_mgo));
      if (bal > 0) {
        broadcast();
        old_mgo.withdrawFromMangrove(bal, payable(admin));
        console.log("Retrieved ", bal, "WEIs from old deployment", address(old_mgo));
      }
    }
    console.log("Deploying Mangrove Order...");

    broadcast();
    MangroveOrderEnriched mgv_order = new MangroveOrderEnriched(mgv, admin);
    fork.set("MangroveOrderEnriched", address(mgv_order));
    require(mgv_order.MGV() == mgv, "Smoke test failed.");
    outputDeployment();
    console.log("Deployed!", address(mgv_order));
  }
}
