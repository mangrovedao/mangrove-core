// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ToyENS} from "mgv_lib/ToyENS.sol";

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";

import {console} from "forge-std/console.sol";

/**
 * Mints faucets to some address (within the mint limit)
 * Usage:
 * TOKEN=PxUSDC \
 * AMOUNT=$(cast ff 18 1000000) \
 * forge script --fork-url mumbai PolygonPxTokenMint
 */

contract PolygonPxTokenMint is Deployer {
  function run() public {
    TestToken token = TestToken(envAddressOrName("TOKEN"));
    uint old_bal = token.balanceOf(broadcaster());

    uint amount = vm.envUint("AMOUNT");
    broadcast();
    token.mint(amount);
    require(token.balanceOf(broadcaster()) == old_bal + amount, "smoke test failed");
  }
}
