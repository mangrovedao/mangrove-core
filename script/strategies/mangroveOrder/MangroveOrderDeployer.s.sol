// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrder, IERC20, IMangrove} from "mgv_src/strategies/MangroveOrder.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Deploys a MangroveOrder instance
    First test:
 forge script --fork-url mumbai MangroveOrderDeployer -vvv 
    Then broadcast and verify:
 WRITE_DEPLOY=true forge script --fork-url mumbai MangroveOrderDeployer -vvv --broadcast --verify
    Remember to activate it using ActivateMangroveOrder

  You can specify a mangrove address with the MANGROVE env var.*/
contract MangroveOrderDeployer is Deployer {
  MangroveOrder mgv_order;

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
    console.log("Deploying Mangrove Order...");

    broadcast();
    mgv_order = new MangroveOrder(mgv, admin, 30_000);
    fork.set("MangroveOrder", address(mgv_order));
    fork.set("MangroveOrder-Router", address(mgv_order.router()));
    outputDeployment();
    console.log("Deployed!", address(mgv_order));
    console.log("Used mangrove is %s", mangrove);
    smokeTest(mgv_order, mgv);
  }

  function smokeTest(MangroveOrder mgvOrder, IMangrove mgv) internal view {
    require(mgvOrder.MGV() == mgv, "Incorrect Mangrove address");
  }
}
