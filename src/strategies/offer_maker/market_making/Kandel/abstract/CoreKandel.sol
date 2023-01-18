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
  ///@notice base of the market Kandel is making
  IERC20 public immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 public immutable QUOTE;

  Params public params;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice) Direct(mgv, NO_ROUTER, gasreq) {
    BASE = base;
    QUOTE = quote;
    require(uint16(gasprice) == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = uint16(gasprice);

    // approves Mangrove to pull base and quote token from this contract
    __activate__(base);
    __activate__(quote);
  }

  function setCompoundRate(uint16 c) public mgvOrAdmin {
    require(c <= 10 ** PRECISION, "Kandel/invalidCompoundRate");
    emit SetCompoundRate(MGV, BASE, QUOTE, c);
    params.compoundRate = c;
  }

  function length() public view returns (uint) {
    return params.length;
  }

  ///@notice increments pending liquidity
  ///@param ba whether liquidity is used for bids or asks
  ///@param amount of liquidity in quote (for bids) or base (for asks)
  function pushPending(OrderType ba, uint amount) internal {
    require(uint96(amount) == amount, "Kandel/pendingOverflow");
    if (amount == 0) return;
    if (ba == OrderType.Ask) {
      params.pendingBase += uint96(amount);
    } else {
      params.pendingQuote += uint96(amount);
    }
  }

  ///@notice decrements pending liquidity
  ///@param ba whether liquidity is used for bids or asks
  ///@param amount of liquidity in quote (for bids) or base (for asks)
  function popPending(OrderType ba, uint amount) internal mgvOrAdmin {
    require(uint96(amount) == amount, "Kandel/pendingOverflow");
    if (amount == 0) return;
    if (ba == OrderType.Ask) {
      require(params.pendingBase >= amount, "Kandel/NotEnoughBase");
      params.pendingBase -= uint96(amount);
    } else {
      require(params.pendingQuote >= amount, "Kandel/NotEnoughQuote");
      params.pendingQuote -= uint96(amount);
    }
  }

  ///@notice turns an order type into an (outbound, inbound) pair identifying an offer list
  ///@param ba whether one wishes to access the offer lists where asks or bids are posted
  function tokenPairOfOrderType(OrderType ba) internal view returns (IERC20, IERC20) {
    return ba == OrderType.Bid ? (QUOTE, BASE) : (BASE, QUOTE);
  }

  ///@notice returns the Kandel order type of the offer list whose outbound token is given in argument
  ///@param outbound_tkn the outbound token of the offer list
  function orderTypeOfOutbound(IERC20 outbound_tkn) internal view returns (OrderType) {
    return outbound_tkn == BASE ? OrderType.Ask : OrderType.Bid;
  }

  function wantsGivesOfBaseQuote(OrderType ba, uint baseAmount, uint quoteAmount)
    internal
    pure
    returns (uint wants, uint gives)
  {
    if (ba == OrderType.Ask) {
      wants = quoteAmount;
      gives = baseAmount;
    } else {
      wants = baseAmount;
      gives = quoteAmount;
    }
  }

  ///@notice retracts the order at given index from Mangrove
  ///@param ba the order type
  ///@param v view monad for `ba` at `index`
  ///@param deprovision whether one wishes to be credited free wei's on Mangrove's balance
  function retractOffer(OrderType ba, SlotViewMonad memory v, bool deprovision) internal returns (uint) {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = tokenPairOfOrderType(ba);
    return _offerId(ba, v) == 0 ? 0 : retractOffer(outbound_tkn, inbound_tkn, _offerId(ba, v), deprovision);
  }

  ///@notice returns the dual order type
  ///@param ba whether the order is an ask or a bid
  ///@return dualBa is the dual order type (ask for bid and conversely)
  function dual(OrderType ba) public pure returns (OrderType dualBa) {
    return OrderType((uint(ba) + 1) % 2);
  }

  function dualWantsGivesOfOrder(
    OrderType ba_dual,
    SlotViewMonad memory v_dual,
    MgvLib.SingleOrder calldata order,
    Params memory params_
  ) internal view returns (uint wants, uint gives, uint pending_) {
    // computing gives/wants for dual offer
    // we verify we cannot overflow if PRECISION < 6
    // spread:8
    uint spread = uint(params_.spread);
    // compoundRate:16
    uint compoundRate = uint(params_.compoundRate);
    // params.ratio:16, spread:8 ==> r:128
    uint r = uint(params_.ratio) ** spread;
    // log2(10) = 3.32 => p:PRECISION*3.32
    uint p = 10 ** PRECISION;
    // (p-compoundRate) * p**spread ~ p ** (spread + 1) : 9 * 3.32 * PRECISION
    // compoundRate:16, r:128 => compoundRate * r : 144
    // order.gives:96 => gives : max(9*3.32*PRECISION+96, 240) which will not overflow if PRECISION < 6
    // r:128, p:PRECISION*3.32 => r*p:128+PRECISION*3.32 => gives:  max(9*3.32*PRECISION+96, 240) / (128+PRECISION*3.32)
    // for PRECISION=4 we have gives ~ 240 - 142 => gives:98
    gives = (order.gives * ((p - compoundRate) * p ** spread + compoundRate * r)) / (r * p);

    pending_ = order.gives - gives;
    // adding to gives what the offer was already giving
    // gives:98 _offer(..).gives:96
    // gives:99
    gives += _offer(ba_dual, v_dual).gives();
    // adjusting wants to price:
    // gives: 99, r:128 => gives * r : 227
    // order.gives * p**spread: 8*PRECISION*3.32 + 96 = 203 (for PRECISION = 4)
    // (gives  * r) / (order.gives * (p ** spread)) : 24
    // wants : 24 + 98 = 122
    wants = order.wants * ((gives * r) / (order.gives * (p ** spread)));
  }

  ///@notice returns a better (for Kandel) price index than the one given in argument
  ///@param ba whether Kandel is bidding or asking
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  function better(OrderType ba, uint index, uint step, uint length_) public pure returns (uint) {
    return ba == OrderType.Ask
      ? index + step >= length_ ? length_ - 1 : index + step
      : int(index) - int(step) < 0 ? 0 : index - step;
  }

  function _fresh(uint index) internal pure returns (SlotViewMonad memory v) {
    v.index_ = true;
    v.index = index;
    return v;
  }

  function _offerId(OrderType ba, SlotViewMonad memory v) internal view returns (uint) {
    if (v.offerId_) {
      return v.offerId;
    } else {
      require(v.index_, "Kandel/monad/UninitializedIndex");
      v.offerId_ = true;
      v.offerId = offerIdOfIndex(ba, v.index);
      return v.offerId;
    }
  }

  function _index(OrderType ba, SlotViewMonad memory v) internal view returns (uint) {
    if (v.index_) {
      return v.index;
    } else {
      require(v.offerId_, "Kandel/monad/UninitializedOfferId");
      v.index_ = true;
      v.index = indexOfOfferId(ba, v.offerId);
      return v.index;
    }
  }

  function _offer(OrderType ba, SlotViewMonad memory v) internal view returns (MgvStructs.OfferPacked) {
    if (v.offer_) {
      return v.offer;
    } else {
      v.offer_ = true;
      uint id = _offerId(ba, v);
      (IERC20 outbound, IERC20 inbound) = tokenPairOfOrderType(ba);
      v.offer = MGV.offers(address(outbound), address(inbound), id);
      return v.offer;
    }
  }

  function _offerDetail(OrderType ba, SlotViewMonad memory v) internal view returns (MgvStructs.OfferDetailPacked) {
    if (v.offerDetail_) {
      return v.offerDetail;
    } else {
      v.offerDetail_ = true;
      uint id = _offerId(ba, v);
      (IERC20 outbound, IERC20 inbound) = tokenPairOfOrderType(ba);
      v.offerDetail = MGV.offerDetails(address(outbound), address(inbound), id);
      return v.offerDetail;
    }
  }

  function getOffer(OrderType ba, uint index)
    external
    view
    returns (MgvStructs.OfferPacked offer, MgvStructs.OfferDetailPacked offerDetail)
  {
    uint offerId = offerIdOfIndex(ba, index);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOrderType(ba);
    offer = MGV.offers(address(outbound), address(inbound), offerId);
    offerDetail = MGV.offerDetails(address(outbound), address(inbound), offerId);
  }

  function pending(OrderType ba) public view returns (uint) {
    return ba == OrderType.Ask ? params.pendingBase : params.pendingQuote;
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Monad for the offer to be published
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndex(OrderType ba, SlotViewMonad memory v, OfferArgs memory args) internal returns (int delta) {
    uint offerId = _offerId(ba, v);
    if (offerId == 0 && args.gives > 0) {
      (uint offerId_, bytes32 result) = _newOffer(args);
      if (offerId_ == 0) {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", result);
        return 0;
      } else {
        offerIdOfIndex(ba, _index(ba, v), offerId_);
        indexOfOfferId(ba, offerId_, _index(ba, v));
        return -int(args.gives);
      }
    } else {
      if (offerId == 0) {
        //offerId && gives are 0
        return 0;
      }
      // when gives is 0 we retract offer
      if (args.gives == 0) {
        retractOffer(ba, v, false);
        return int(_offer(ba, v).gives());
      } else {
        bytes32 result = _updateOffer(args, offerId);
        if (result != REPOST_SUCCESS) {
          emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/updateOfferFailed", result);
          return int(_offer(ba, v).gives() + args.gives);
        }
        return int(_offer(ba, v).gives()) - int(args.gives);
      }
    }
  }

  struct HeapVarsPopulate {
    uint quote_i;
    int deltaQuote;
    int deltaBase;
    int delta;
    uint from;
    uint to;
    uint lastBidIndex;
    uint gasprice;
    uint ratio;
  }

  function iterPopulate(HeapVarsPopulate memory vars, uint[] calldata baseDist, uint[] calldata pivotIds) internal {
    for (uint index = vars.from; index < vars.to; index++) {
      OfferArgs memory args;

      OrderType ba = index <= vars.lastBidIndex ? OrderType.Bid : OrderType.Ask;
      (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOrderType(ba);
      (args.wants, args.gives) = wantsGivesOfBaseQuote(ba, baseDist[index - vars.from], vars.quote_i);
      args.fund = 0;
      args.noRevert = false;
      args.gasreq = offerGasreq();
      args.gasprice = vars.gasprice;
      args.pivotId = pivotIds[index - vars.from];

      if (ba == OrderType.Ask) {
        vars.deltaBase += populateIndex(ba, _fresh(index), args);
      } else {
        vars.deltaQuote += populateIndex(ba, _fresh(index), args);
      }
      vars.quote_i = (vars.quote_i * uint(vars.ratio)) / 10 ** PRECISION;
    }
  }

  ///@notice publishes bids/asks in the distribution interval `[to,from[`
  ///@param from start in dex
  ///@param to end index
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@dev This function must be called w/o changing ratio
  ///@dev `from` > 0 must imply `initQuote` >= quote amount given/wanted at index from-1
  ///@dev msg.value must be enough to provision all posted offers
  ///@dev pendingBase and pendingQuote must have enough funds to cover all delta in offer.gives
  function populate(
    uint from,
    uint to,
    uint lastBidIndex,
    uint kandelSize,
    uint16 ratio,
    uint8 spread,
    uint initQuote, // quote given/wanted at index from
    uint[] calldata baseDist, // base distribution in [from, to[
    uint[] calldata pivotIds // pivots for {offer[from],...,offer[to-1]}
  ) external payable onlyAdmin {
    Params memory params_ = params;
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    require(from < to && to <= kandelSize, "Kandel/invalidInterval");
    // Initializing arrays and parameters if needed
    if (params_.length != kandelSize) {
      require(kandelSize <= type(uint8).max, "Kandel/TooManyPricePoints");
      offerIdOfIndex_[uint(OrderType.Bid)] = new uint[](kandelSize);
      offerIdOfIndex_[uint(OrderType.Ask)] = new uint[](kandelSize);
      params.length = uint8(kandelSize);
    }
    if (params_.ratio != ratio) {
      require(ratio >= 10 ** PRECISION, "Kandel/invalidRatio");
      params.ratio = ratio;
    }
    if (params_.spread != spread) {
      require(spread > 0, "Kandel/invalidSpread");
      params.spread = spread;
    }

    HeapVarsPopulate memory vars = HeapVarsPopulate({
      quote_i: initQuote,
      from: from,
      to: to,
      lastBidIndex: lastBidIndex,
      ratio: params.ratio,
      gasprice: params.gasprice,
      deltaQuote: int(0),
      deltaBase: int(0),
      delta: int(0)
    });

    iterPopulate(vars, baseDist, pivotIds);

    // call below verify that Kandel has enough base/quote to fullfill the offer it has posted.
    if (vars.deltaBase > 0) {
      pushPending(OrderType.Ask, uint(vars.deltaBase));
    } else {
      popPending(OrderType.Ask, uint(-vars.deltaBase));
    }
    if (vars.deltaQuote > 0) {
      pushPending(OrderType.Bid, uint(vars.deltaQuote));
    } else {
      popPending(OrderType.Bid, uint(-vars.deltaQuote));
    }
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`
  ///@param from the start index
  ///@param to the end index
  ///@dev this simply provisions this contract's balance on Mangrove.
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs
  function retractOffers(uint from, uint to) external onlyAdmin returns (uint collected) {
    for (uint index = from; index < to; index++) {
      SlotViewMonad memory v_ask = _fresh(index);
      SlotViewMonad memory v_bid = _fresh(index);
      collected += retractOffer(OrderType.Ask, v_ask, true);
      collected += retractOffer(OrderType.Bid, v_bid, true);
      pushPending(OrderType.Ask, _offer(OrderType.Ask, v_ask).gives());
      pushPending(OrderType.Bid, _offer(OrderType.Bid, v_bid).gives());
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
    OrderType ba = orderTypeOfOutbound(IERC20(order.outbound_tkn));
    // adds any unpublished liquidity to pending[Base/Quote]
    pushPending(ba, _handleResidual(order, makerData));
    // preparing arguments for the dual maker order
    (OrderType dualBa, SlotViewMonad memory v_dual, OfferArgs memory args) = _transportLogic(ba, order);
    int delta = populateIndex(dualBa, v_dual, args);
    return "";
  }

  ///@notice In case an offer failed to deliver, promised liquidity becomes pending, but offer is not reposted.
  ///@inheritdoc MangroveOffer
  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    OrderType ba = orderTypeOfOutbound(IERC20(order.outbound_tkn));
    pushPending(ba, order.offer.gives());
    return "";
  }
}
