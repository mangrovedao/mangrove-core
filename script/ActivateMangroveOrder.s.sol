// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrder} from "mgv_src/periphery/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

/* Activates a MangroveOrder for some tokens. */

contract ActivateMangroveOrder is Script {
  function run(MangroveOrder mgvOrder, IERC20[] calldata tkns) public {
    vm.broadcast();
    mgvOrder.activate(tkns);
  }
}
