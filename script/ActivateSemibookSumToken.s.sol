// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {ActivateSemibook} from "./ActivateSemibook.s.sol";
// FIXME: Document
/* 
  Activates a semibook with SumToken on Mangrove.
    outbound: outbound token
    inbound: inbound token,
    outbound_in_gwei: price of one outbound token (display units) in gwei
    fee: fee in per 10_000

  outbound_in_gwei should be obtained like this:
  1. Get the price of one outbound token display unit in ETH
  2. Multiply by 10^9
  3. Round to nearest integer
*/

contract ActivateSemibookSumToken is ActivateSemibook {
  function measureTransferGas(address tkn) internal override returns (uint) {
    // FIXME: Can we do something more sensible here?
    return 200_000;
  }
}
