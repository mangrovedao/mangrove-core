// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "src/periphery/MangroveOrderEnriched.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 ADMIN=$MUMBAI_PRIVATE_ADDRESS forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 ADMIN=$MUMBAI_PRIVATE_ADDRESS WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder
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
    try fork.get("MangroveOrderEnriched") returns (address payable old_mgo_address) {
      MangroveOrderEnriched old_mgo = MangroveOrderEnriched(old_mgo_address);
      uint bal = mgv.balanceOf(old_mgo_address);
      if (bal > 0) {
        broadcast();
        old_mgo.withdrawFromMangrove(bal, payable(admin));
        console.log("Retrieved ", bal, "WEIs from old deployment", address(old_mgo));
      }
    } catch {
      console.log("No existing Mangrove Order in ToyENS");
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
