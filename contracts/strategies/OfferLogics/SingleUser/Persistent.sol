// SPDX-License-Identifier:	BSD-2-Clause

// Persistent.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "./SingleUser.sol";

/** Strat class with specialized hooks that repost offer residual after a partial fill */
/** (Single user variant) */

abstract contract Persistent is SingleUser {
  /** Persistent class specific hooks. */

  // Hook that defines how much inbound tokens the residual offer should ask for when repositing itself on the Offer List.
  // default is to repost the old amount minus the partial fill
  function __residualWants__(ML.SingleOrder calldata order)
    internal
    virtual
    returns (uint)
  {
    return order.offer.wants() - order.gives;
  }

  // Hook that defines how much outbound tokens the residual offer should promise for when repositing itself on the Offer List.
  // default is to repost the old required amount minus the partial fill
  // NB this could produce an offer below the density. Offer Maker should perform a density check at repost time if not willing to fail reposting.
  function __residualGives__(ML.SingleOrder calldata order)
    internal
    virtual
    returns (uint)
  {
    return order.offer.gives() - order.wants;
  }

  // Specializing this hook to repost offer residual when trade was a success
  function __posthookSuccess__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    uint new_gives = __residualGives__(order);
    // Density check would be too gas costly.
    // We only treat the special case of `gives==0` (total fill).
    // Offer below the density will cause Mangrove to throw (revert is catched to log information)
    if (new_gives == 0) {
      return true;
    }
    uint new_wants = __residualWants__(order);
    try
      MGV.updateOffer(
        order.outbound_tkn,
        order.inbound_tkn,
        new_wants,
        new_gives,
        order.offerDetail.gasreq(),
        order.offerDetail.gasprice(),
        order.offer.next(),
        order.offerId
      )
    {
      return true;
    } catch (bytes memory reason) {
      // `newOffer` can fail when Mango is under provisioned or if `offer.gives` is below density
      // Log incident only if under provisioned
      if (keccak256(reason) == keccak256("mgv/insufficientProvision")) {
        emit LogIncident(
          MGV,
          IEIP20(order.outbound_tkn),
          IEIP20(order.inbound_tkn),
          order.offerId,
          "Persistent/hook/outOfProvision"
        );
      }
      return false;
    }
  }
}
