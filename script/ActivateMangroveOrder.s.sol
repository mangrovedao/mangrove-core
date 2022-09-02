// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";
import {MangroveOrder} from "mgv_src/periphery/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

/* Allows MangroveOrder to trade on the tokens given in argument. */

contract ActivateMangroveOrder is Script {
  function run(MangroveOrder mgvOrder, IERC20[] calldata tkns) public {
    console.log("Will activate MangroveOrder. Verifying token addresses...");
    for (uint i = 0; i < tkns.length; i++) {
      console.log(tkns[i].symbol(), "...");
    }
    vm.broadcast();
    mgvOrder.activate(tkns);
  }
}
