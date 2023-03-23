// SPDX-License-Identifier:	BSD-2-Clause

// ExplicitKandel.sol

// Copyright (c) 2023 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {ExplicitKandelState} from "./ExplicitKandelState.sol";
import {CoreKandel, OfferType} from "./CoreKandel.sol";

///@title Explicit Kandel storage

abstract contract ExplicitKandel is ExplicitKandelState, CoreKandel {
  constructor(uint gasreq, uint gasprice) ExplicitKandelState(gasreq, gasprice) {}

  function dualWantsGivesOfOffer(
    OfferType ba,
    uint dualOfferGives,
    MgvLib.SingleOrder calldata order,
    PriceIndex memory dualPriceIndex
  ) internal pure returns (uint wants, uint gives) {
    gives = dualOfferGives + order.gives;
    if (ba == OfferType.Bid) {
      // dual offer is an Ask so wants quote tokens
      wants = gives * dualPriceIndex.price / 10 ** PRICE_DECIMALS;
    } else {
      // dual offer is a Bid so wants base tokens
      wants = gives * (10 ** PRICE_DECIMALS / dualPriceIndex.price);
    }
  }

  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    view
    override
    returns (OfferType, OfferStatus memory, PriceIndex memory, OfferArgs memory)
  {
    mapping(uint => PriceIndex) storage dualPriceOfOfferId =
      ba == OfferType.Bid ? priceIndexOfAskOfferId_ : priceIndexOfBidOfferId_;
    PriceIndex memory p = dualPriceOfOfferId[order.offerId];
    OfferStatus memory s = offerStatusOfIndex_[p.index];
    // dualOfferId can be 0 if dual offer was not yet created
    // NB dualOfferId not being 0 does not mean the offer is live on Mangrove
    uint dualOfferId = ba == OfferType.Bid ? s.askId : s.bidId;

    OfferArgs memory args;
    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(dual(ba));
    // if OfferId == 0, dualOffer below has 0s everywhere
    MgvStructs.OfferPacked dualOffer = MGV.offers(address(args.outbound_tkn), address(args.inbound_tkn), dualOfferId);
    (args.wants, args.gives) = dualWantsGivesOfOffer(ba, dualOffer.gives() + s.pending, order, p);
    args.gasprice = s.gasprice;
    args.gasreq = s.gasreq;
    args.noRevert = true;
    args.pivotId = dualOffer.gives() > 0 ? dualOffer.next() : 0;
    return (dual(ba), s, p, args);
  }
}
