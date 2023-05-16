// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {MangroveOrder} from "mgv_src/strategies/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Allows MangroveOrder to trade on the tokens given in argument.

    mgvOrder: address of MangroveOrder contract
    tkns: array of token addresses to activate
   
    The TKNS env variable should be given as a comma-separated list of names (known by ens) or addresses.
    For instance:

  TKNS="DAI,USDC,WETH,DAI_AAVE,USDC_AAVE,WETH_AAVE" forge script --fork-url mumbai ActivateMangroveOrder*/

contract ActivateMangroveOrder is Deployer {
  function run() public {
    string[] memory tkns = vm.envString("TKNS", ",");
    IERC20[] memory iercs = new IERC20[](tkns.length);
    for (uint i = 0; i < tkns.length; ++i) {
      iercs[i] = IERC20(envAddressOrName(tkns[i]));
    }

    innerRun({
      mgvOrder: MangroveOrder(envAddressOrName("MANGROVE_ORDER", "MangroveOrder")),
      iercs: iercs
    });
  }

  function innerRun(MangroveOrder mgvOrder, IERC20[] memory iercs) public {
    console.log("MangroveOrder (%s) is acting of Mangrove (%s)", address(mgvOrder), address(mgvOrder.MGV()));
    console.log("Activating tokens...");
    for (uint i = 0; i < iercs.length; ++i) {
      console.log("%s (%s)", iercs[i].symbol(), address(iercs[i]));
    }
    broadcast();
    mgvOrder.activate(iercs);
    console.log("done!");
  }
}
