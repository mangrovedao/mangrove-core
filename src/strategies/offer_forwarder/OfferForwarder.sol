// SPDX-License-Identifier:	BSD-2-Clause

// OfferForwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Forwarder, IMangrove, IERC20} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {SimpleRouter, AbstractRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";

contract OfferForwarder is ILiquidityProvider, Forwarder {
  constructor(IMangrove mgv, address deployer) Forwarder(mgv, new SimpleRouter(), 30_000) {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router_.setAdmin(deployer);
    }
  }

  /// @inheritdoc ILiquidityProvider
  function newOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice, // keeping gasprice here in order to expose the same interface as `OfferMaker` contracts.
    uint pivotId
  ) external payable returns (uint offerId) {
    gasprice; // ignoring gasprice that will be derived based on msg.value.
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false, // propagates Mangrove's revert data in case of newOffer failure
        owner: msg.sender
      })
    );
  }

  ///@inheritdoc ILiquidityProvider
  ///@dev the `gasprice` argument is always ignored in `Forwarder` logic, since it has to be derived from `msg.value` of the call (see `_newOffer`).
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq, // value ignored but kept to satisfy `OfferForwarder is ILiquidityProvider`
    uint gasprice, // value ignored but kept to satisfy `OfferForwarder is ILiquidityProvider`
    uint pivotId,
    uint offerId
  ) external payable override onlyOwner(outbound_tkn, inbound_tkn, offerId) {
    gasprice; // ssh
    gasreq; // ssh
    OfferArgs memory args;

    // funds to compute new gasprice is msg.value. Will use old gasprice if no funds are given
    // it might be tempting to include `od.weiBalance` here but this will trigger a recomputation of the `gasprice`
    // each time a offer is updated.
    args.fund = msg.value; // if inside a hook (Mangrove is `msg.sender`) this will be 0
    args.outbound_tkn = outbound_tkn;
    args.inbound_tkn = inbound_tkn;
    args.wants = wants;
    args.gives = gives;
    args.gasreq = type(uint).max; // this will force _updateOffer to use old gasreq of offer
    args.pivotId = pivotId;
    args.noRevert = false; // will throw if Mangrove reverts
    // weiBalance is used to provision offer
    _updateOffer(args, offerId);
  }
}
