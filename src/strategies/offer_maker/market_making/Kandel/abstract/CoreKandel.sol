// SPDX-License-Identifier:	BSD-2-Clause

// CoreKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {
  MangroveOffer,
  Direct,
  IMangrove,
  IERC20,
  MgvLib,
  MgvStructs
} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandel} from "./AbstractKandel.sol";

abstract contract CoreKandel is Direct, AbstractKandel {
  ///@notice number of offers managed by this strat
  uint16 public immutable NSLOTS;
  ///@notice base of the market Kandel is making
  IERC20 public immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 public immutable QUOTE;
  ///@notice `pendingBase` is the amount of free (not promised) base tokens in reserve
  uint128 public pendingBase;
  ///@notice `pendingQuote` is the amount of free (not promised) quote tokens in reserve
  uint128 public pendingQuote;

  ///@notice maps index to offer id on Mangrove. We use an array to be able to iterate over indexes
  uint[][2] public _offerIdOfIndex;
  mapping(OrderType => mapping(uint => uint)) public _indexOfOfferId;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots) Direct(mgv, NO_ROUTER, gasreq) {
    NSLOTS = nslots;
    BASE = base;
    QUOTE = quote;
    _offerIdOfIndex[uint(OrderType.Bid)] = new uint[](NSLOTS);
    _offerIdOfIndex[uint(OrderType.Ask)] = new uint[](NSLOTS);
    // approves Mangrove to pull base and quote token from this contract
    __activate__(base);
    __activate__(quote);
  }

  ///@notice liquidity available for increasing volume distribution at the next populated index
  ///@param ba whether populated index is bidding or asking
  ///@return pending liquidity in quote (for bids) or base (for asks)
  function getPending(OrderType ba) public view returns (uint pending) {
    pending = ba == OrderType.Ask ? pendingBase : pendingQuote;
  }

  ///@notice increments pending liquidity
  ///@param ba whether liquidity is used for bids or asks
  ///@param amount of liquidity in quote (for bids) or base (for asks)
  function pushPending(OrderType ba, uint amount) public mgvOrAdmin {
    require(uint128(amount) == amount, "Kandel/pendingOverflow");
    if (ba == OrderType.Ask) {
      pendingBase += uint128(amount);
    } else {
      pendingQuote += uint128(amount);
    }
  }

  ///@notice decrements pending liquidity
  ///@param ba whether liquidity is used for bids or asks
  ///@param amount of liquidity in quote (for bids) or base (for asks)
  function popPending(OrderType ba, uint amount) public mgvOrAdmin {
    require(uint128(amount) == amount, "Kandel/pendingOverflow");
    if (ba == OrderType.Ask) {
      pendingBase -= uint128(amount);
    } else {
      pendingQuote -= uint128(amount);
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

  ///@notice retracts the order at given index from Mangrove
  ///@param ba the order type
  ///@param index the index of the order
  ///@param deprovision whether one wishes to be credited free wei's on Mangrove's balance
  function retractOffer(OrderType ba, uint index, bool deprovision) public mgvOrAdmin returns (uint) {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = _tokenPairOfOrderType(ba);
    uint offerId = offerIdOfIndex(ba, index);
    return offerId == 0 ? 0 : retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  ///@notice retrieve offer data on Mangrove
  ///@param ba the order type
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

  ///@notice check whether given order is live on Mangrove
  ///@param ba the order type
  ///@param index the price index of the order
  ///@return live is true if the order is live on Mangrove
  function isLive(OrderType ba, uint index) public view returns (bool live) {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = _tokenPairOfOrderType(ba);
    uint offerId = offerIdOfIndex(ba, index);
    return offerId > 0 && MGV.isLive(MGV.offers(address(outbound_tkn), address(inbound_tkn), offerId));
  }

  ///@notice returns the dual order type
  ///@param ba whether the order is an ask or a bid
  ///@return dualBa is the dual order type (ask for bid and conversely)
  function dual(OrderType ba) public pure returns (OrderType dualBa) {
    return OrderType((uint(ba) + 1) % 2);
  }

  ///@notice returns a better (for Kandel) price index than the one given in argument
  ///@param ba whether Kandel is bidding or asking
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  function better(OrderType ba, uint index, uint step) public pure returns (uint) {
    return ba == OrderType.Ask ? index + step : index - step;
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param index the index of the distribution
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function _populateIndex(OrderType ba, uint index, OfferArgs memory args) internal returns (bytes32) {
    uint offerId = offerIdOfIndex(ba, index);
    if (isLive(dual(ba), index)) {
      // not populating index as this would cross the OB
      // storing pending liquidity
      pushPending(ba, args.gives);
      return "populate/crossed";
    }
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
      if (offerId == 0) {
        //offerId && gives are 0
        return "";
      }
      if (args.gives == 0) {
        retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
        return "populate/retracted";
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
  function retractOffers(uint from, uint to) external onlyAdmin returns (uint collected) {
    for (uint index = from; index < to; index++) {
      collected += retractOffer(OrderType.Ask, index, true);
      collected += retractOffer(OrderType.Bid, index, true);
    }
  }

  ///@notice takes care of reposting residual offer in case of a partial fill and logging potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  ///@return notPublished the amount of liquidity that failed to be published on mangrove
  function _handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData) internal returns (uint notPublished) {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    if (repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS) {
      return 0;
    }
    if (repostStatus == "mgv/writeOffer/density/tooLow") {
      return __residualGives__(order);
    } else {
      // Offer failed to repost for bad reason, logging the incident
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
      return __residualGives__(order);
    }
  }

  ///@notice repost residual offer and dual offer according to transport logic
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    OrderType ba = _orderTypeOfOutbound(IERC20(order.outbound_tkn));
    // adds any unpublished liquidity to pending[Base/Quote]
    pushPending(ba, _handleResidual(order, makerData));
    // preparing arguments for the dual maker order
    (OrderType dualBa, uint dualIndex, OfferArgs memory args) = _transportLogic(ba, order, makerData);
    return _populateIndex(dualBa, dualIndex, args);
  }

  ///@notice In case an offer failed to deliver, promised liquidity becomes pending, but offer is not reposted.
  ///@inheritdoc MangroveOffer
  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    OrderType ba = _orderTypeOfOutbound(IERC20(order.outbound_tkn));
    pushPending(ba, order.offer.gives());
    return "";
  }
}
