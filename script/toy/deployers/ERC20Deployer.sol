// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";

/* 
This script deploys a testToken ERC20. Grants admin rights to `broadcaster`*/
/* Example:
NAME="Mangrove Testnet USDC token" \
SYMBOL=USDC \
DECIMALS=6 \
MINT_LIMIT=$(cast ff 6 10000) \
forge script --fork-url mumbai ERC20Deployer*/

contract ERC20Deployer is Deployer {
  function run() public {
    string memory symbol = vm.envString("SYMBOL");
    uint dec = vm.envUint("DECIMALS");
    require(uint8(dec) == dec, "Decimals overflow");
    broadcast();
    TestToken token = new TestToken({
      admin: broadcaster(),
      name: vm.envString("NAME"),
      symbol: symbol,
      _decimals: uint8(dec)
    });
    fork.set(symbol, address(token));
    broadcast();
    token.setMintLimit(vm.envUint("MINT_LIMIT"));
    outputDeployment();
    smokeTest(token);
  }

  function smokeTest(TestToken token) internal view {
    uint limit = token.mintLimit();
    require(limit == 0 || limit > 10 ** token.decimals(), "MintLimit is too low");
    require(token.mintLimit() < type(uint).max / 100000, "MintLimit is too high");
  }
}
