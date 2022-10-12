// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.12;

import {IERC20} from "mgv_src/MgvLib.sol";
import {SumToken} from "mgv_src/token_adapters/SumToken.sol";
import {Deployer} from "../lib/Deployer.sol";

/* 
This script deploys a SumToken ERC20. Grants admin rights to `msg.sender`
*/
/* Example:
TOKEN_A="USDC" TOKEN_B="DAI" \
WRITE_DEPLOY=true \
  forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $MUMBAI_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  SumTokenDeployer
*/

contract SumTokenDeployer is Deployer {
  function run() public {
    address tokenA = fork.get(vm.envString("TOKEN_A"));
    address tokenB = fork.get(vm.envString("TOKEN_B"));

    broadcast();
    SumToken token = new SumToken(IERC20(tokenA), IERC20(tokenB));
    // smoke test
    require(token.decimals() == (IERC20(tokenA)).decimals(), "Smoke test failed");
    fork.set(token.symbol(), address(token));
    outputDeployment();
  }
}
