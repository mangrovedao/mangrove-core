// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Script2} from "mgv_lib/Script2.sol";
import {MangroveOrder} from "mgv_src/strategies/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Allows MangroveOrder to trade on the tokens given in argument.

    mgvOrder: address of MangroveOrder(Enriched) contract
    tkns: array of token addresses to activate
   
    The TKNS env variable should be given as a comma-separated list of names (known by ens).
    For instance:

  TKNS="DAI,USDC,WETH,DAI_AAVE,USDC_AAVE,WETH_AAVE" forge script --fork-url mumbai ActivateMangroveOrder*/

contract ActivateMangroveOrder is Deployer {
  function run() public {
    innerRun({mgvOrder: MangroveOrder(fork.get("MangroveOrderEnriched")), tkns: vm.envString("TKNS", ",")});
  }

  function innerRun(MangroveOrder mgvOrder, string[] memory tkns) public {
    console.log("Activating the following tokens on MangroveOrder (%s):", address(mgvOrder));
    IERC20[] memory iercs = new IERC20[](tkns.length);
    for (uint i = 0; i < tkns.length; i++) {
      iercs[i] = IERC20(fork.get(tkns[i]));
      console.log("%s (%s)", iercs[i].symbol(), address(iercs[i]));
    }
    broadcast();
    MangroveOrder(payable(mgvOrder)).activate(iercs);
    console.log("done!");
  }
}
