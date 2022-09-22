// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrderEnriched, IERC20, IMangrove} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {Deployer} from "./lib/Deployer.sol";

/** @notice deploys a MangroveOrder instance */
// forge script --fork-url $MUMBAI_NODE_URL \
// --private-key $MUMBAI_DEPLOYER_PRIVATE_KEY \
// --sig "run(address, address)" \
// --etherscan-api-key $POLYGONSCAN_API \
// --verify \
// MangroveOrderDeployer \
// $MANGROVE \
// $MUMBAI_TESTER_ADDRESS

contract MangroveOrderDeployer is Deployer {
  /**
  @param mgv Address of Mangrove contract 
  @param admin address of the adim on Mango after deployment 
  */
  function run(address payable mgv, address admin) public {
    console.log("Deploying Mangrove Order...");
    broadcast();
    MangroveOrderEnriched mgv_order = new MangroveOrderEnriched(
      IMangrove(mgv),
      admin
    );
    outputDeployment();
    console.log("Deployed!", address(mgv_order));
  }
}
