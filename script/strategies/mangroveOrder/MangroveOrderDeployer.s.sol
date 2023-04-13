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
  function run() public {
    address mgv = envHas("MANGROVE") ? envAddressOrName("MANGROVE") : fork.get("Mangrove");
    address governance = envHas("MgvGovernance") ? envAddressOrName("MgvGovernance") : broadcaster();

    innerRun({mangrove: mgv, admin: governance});
    outputDeployment();
  }

  /**
   * @param admin address of the admin on MangroveOrder after deployment
   */
  function innerRun(address admin, address mangrove) public {
    IMangrove mgv = IMangrove(payable(mangrove));
    MangroveOrder mgvOrder;
    // use 30K gasreq, this will be addeed to the SimpleRouter gasreq of 70K.
    // tests show that MangroveOrder requires 65K under normal circumstances.
    broadcast();
    if (forMultisig) {
      mgvOrder = new MangroveOrder{salt:salt}(mgv, admin, 30_000);
    } else {
      mgvOrder = new MangroveOrder(mgv, admin, 30_000);
    }
    fork.set("MangroveOrder", address(mgvOrder));
    fork.set("MangroveOrder-Router", address(mgvOrder.router()));
    smokeTest(mgvOrder, mgv);
  }

  function smokeTest(MangroveOrder mgvOrder, IMangrove mgv) internal view {
    require(mgvOrder.MGV() == mgv, "Incorrect Mangrove address");
  }
}
