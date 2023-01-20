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

  ///@notice returns the outbound token for the order type
  ///@param ba the order type
  function outboundOfOrderType(OrderType ba) internal view returns (IERC20 token) {
    token = ba == OrderType.Ask ? BASE : QUOTE;
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
  ) internal view returns (uint wants, uint gives) {
    // computing gives/wants for dual offer
    // we verify we cannot overflow if PRECISION = 4
    // spread:8
    uint spread = uint(params_.spread);
    // compoundRate:16
    uint compoundRate = uint(params_.compoundRate);
    // params.ratio:16, spread:8 ==> r:128
    uint r = uint(params_.ratio) ** spread;
    // log2(10) = 3.32 => p:PRECISION*3.32
    uint p = 10 ** PRECISION;
    // (a) max (p - compoundRate): 4*log2(10) (for compoundRate = 0)
    // (b) p**spread: 8*4*log2(10) < 107
    // (a) * (b) : 32*log2(10) + 4*log2(10) = 36*log2(10) < 120
    // max (compoundRate * r) : 4*log2(10)+128 < 142 (for compoundRate = 10**4)
    // max(numerator) : 96 + 142 = 238 (for compoundRate = 10**4)
    // r:128*p:4*log2(10) : 128 + 4*log2(10) = 142 and gives:96 as it should
    gives = (order.gives * ((p - compoundRate) * p ** spread + compoundRate * r)) / (r * p);

    // adding to gives what the offer was already giving so gives could be greater than 2**96
    // gives:97
    gives += _offer(ba_dual, v_dual).gives();
    if (uint96(gives) != gives) {
      // this should not be reached under normal circumstances unless strat is posting on top of an existing offer with an abnormal volume
      // to prevent gives to be too high, we let the surplus be pending
      gives = type(uint96).max;
    }
    // adjusting wants to price:
    // (a) gives * r : 96 + 128 = 224 so order.wants must be < 2**32 to avoid overflow
    if (order.wants < 2 ** 32) {
      // using max precision
      wants = (order.wants * gives * r) / (order.gives * (p ** spread));
    } else {
      wants = order.wants * ((gives * r) / (order.gives * (p ** spread)));
    }
    // wants is higher than order.wants
    // this may cause wants to be higher than 2**96 allowed by Mangrove (for instance if one needs many quotes to buy sell base tokens)
    // so we adjust the price so as to want an amount of tokens that mangrove will accept.
    if (uint96(wants) != wants) {
      gives = (type(uint96).max * gives) / wants;
      wants = type(uint96).max;
    }
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
    public
    view
    returns (MgvStructs.OfferPacked offer, MgvStructs.OfferDetailPacked offerDetail)
  {
    uint offerId = offerIdOfIndex(ba, index);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOrderType(ba);
    offer = MGV.offers(address(outbound), address(inbound), offerId);
    offerDetail = MGV.offerDetails(address(outbound), address(inbound), offerId);
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Monad for the offer to be published
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndex(OrderType ba, SlotViewMonad memory v, OfferArgs memory args) internal {
    uint offerId = _offerId(ba, v);
    if (offerId == 0 && args.gives > 0) {
      (uint offerId_, bytes32 result) = _newOffer(args);
      if (offerId_ == 0) {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", result);
      } else {
        offerIdOfIndex(ba, _index(ba, v), offerId_);
        indexOfOfferId(ba, offerId_, _index(ba, v));
      }
    } else {
      if (offerId == 0) {
        //offerId && gives are 0
      }
      //uint old_gives = _offer(ba, v).gives();
      // when gives is 0 we retract offer
      // note if gives is 0 then all gives in the range are 0, we may not want to allow for this.
      if (args.gives == 0) {
        retractOffer(ba, v, false);
      } else {
        bytes32 result = _updateOffer(args, offerId);
        if (result != REPOST_SUCCESS) {
          emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/updateOfferFailed", result);
          //TODO emit residual ? return int(old_gives + args.gives);
        }
      }
    }
  }

  struct HeapVarsPopulate {
    uint lastBidIndex;
    uint gasprice;
    uint ratio;
  }

  function iterPopulate(
    HeapVarsPopulate memory vars,
    uint[] memory indices,
    uint[] calldata baseDist,
    uint[] memory quoteDist,
    uint[] calldata pivotIds
  ) internal {
    for (uint i = 0; i < indices.length; i++) {
      OfferArgs memory args;
      uint index = indices[i];

      OrderType ba = index <= vars.lastBidIndex ? OrderType.Bid : OrderType.Ask;
      (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOrderType(ba);
      (args.wants, args.gives) = wantsGivesOfBaseQuote(ba, baseDist[i], quoteDist[i]);
      args.fund = 0;
      args.noRevert = false;
      args.gasreq = offerGasreq();
      args.gasprice = vars.gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(ba, _fresh(index), args);
    }
  }

  function setParams(uint kandelSize, uint16 ratio, uint8 spread) private {
    // Initializing arrays and parameters if needed
    Params memory params_ = params;

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
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param indices the indices to populate
  ///@param baseDist the distribution of base
  ///@param quoteDist the distribution of quote
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param kandelSize the number of price points
  ///@param ratio the rate of the geometric distribution with PRECISION decimals.
  ///@param spread the distance between a ask in the distribution and its corresponding bid.
  ///@dev This function must be called w/o changing ratio, kandelSize, spread. To change them, first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers
  function populate(
    uint[] calldata indices,
    uint[] calldata baseDist,
    uint[] calldata quoteDist,
    uint[] calldata pivotIds,
    uint lastBidIndex,
    uint kandelSize,
    uint16 ratio,
    uint8 spread
  ) external payable onlyAdmin {
    require(
      indices.length == baseDist.length && indices.length == quoteDist.length && indices.length == pivotIds.length,
      "Kandel/ArraysMustBeSameSize"
    );
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(kandelSize, ratio, spread);

    HeapVarsPopulate memory vars =
      HeapVarsPopulate({lastBidIndex: lastBidIndex, ratio: params.ratio, gasprice: params.gasprice});

    iterPopulate(vars, indices, baseDist, quoteDist, pivotIds);
  }

  ///@notice publishes bids/asks in the distribution interval `[from, to[`
  ///@param from start index
  ///@param to end index
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@dev This function must be called w/o changing ratio
  ///@dev `from` > 0 must imply `initQuote` >= quote amount given/wanted at index from-1
  ///@dev msg.value must be enough to provision all posted offers
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
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }

    uint[] memory quoteDist = new uint[](baseDist.length);
    uint[] memory indices = new uint[](baseDist.length);
    uint i = 0;
    for (uint index = from; index < to; index++) {
      indices[i] = index;
      quoteDist[i] = initQuote;
      initQuote = (initQuote * uint(ratio)) / 10 ** PRECISION;
      i++;
    }

    setParams(kandelSize, ratio, spread);

    HeapVarsPopulate memory vars =
      HeapVarsPopulate({lastBidIndex: lastBidIndex, ratio: params.ratio, gasprice: params.gasprice});

    iterPopulate(vars, indices, baseDist, quoteDist, pivotIds);
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
    }
  }

  ///@notice takes care of reposting residual offer in case of a partial fill and logging potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  function _handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData) internal {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    if (repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS) {
      return;
    }
    if (repostStatus == "mgv/writeOffer/density/tooLow") {
      // TODO log density too low
      //return __residualGives__(order);
    } else {
      // Offer failed to repost for bad reason, logging the incident
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
      //return __residualGives__(order);
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
    _handleResidual(order, makerData);
    // preparing arguments for the dual maker order
    (OrderType dualBa, SlotViewMonad memory v_dual, OfferArgs memory args) = _transportLogic(ba, order);
    populateIndex(dualBa, v_dual, args);
    return "";
  }
}
