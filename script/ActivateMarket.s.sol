// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import "mgv_src/Mangrove.sol";
import {ERC20} from "../test/lib/tokens/ERC20.sol";

import {ActivateSemibook} from "./ActivateSemibook.s.sol";
/* Example: activate (USDC,WETH) offer lists
 TKN1=USDC \
 TKN2=WETH \
 TKN1_IN_GWEI=$(cast tun 7.5ether gwei) \
 TKN2_IN_GWEI=$(cast tun 7.1 eth gwei) \
 FEE=30 \
 forge script --fork-url mumbai ActivateMarket
*/

contract ActivateMarket is Deployer {
  function run() public {
    innerRun({
      tkn1: getRawAddressOrName("TKN1"),
      tkn2: getRawAddressOrName("TKN2"),
      tkn1_in_gwei: vm.envUint("TKN1_IN_GWEI"),
      tkn2_in_gwei: vm.envUint("TKN2_IN_GWEI"),
      fee: vm.envUint("FEE")
    });
  }

  /* Activates a market on mangrove. Two semibooks are activated, one where the first tokens is outbound and the second inbound, and the reverse.
    mgv: mangrove address
    tkn1: first tokens
    tkn2: second tokens,
    tkn1_in_gwei: price of one tkn1 (display units) in gwei
    tkn2_in_gwei: price of one tkn2 (display units) in gwei
    fee: fee in per 10_000
  */

  /* 
    tknX_in_gwei should be obtained like this:
    1. Get the price of one tknX display unit in ETH, in display units
    2. Multiply by 10^9
    3. Round to nearest integer
  */
  function innerRun(address tkn1, address tkn2, uint tkn1_in_gwei, uint tkn2_in_gwei, uint fee) public {
    new ActivateSemibook().innerRun({
      outbound_tkn: tkn1,
      inbound_tkn: tkn2,
      outbound_in_gwei: tkn1_in_gwei,
      fee: fee
    });

    new ActivateSemibook().innerRun({
      outbound_tkn: tkn2,
      inbound_tkn: tkn1,
      outbound_in_gwei: tkn2_in_gwei,
      fee: fee
    });
  }
}
