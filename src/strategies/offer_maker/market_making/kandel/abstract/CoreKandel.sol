// SPDX-License-Identifier:	BSD-2-Clause

// CoreKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./Trade.sol";
import {DirectWithDistribution} from "./DirectWithDistribution.sol";

abstract contract CoreKandel is DirectWithDistribution {
  constructor(IMangrove mgv, uint gasreq, address owner) DirectWithDistribution(mgv, gasreq, owner) {}

  ///@notice takes care of status for reposting residual offer in case of a partial fill and logging of potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  ///@param repostStatus from the super posthook
  function handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData, bytes32 repostStatus) internal {
    if (
      repostStatus == COMPLETE_FILL || repostStatus == REPOST_SUCCESS
        || repostStatus == "mgv/writeOffer/density/tooLow"
    ) {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    } else {
      // Offer failed to repost for bad reason, logging the incident
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
    }
  }

  ///@notice takes care of status for populating dual and logging of potential issues.
  ///@param dualBa whether the offer is a bid or an ask
  ///@param viewDual the view Memoizer for the offer.
  ///@param args the argument of the offer.
  function handlePopulate(OfferType dualBa, SlotMemoizer memory viewDual, OfferArgs memory args, bytes32 populateStatus)
    internal
  {
    if (
      populateStatus == REPOST_SUCCESS || populateStatus == NEW_OFFER_SUCCESS
        || populateStatus == "mgv/writeOffer/density/tooLow"
    ) {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    }
    uint offerId = _offerId(dualBa, viewDual);
    if (offerId != 0) {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, offerId, "Kandel/updateOfferFailed", populateStatus);
    } else {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", populateStatus);
    }
  }

  ///@notice repost residual offer and dual offer according to transport logic
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32 populateStatus)
  {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    OfferType ba = OfferTypeOfOutbound(IERC20(order.outbound_tkn));
    handleResidual(order, makerData, repostStatus);

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (OfferType dualBa, SlotMemoizer memory viewDual, OfferArgs memory args) = transportLogic(ba, order);
    populateStatus = populateIndex(dualBa, viewDual, args);

    handlePopulate(dualBa, viewDual, args, populateStatus);
  }

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return baDual the type of offer that will re-invest inbound liquidity
  ///@return viewDual the view Memoizer for the dual offer
  ///@return args the argument for `populateIndex` specifying gives and wants
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OfferType baDual, SlotMemoizer memory viewDual, OfferArgs memory args);
}
