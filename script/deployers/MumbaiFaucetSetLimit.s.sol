// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import {console} from "forge-std/console.sol";

/**
 * updates the mint limit of a faucet on mumbai
 * usage:
 * TOKEN=WMATIC AMOUNT=$(cast ff 18 100000) forge script --fork-url mumbai MumbaiFaucetSetLimit
 */

contract MumbaiFaucetSetLimit is Deployer {
  function run() public {
    TestToken token = TestToken(envAddressOrName("TOKEN"));
    uint amount = vm.envUint("AMOUNT");
    require(amount < (type(uint).max / 100_000), "Too much minting required");
    broadcast();
    token.setMintLimit(amount);
    require(token.mintLimit() == amount, "smoke test failed");
  }
}
