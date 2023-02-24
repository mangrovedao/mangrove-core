// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import "forge-std/StdStorage.sol";
import "forge-std/console.sol";

interface SmallERC20 {
  function decimals() external view returns (uint8);
}

contract GetTokenDealSlot is Deployer {
  using stdStorage for StdStorage;

  function run() public {
    address token = envAddressOrName("TOKEN");
    address account = envAddressOrName("ACCOUNT");
    uint slot = stdstore.target(token).sig(0x70a08231).with_key(account).find();
    console.log("slot: %s", vm.toString(bytes32(slot)));
    console.log("decimals: %s", SmallERC20(token).decimals());
  }
}
