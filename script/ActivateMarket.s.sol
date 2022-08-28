// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {MgvOracle} from "mgv_src/periphery/MgvOracle.sol";
import "mgv_src/Mangrove.sol";
import {ERC20} from "../test/lib/tokens/ERC20.sol";

import {ActivateSemibook} from "./ActivateSemibook.s.sol";

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

contract ActivateMarket is Script {
  function run(
    Mangrove mgv,
    address tkn1,
    address tkn2,
    uint tkn1_in_gwei,
    uint tkn2_in_gwei,
    uint fee
  ) public {
    new ActivateSemibook().run({
      mgv: mgv,
      outbound_tkn: tkn1,
      inbound_tkn: tkn2,
      outbound_in_gwei: tkn1_in_gwei,
      fee: fee
    });

    new ActivateSemibook().run({
      mgv: mgv,
      outbound_tkn: tkn2,
      inbound_tkn: tkn1,
      outbound_in_gwei: tkn2_in_gwei,
      fee: fee
    });
  }
}
