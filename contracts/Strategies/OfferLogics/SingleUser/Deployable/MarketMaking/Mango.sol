// SPDX-License-Identifier:	BSD-2-Clause

// Mango.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "./Drupe.sol";
import "../../AaveV3Trader.sol";

/** Discrete automated market making strat */
/** This AMM is headless (no price model) and market makes on `NSLOTS` price ranges*/
/** current `Pmin` is the price of an offer at position `0`, current `Pmax` is the price of an offer at position `NSLOTS-1`*/
/** Initially `Pmin = P(0) = QUOTE_0/BASE_0` and the general term is P(i) = __quote_progression__(i)/BASE_0 */
/** NB `__quote_progression__` is a hook that defines how price increases with positions and is by default an arithmetic progression, i.e __quote_progression__(i) = QUOTE_0 + `current_delta`*i */
/** When one of its offer is matched on Mangrove, the headless strat does the following: */
/** Each time this strat receives b `BASE` tokens (bid was taken) at price position i, it increases the offered (`BASE`) volume of the ask at position i+1 of 'b'*/
/** Each time this strat receives q `QUOTE` tokens (ask was taken) at price position i, it increases the offered (`QUOTE`) volume of the bid at position i-1 of 'q'*/
/** In case of a partial fill of an offer at position i, the offer residual is reposted (see `Persistent` strat class)*/

contract Mango is Drupe, AaveV3Trader(2) {
  uint public base_buffer_target;
  uint public quote_buffer_target;

  constructor(
    address payable mgv,
    address base,
    address quote,
    uint base_0,
    uint quote_0,
    uint nslots,
    uint delta,
    address caller,
    address addressesProvider
  )
    Drupe(mgv, base, quote, base_0, quote_0, nslots, delta, caller)
    AaveV3Module(addressesProvider, 0)
  {}

  function set_buffer(bool base, uint buffer) internal onlyAdmin {
    if (base) {
      base_buffer_target = buffer;
    } else {
      quote_buffer_target = buffer;
    }
  }

  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    uint outbound_tkn_buffer_target = (order.outbound_tkn == BASE)
      ? base_buffer_target
      : quote_buffer_target;
    // if treasury is below target buffer, redeem on lender
    uint outbound_tkn_current_buffer = IEIP20(order.outbound_tkn).balanceOf(
      address(this)
    );
    if (outbound_tkn_current_buffer < outbound_tkn_buffer_target) {
      // redeems as many outbound tokens as `this` contract has overlyings.
      // redeem is deposited on `this` contract balance
      outbound_tkn_current_buffer += AaveV3Trader.__get__(
        type(uint).max,
        order
      );
      if (outbound_tkn_current_buffer >= amount) {
        return 0;
      }
    } else {
      return amount - redeemed;
    }
  }

  // NB no specific __put__ needed as inbound tokens should be deposited locally and will be moved to lender during posthook
  function __posthookSuccess__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    if (IEIP20(BASE).balanceOf(address(this)) > base_buffer_target) {}
  }
}
