// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import {console} from "forge-std/console.sol";

contract MumbaiFaucetMint is Deployer {
  function run() public {
    TestToken token = TestToken(envAddressOrName("TOKEN"));
    address to = vm.envAddress("TO");
    uint old_bal = token.balanceOf(to);

    uint amount = vm.envUint("AMOUNT");
    require(amount < (type(uint).max / 100_000), "Too much minting required");
    broadcast();
    token.mintTo(to, amount);
    require(token.balanceOf(to) == old_bal + amount, "smoke test failed");
  }
}
