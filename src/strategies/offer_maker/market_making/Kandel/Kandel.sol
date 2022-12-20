// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct, IMangrove, AbstractRouter, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";

contract Kandel is Direct {
  ///@notice number of price offers managed by this strat
  uint16 immutable NSLOTS;
  ///@notice base of the market Kandel is making
  IERC20 immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 immutable QUOTE;
  ///@notice quote distribution: `quoteOfIndex[i]` is the amount of quote tokens Kandel must give or want at index i
  uint[] quoteOfIndex;
  ///@notice quote distribution: `baseOfIndex[i]` is the amount of base tokens Kandel must give or want at index i
  uint[] baseOfIndex;
  ///@notice `pendingBase/Quote` that failed to be published and must be recycled when possible
  uint pendingBase;
  uint pendingQuote;

  ///@notice signals that the price has move beyond Kandel's current price range
  event AllAsks(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);
  event AllBids(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);

  ///@notice a bid or an ask
  enum OrderType {
    Bid,
    Ask
  }

  ///@notice maps index to offer id on Mangrove
  mapping(OrderType => mapping(uint => uint)) offerIdOfIndex;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots) Direct(mgv, NO_ROUTER, gasreq) {
    NSLOTS = nslots;
    BASE = base;
    QUOTE = quote;
  }

  ///@notice sets the base/quote distribution that Kandel should follow
  ///@param inQuotes whether this call is setting quote distribution
  ///@param from start index (included). Must be less than `to`.
  ///@param to end index (excluded). Must be less than `NSLOT`.
  ///@param slice the distrbution of base/quote in the interval [from, to[
  function setDistribution(bool inQuotes, uint from, uint to, uint[] calldata slice) external onlyAdmin {
    uint[] storage dist = inQuotes ? quoteOfIndex : baseOfIndex;
    uint cpt = 0;
    for (uint i = from; i < to; i++) {
      dist[i] = slice[cpt];
      cpt++;
    }
  }

  ///@notice how much price and volume distribution says Kandel should give at given index
  ///@param ba whether Kandel is asking or bidding at this index
  ///@param index the distribution index
  function _givesOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Ask ? quoteOfIndex[index] : baseOfIndex[index];
  }

  ///@notice how much price and volume distribution says Kandel should want at given index
  ///@param ba whether Kandel is asking or bidding at this index
  ///@param index the distribution index
  function _wantsOfIndex(OrderType ba, uint index) internal view returns (uint) {
    return ba == OrderType.Ask ? baseOfIndex[index] : quoteOfIndex[index];
  }

  ///@notice turns an order type into an (outbound, inbound) pair identifying an offer list
  ///@param ba whether one wishes to acces the offer lists where asks or bids are posted
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
    return (
      MGV.offers(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex[ba][index]),
      MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerIdOfIndex[ba][index])
    );
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param index the index of the distribution
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function _populateIndex(OrderType ba, uint index, OfferArgs memory args) internal returns (bytes32) {
    uint offerId = offerIdOfIndex[ba][index];
    if (offerId == 0) {
      offerId = _newOffer(args);
      if (offerId == 0) {
        return "newOffer/Failed";
      } else {
        offerIdOfIndex[ba][index] = offerId;
        return REPOST_SUCCESS;
      }
    } else {
      return _updateOffer(args, offerId);
    }
  }

  function populate(uint from, uint to, uint lastBidIndex, uint gasprice) external payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    for (uint index = from; index < to; index++) {
      OfferArgs memory args;
      OrderType ba = index <= lastBidIndex ? OrderType.Bid : OrderType.Ask;
      (args.outbound_tkn, args.inbound_tkn) = _tokenPairOfOrderType(ba);
      (args.gives, args.wants) =
        ba == OrderType.Bid ? (quoteOfIndex[index], baseOfIndex[index]) : (baseOfIndex[index], quoteOfIndex[index]);
      args.fund = 0;
      args.noRevert = true;
      args.gasreq = offerGasreq();
      args.gasprice = gasprice;
      _populateIndex(ba, index, args);
    }
  }

  ///@notice hooks that implements transport logic
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return dualBa the type of order implementing the transport
  ///@return dualIndex the distribution index where liquidity is transported
  ///@return args the argument for `populateIndex` specifying volume and price
  function __transportLogic__(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OrderType dualBa, uint dualIndex, OfferArgs memory args)
  {
    uint index = offerIdOfIndex[ba][order.offerId];
    if (index == 0) {
      emit AllAsks(MGV, BASE, QUOTE);
    }
    if (index == NSLOTS - 1) {
      emit AllBids(MGV, BASE, QUOTE);
    }
    (MgvStructs.OfferPacked dualOffer, MgvStructs.OfferDetailPacked dualOfferDetails) = getOffer(dualBa, dualIndex);

    (dualIndex, dualBa) = ba == OrderType.Ask ? (index - 1, OrderType.Bid) : (index + 1, OrderType.Ask);

    // can repost what the current taker order gives + what the dual offer already gives.
    uint maxDualGives = dualBa == OrderType.Ask
      ? dualOffer.gives() + order.gives + pendingBase
      : dualOffer.gives() + order.gives + pendingQuote;

    // what the distribution says the dual order should ask/bid
    uint shouldGive = _givesOfIndex(dualBa, dualIndex);
    uint shouldWant = _wantsOfIndex(dualBa, dualIndex);

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);
    args.gives = shouldGive > maxDualGives ? maxDualGives : shouldGive;
    // if giving less volume than distribution, one must adapts wants to match distribution price
    args.wants = args.gives == shouldGive ? shouldWant : (maxDualGives * shouldWant) / shouldGive;
    args.fund = 0;
    args.noRevert = true;
    args.gasreq = dualOfferDetails.gasreq();
    args.gasprice = dualOfferDetails.gasprice();
  }

  ///@notice takes care of reposting residual offer in case of a partial fill and logging potential issues.
  ///@param order a recap of the taker order
  ///@param ba whether the executer offer (order.offer) is a bid or an ask
  function _handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData, OrderType ba) internal {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    // Offer failed to repost for bad reason, logging the incident
    if (repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS) {
      return;
    }
    if (repostStatus == "mgv/writeOffer/density/tooLow") {
      uint givesBelowDensity = __residualGives__(order);
      if (ba == OrderType.Ask) {
        pendingBase += givesBelowDensity;
      } else {
        pendingQuote += givesBelowDensity;
      }
    } else {
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    OrderType ba = _orderTypeOfOutbound(IERC20(order.outbound_tkn));
    _handleResidual(order, makerData, ba);
    // preparing arguments for the dual maker order
    (OrderType ba_, uint index_, OfferArgs memory args) = __transportLogic__(ba, order);
    return _populateIndex(ba_, index_, args);
  }
}
