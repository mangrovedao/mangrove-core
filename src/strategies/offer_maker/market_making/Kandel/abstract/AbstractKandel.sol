// SPDX-License-Identifier:	BSD-2-Clause

// AbstractKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct, IMangrove, IERC20, MgvLib, MgvStructs} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";

abstract contract AbstractKandel {
  ///@notice signals that the price has moved above Kandel's current price range
  event AllAsks(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);

  event SetCompoundRate(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote, uint compoundRate);

  // ratio and compoundRate have PRECISION decimals.
  // setting PRECISION higher than 4 might produce overflow in limit cases.
  uint8 public constant PRECISION = 4;
  ///@notice a bid or an ask

  enum OrderType {
    Bid,
    Ask
  }

  ///@notice Kandel Params
  ///@param pendingBase is the amount of free (not promised) base tokens in reserve
  ///@param pendingQuote is the amount of free (not promised) quote tokens in reserve
  ///@param ratio of price progression (` 2**16 > ratio >= 10**PRECISION`) expressed with `PRECISION` decimals
  ///@param compoundRate percentage of the spread that is to be compounded, expressed with `PRECISION` decimals (`compoundRate <= 10**PRECISION`)
  ///@param spread in amount of price slots for posting dual offer
  ///@param precision number of decimals used for 'ratio' and `compoundRate`
  struct Params {
    uint96 pendingBase;
    uint96 pendingQuote;
    uint16 gasprice;
    uint16 ratio; // geometric ratio is `ratio/10**PRECISION`
    uint16 compoundRate; // compoundRate is `compoundRate/10**PRECISION`
    uint8 spread;
    uint8 length;
  }

  ///@notice offerIdOfIndex maps index of bids (uint(OrderType.Bid)) or asks (uint(OrderType.Ask)) to offer id on Mangrove. e.g. `offerIdOfIndex[uint(OrderType.Bid)][42]` is the bid id on Mangrove that is stored at index #42 .
  uint[][2] offerIdOfIndex_;

  function offerIdOfIndex(OrderType ba, uint index) public view returns (uint) {
    return offerIdOfIndex_[uint(ba)][index];
  }

  function offerIdOfIndex(OrderType ba, uint index, uint offerId) internal {
    offerIdOfIndex_[uint(ba)][index] = offerId;
  }

  ///@notice indexOfOfferId inverse mapping of the above.  e.g. `indexOfOfferId[uint(OrderType.Ask)][12]` is the index at which ask of id #12 on Mangrove is stored
  mapping(OrderType => mapping(uint => uint)) indexOfOfferId_;

  function indexOfOfferId(OrderType ba, uint offerId) public view returns (uint) {
    return indexOfOfferId_[ba][offerId];
  }

  function indexOfOfferId(OrderType ba, uint offerId, uint index) internal {
    indexOfOfferId_[ba][offerId] = index;
  }

  struct SlotViewMonad {
    bool index_;
    uint index;
    bool offerId_;
    uint offerId;
    bool offer_;
    MgvStructs.OfferPacked offer;
    bool offerDetail_;
    MgvStructs.OfferDetailPacked offerDetail;
  }

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return ba_dual the type of order that will re-invest inbound liquidity
  ///@return v_dual the view Monad for the dual order
  ///@return args the argument for `populateIndex` specifying gives and wants
  function _transportLogic(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OrderType ba_dual, SlotViewMonad memory v_dual, Direct.OfferArgs memory args);
}
