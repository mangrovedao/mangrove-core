// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/strategies/MangroveOrderEnriched.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder

  You can specify a mangrove address with the MANGROVE env var.*/
contract MangroveOrderDeployer is Deployer {
  MangroveOrderEnriched mgv_order;

  function run() public {
    address mangrove;
    // optionally read mangrove from environment
    try vm.envAddress("MANGROVE") returns (address _mangrove) {
      mangrove = _mangrove;
    } catch (bytes memory) {
      mangrove = fork.get("Mangrove");
    }
    innerRun({admin: broadcaster(), mangrove: mangrove});
  }

  /**
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(address admin, address mangrove) public {
    IMangrove mgv = IMangrove(payable(mangrove));

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
    mgv_order = new MangroveOrderEnriched(mgv, admin);
    fork.set("MangroveOrderEnriched", address(mgv_order));
    outputDeployment();
    console.log("Deployed!", address(mgv_order));
  }
}
