// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {Deployer} from "./lib/Deployer.sol";

/** @notice deploys a MangroveOrder instance
  ADMIN=$MUMBAI_TESTER_ADDRESS forge script --fork-url $MUMBAI_NODE_URL \
  --private-key $MUMBAI_TESTER_PRIVATE_KEY \
  --broadcast \
  --verify
  MangroveOrderDeployer
*/
contract MangroveOrderDeployer is Deployer {
  function run() public {
    innerRun({admin: vm.envAddress("ADMIN")});
  }

  /**
  @param admin address of the admin on Mango after deployment 
  */
  function innerRun(address admin) public {
    console.log("Deploying Mangrove Order...");
    IMangrove mgv = IMangrove(fork.get("Mangrove"));
    vm.broadcast();
    MangroveOrderEnriched mgv_order = new MangroveOrderEnriched(mgv, admin);
    fork.set("MangroveOrderEnriched", address(mgv_order));
    outputDeployment();
    console.log("Deployed!", address(mgv_order));
  }
}
