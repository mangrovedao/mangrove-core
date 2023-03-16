// SPDX-License-Identifier:	BSD-2-Clause

// ILiquidityProvider.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IOfferLogic} from "./IOfferLogic.sol";

///@title Completes IOfferLogic to provide an ABI for LiquidityProvider class of Mangrove's SDK

interface ILiquidityProvider is IOfferLogic {
  ///@notice creates a new offer on Mangrove.
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for inserting the offer in the list
  ///@return offerId the Mangrove offer id.
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    external
    payable
    returns (uint offerId);

  ///@notice creates a new offer on Mangrove with an override for gas requirement
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for inserting the offer in the list
  ///@param gasreq the gas required by the offer logic
  ///@return offerId the Mangrove offer id.
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq)
    external
    payable
    returns (uint offerId);

  ///@notice updates an offer existing on Mangrove (not necessarily live).
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the new amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the new amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for re-inserting the offer in the list (use `offerId` if updated offer is live)
  ///@param offerId the id of the offer in the offer list.
  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    external
    payable;

  ///@notice updates an offer existing on Mangrove (not necessarily live) with an override for gas requirement
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the new amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the new amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for re-inserting the offer in the list (use `offerId` if updated offer is live)
  ///@param offerId the id of the offer in the offer list.
  ///@param gasreq the gas required by the offer logic
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq
  ) external payable;

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    external
    returns (uint freeWei);
}
