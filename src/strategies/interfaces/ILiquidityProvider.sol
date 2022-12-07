// SPDX-License-Identifier:	BSD-2-Clause

// ILiquidityProvider.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.0;

import "./IOfferLogic.sol";

///@title Completes IOfferLogic to provide an ABI for LiquidityProvider class of Mangrove's SDK

interface ILiquidityProvider is IOfferLogic {
  ///@notice creates a new offer on Mangrove.
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for inserting the offer in the list
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    external
    payable
    returns (uint);

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
}
