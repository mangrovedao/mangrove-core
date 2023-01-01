// SPDX-License-Identifier:	BSD-2-Clause

// CoreKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct, IMangrove, IERC20, MgvLib, MgvStructs} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandel} from "./AbstractKandel.sol";

abstract contract CoreKandel is Direct, AbstractKandel {
  ///@notice number of offers managed by this strat
  uint16 immutable NSLOTS;
  ///@notice base of the market Kandel is making
  IERC20 immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 immutable QUOTE;
  ///@notice `pendingBase` is the amount of free (not promised) base tokens in reserve
  uint public pendingBase;
  ///@notice `pendingQuote` is the amount of free quote tokens in reserve
  uint public pendingQuote;

  ///@notice maps index to offer id on Mangrove
  uint[][2] public _offerIdOfIndex;
  mapping(OrderType => mapping(uint => uint)) public _indexOfOfferId;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots) Direct(mgv, NO_ROUTER, gasreq) {
    NSLOTS = nslots;
    BASE = base;
    QUOTE = quote;
    _offerIdOfIndex[uint(OrderType.Bid)] = new uint[](NSLOTS);
    _offerIdOfIndex[uint(OrderType.Ask)] = new uint[](NSLOTS);
  }

  function getPending(OrderType ba) public view returns (uint pending) {
    pending = ba == OrderType.Ask ? pendingBase : pendingQuote;
  }

  function setPending(OrderType ba, uint amount) public mgvOrAdmin {
    if (ba == OrderType.Ask) {
      pendingBase = amount;
    } else {
      pendingQuote = amount;
    }
  }

  function offerIdOfIndex(OrderType ba, uint index) public view returns (uint) {
    return _offerIdOfIndex[uint(ba)][index];
  }

  function indexOfOfferId(OrderType ba, uint offerId) public view returns (uint) {
    return _indexOfOfferId[ba][offerId];
  }

  ///@notice how much price and volume distribution Kandel should give at given index
  ///@param ba whether Kandel is asking or bidding at this index
  ///@param index the distribution index
  function _givesOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Bid ? quoteOfIndex(index) : baseOfIndex(index);
  }

  ///@notice how much price and volume distribution Kandel should want at given index
  ///@param ba whether Kandel is asking or bidding at this index
  ///@param index the distribution index
  function _wantsOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Bid ? baseOfIndex(index) : quoteOfIndex(index);
  }

  ///@notice turns an order type into an (outbound, inbound) pair identifying an offer list
  ///@param ba whether one wishes to access the offer lists where asks or bids are posted
  function _tokenPairOfOrderType(OrderType ba) internal view returns (IERC20, IERC20) {
    return ba == OrderType.Bid ? (QUOTE, BASE) : (BASE, QUOTE);
  }

  ///@notice returns the Kandel order type of the offer list whose outbound token is given in argument
  ///@param outbound_tkn the outbound token of the offer list
  function _orderTypeOfOutbound(IERC20 outbound_tkn) internal view returns (OrderType) {
    return outbound_tkn == BASE ? OrderType.Ask : OrderType.Bid;
  }

  ///@notice retrieve offer data on Mangrove
  ///@param ba whether the offer is a Bid or an Ask
  ///@param index the distribution index of the offer
  function getOffer(OrderType ba, uint index)
    public
    view
    returns (MgvStructs.OfferPacked, MgvStructs.OfferDetailPacked)
  {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = _tokenPairOfOrderType(ba);
    uint offerId = offerIdOfIndex(ba, index);
    return (
      MGV.offers(address(outbound_tkn), address(inbound_tkn), offerId),
      MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerId)
    );
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param index the index of the distribution
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function _populateIndex(OrderType ba, uint index, OfferArgs memory args) internal returns (bytes32) {
    uint offerId = offerIdOfIndex(ba, index);
    if (offerId == 0 && args.gives > 0) {
      offerId = _newOffer(args);
      if (offerId == 0) {
        //FIXME `_newOffer` should return Mangrove's error message if `noRevert` is set
        return "newOffer/Failed";
      } else {
        _offerIdOfIndex[uint(ba)][index] = offerId;
        _indexOfOfferId[ba][offerId] = index;
        return REPOST_SUCCESS;
      }
    } else {
      if (args.gives == 0) {
        retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
        return "populateIndex/retracted";
      } else {
        return _updateOffer(args, offerId);
      }
    }
  }

  ///@notice publishes bids/asks in the distribution interval `[to,from[`
  ///@param from start index
  ///@param to end index
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param gasprice that should be used to compute the offer's provision
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  function populate(uint from, uint to, uint lastBidIndex, uint gasprice, uint[] calldata pivotIds)
    external
    payable
    onlyAdmin
  {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    for (uint index = from; index < to; index++) {
      OfferArgs memory args;
      OrderType ba = index <= lastBidIndex ? OrderType.Bid : OrderType.Ask;
      (args.outbound_tkn, args.inbound_tkn) = _tokenPairOfOrderType(ba);
      args.gives = _givesOfIndex(ba, index);
      args.wants = _wantsOfIndex(ba, index);
      args.fund = 0;
      args.noRevert = false;
      args.gasreq = offerGasreq();
      args.gasprice = gasprice;
      args.pivotId = pivotIds[index - from];
      _populateIndex(ba, index, args);
    }
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`
  ///@param from the start index
  ///@param to the end index
  ///@dev this simply provisions this contract's balance on Mangrove.
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs
  function retractOffers(uint from, uint to) external onlyAdmin {
    uint collected;
    for (uint index = from; index < to; index++) {
      (IERC20 outbound_tkn, IERC20 inbound_tkn) = _tokenPairOfOrderType(OrderType.Ask);
      collected +=
        MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex(OrderType.Ask, index), true);
      (outbound_tkn, inbound_tkn) = _tokenPairOfOrderType(OrderType.Bid);
      collected +=
        MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex(OrderType.Bid, index), true);
    }
  }

  ///@notice takes care of reposting residual offer in case of a partial fill and logging potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  ///@return notPublished the amount of liquidity that failed to be published on mangrove
  function _handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData) internal returns (uint notPublished) {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    // Offer failed to repost for bad reason, logging the incident
    if (repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS) {
      return 0;
    }
    if (repostStatus == "mgv/writeOffer/density/tooLow") {
      return __residualGives__(order);
    } else {
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
      return __residualGives__(order);
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    OrderType ba = _orderTypeOfOutbound(IERC20(order.outbound_tkn));
    // adds any unpublished liquidity to pending[Base/Quote]
    setPending(ba, _handleResidual(order, makerData));
    // preparing arguments for the dual maker order
    (OrderType dualBa, uint dualIndex, OfferArgs memory args) = _transportLogic(ba, order);
    return _populateIndex(dualBa, dualIndex, args);
  }
}
