// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {console} from "forge-std/console.sol";
import {Script2} from "mgv_test/lib/Script2.sol";
import {MangroveOrder} from "mgv_src/periphery/MangroveOrder.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

/*  Allows MangroveOrder to trade on the tokens given in argument.

    mgvOrder: address of MangroveOrder(Enriched) contract
    tkns: array of token addresses to activate
   
    The TKNS env variable should be given as a comma-separated list of addresses.
    For instance, if you have the DAI and USDC env vars set:

      TKNS="$DAI,$USDC" forge script ...

*/

contract ActivateMangroveOrder is Script2, Deployer {
  function run() public {
    innerRun({
      mgvOrder: MangroveOrder(fork.get("MangroveOrderEnriched")),
      tkns: toIERC20(vm.envAddress("TKNS", ","))
    });
  }

  function innerRun(MangroveOrder mgvOrder, IERC20[] memory tkns) public {
    console.log("Activating the following tokens:");
    for (uint i = 0; i < tkns.length; i++) {
      console.log("%s (%s)", IERC20(tkns[i]).symbol(), address(tkns[i]));
    }
    broadcast();
    MangroveOrder(payable(mgvOrder)).activate(tkns);
  }
}
