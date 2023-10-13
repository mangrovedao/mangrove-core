// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "@mgv/script/lib/Deployer.sol";
import "@mgv/forge-std/StdStorage.sol";
import "@mgv/forge-std/console.sol";

interface SmallERC20 {
  function decimals() external view returns (uint8);
}

contract GetTokenDealSlot is Deployer {
  using stdStorage for StdStorage;

  /* Read the storage slot used by a token to remember an account's balance.
  Uses stdstore to do the following:
  1. Record storage accesses.
  2. Call token.balanceOf(account) (signature of balanceOf: 0x70a08231) .
  3. Log the slot that was read during the call to balanceOf.
  4. For convenience, also log the number of decimals used by the token.

  The script is intended to be used as follows:
  1. Given an anvil node running (with --fork-url <SOME_NODE>)
  2. Run

      forge script GetTokenDealSlot -vv

  3. Parse output for slot: <slot>
  4. Run

      cast rpc anvil_setStorageAt <token> <slot> <amount>
      (or directly do a json-rpc request from e.g. javascript)

  */
  function run() public {
    address token = envAddressOrName("TOKEN");
    address account = envAddressOrName("ACCOUNT");
    uint slot = stdstore.target(token).sig(0x70a08231).with_key(account).find();
    console.log("slot: %s", vm.toString(bytes32(slot)));
    console.log("decimals: %s", SmallERC20(token).decimals());
  }
}
