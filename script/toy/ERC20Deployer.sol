// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "mgv_src/MgvLib.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/* 
This script deploys a testToken ERC20. Grants admin rights to `msg.sender`*/
/* Example:
NAME="Mangrove Token" \
SYMBOL=MGV \
DECIMALS=18 \
forge script --fork-url mumbai ERC20Deployer*/

contract ERC20Deployer is Deployer {
  function run() public {
    string memory symbol = vm.envString("SYMBOL");
    uint dec = vm.envUint("DECIMALS");
    require(uint8(dec) == dec, "Decimals overflow");
    broadcast();
    TestToken token = new TestToken({
      admin: msg.sender,
      name: vm.envString("NAME"),
      symbol: symbol,
      _decimals: uint8(dec)
    });
    fork.set(symbol, address(token));
    outputDeployment();
  }
}
