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
import {AbstractKandel} from "../abstract/AbstractKandel.sol";
import {TradesBaseQuotePair} from "../abstract/TradesBaseQuotePair.sol";
import {ExplicitKandelState, OfferType} from "./ExplicitKandelState.sol";
import {Direct, AbstractRouter} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

///@title Explicit Kandel contract

abstract contract ExplicitKandel is AbstractKandel, TradesBaseQuotePair, ExplicitKandelState, Direct {
  ///@notice The offer has too low volume to be posted.
  bytes32 internal constant LOW_VOLUME = "Kandel/volumeTooLow";

  constructor(
    IMangrove mgv,
    AbstractRouter router_,
    uint gasreq,
    uint gasprice,
    address reserveId,
    uint[] memory bidPrices,
    uint[] memory askPrices
  ) ExplicitKandelState(gasreq, gasprice, bidPrices, askPrices) Direct(mgv, router_, gasreq, reserveId) {}

  ///@notice returns wants and gives for the offer dual to the offer that is matched by the order given in argument
  ///@param ba the type of the offer matched by the taker order
  ///@param dualOfferGives what the dual offer already gives (including pending)
  ///@param order a recap of the taker order
  ///@param dualPrice the price at which the dual offer should be posted
  function dualWantsGivesOfOffer(OfferType ba, uint dualOfferGives, MgvLib.SingleOrder calldata order, uint dualPrice)
    internal
    pure
    returns (uint wants, uint gives)
  {
    gives = dualOfferGives + order.gives;
    if (ba == OfferType.Bid) {
      // dual offer is an Ask so wants quote tokens
      wants = gives * dualPrice / 10 ** PRICE_DECIMALS;
    } else {
      // dual offer is a Bid so wants base tokens
      wants = gives * (10 ** PRICE_DECIMALS / dualPrice);
    }
  }

  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    view
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
    (args.wants, args.gives) = dualWantsGivesOfOffer(ba, dualOffer.gives() + s.pending, order, p.dualPrice);
    args.gasprice = s.gasprice;
    args.gasreq = s.gasreq;
    args.noRevert = true;
    args.pivotId = dualOffer.gives() > 0 ? dualOffer.next() : 0;
    return (dual(ba), s, p, args);
  }

  function populateIndex(OfferType ba, OfferStatus memory s, PriceIndex memory p, OfferArgs memory args)
    internal
    returns (bytes32 result)
  {
    uint offerId = ba == OfferType.Ask ? s.askId : s.bidId;
    if (offerId == 0) {
      if (args.gives > 0 && args.wants > 0) {
        // create offer
        (offerId, result) = _newOffer(args);
        if (offerId != 0) {
          // adds the mapping  offerId => {p.index, dualBaPrice} to priceIndexOf[ba]OfferId
          setIndexMapping(ba, p.index, offerId);
        }
      } else {
        // else offerId && gives are 0 and the offer is left not posted
        result = LOW_VOLUME;
      }
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0 || args.wants == 0) {
        // This may happen in the following cases:
        // * `gives == 0` may not come from `DualWantsGivesOfOffer` computation, but `wants==0` might.
        // * `gives == 0` may happen from populate in case of re-population where the offers in the spread are then retracted by setting gives to 0.
        _retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
        result = LOW_VOLUME;
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume
        result = _updateOffer(args, offerId);
      }
    }
  }
}
