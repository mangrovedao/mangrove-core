// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer, console} from "./lib/Deployer.sol";
import {MangroveOrderEnriched} from "mgv_src/periphery/MangroveOrderEnriched.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

/** @notice Allows MangroveOrder to trade on the tokens given in argument.  */
// TOKENS="$WETH,$DAI,$USDC" forge script --fork-url $MUMBAI_NODE_URL \
// --private-key $MUMBAI_DEPLOYER_PRIVATE_KEY \
// --sig "run()" \
// --etherscan-api-key $POLYGONSCAN_API \
// --verify \
// ActivateMangroveOrder
contract ActivateMangroveOrder is Deployer {
  function run() public {
    (address $mgo, ) = ens.get("MangroveOrderEnriched");
    address[] memory tokens = vm.envAddress("TOKENS", ",");
    console.log("Will activate MangroveOrder", $mgo);
    for (uint i = 0; i < tokens.length; i++) {
      console.log(IERC20(tokens[i]).symbol(), "...");
    }
    vm.broadcast();
    MangroveOrderEnriched(payable($mgo)).activate(iercs(tokens));
  }
}
