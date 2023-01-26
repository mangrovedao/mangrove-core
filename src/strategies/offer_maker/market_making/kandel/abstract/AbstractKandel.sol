// SPDX-License-Identifier:	BSD-2-Clause

// AbstractKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs, MgvLib} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";

abstract contract AbstractKandel {
  ///@notice signals that the price has moved above Kandel's current price range
  event AllAsks();
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids();

  ///@notice the compound rates have been set to `compoundRateBase` and `compoundRateQuote` which will take effect for future compounding.
  event SetCompoundRates(uint compoundRateBase, uint compoundRateQuote);

  ///@notice signals a new Kandel instance for the owner on the mangrove, for base and quote.
  event NewKandel(address indexed owner, IMangrove indexed mgv, IERC20 indexed base, IERC20 quote);

  // `ratio`, `compoundRateBase`, and `compoundRateQuote` have PRECISION decimals.
  // setting PRECISION higher than 4 might produce overflow in limit cases.
  uint8 public constant PRECISION = 4;

  ///@notice a bid or an ask
  enum OfferType {
    Bid,
    Ask
  }

  constructor(IMangrove mgv, IERC20 base, IERC20 quote) {
    emit NewKandel(msg.sender, mgv, base, quote);
  }

  ///@notice Kandel Params
  ///@param ratio of price progression (`2**16 > ratio >= 10**PRECISION`) expressed with `PRECISION` decimals, so geometric ratio is `ratio/10**PRECISION`
  ///@param compoundRateBase percentage of the spread that is to be compounded for base, expressed with `PRECISION` decimals (`compoundRateBase <= 10**PRECISION`). Real compound rate for base is `compoundRateBase/10**PRECISION`
  ///@param compoundRateQuote percentage of the spread that is to be compounded for quote, expressed with `PRECISION` decimals (`compoundRateQuote <= 10**PRECISION`). Real compound rate for quote is `compoundRateQuote/10**PRECISION`
  ///@param spread in amount of price slots for posting dual offer
  ///@param precision number of decimals used for `ratio`, `compoundRateBase`, and `compoundRateQuote`.
  struct Params {
    uint16 gasprice;
    uint16 ratio;
    uint16 compoundRateBase;
    uint16 compoundRateQuote;
    uint8 spread;
    uint8 length;
  }

  ///@notice Mangrove's offer id of an ask at a given price index.
  uint[] askOfferIdOfIndex;
  ///@notice Mangrove's offer id of a bid at a given price index.
  uint[] bidOfferIdOfIndex;

  ///@notice maps index of offers to offer id on Mangrove.
  function offerIdOfIndex(OfferType ba, uint index) public view returns (uint) {
    return ba == OfferType.Ask ? askOfferIdOfIndex[index] : bidOfferIdOfIndex[index];
  }

  ///@notice An inverse mapping of askOfferIdOfIndex. E.g., indexOfAskOfferId[42] is the index in askOfferIdOfIndex at which ask of id #42 on Mangrove is stored.
  mapping(uint => uint) indexOfAskOfferId;

  ///@notice An inverse mapping of bidOfferIdOfIndex. E.g., indexOfBidOfferId[42] is the index in bidOfferIdOfIndex at which bid of id #42 on Mangrove is stored.
  mapping(uint => uint) indexOfBidOfferId;

  ///@notice Maps an offer type and Mangrove offer id to Kandel index.
  function indexOfOfferId(OfferType ba, uint offerId) public view returns (uint) {
    return ba == OfferType.Ask ? indexOfAskOfferId[offerId] : indexOfBidOfferId[offerId];
  }

  ///@notice Sets the Mangrove offer id for a Kandel index and vice versa.
  function setIndexMapping(OfferType ba, uint index, uint offerId) internal {
    if (ba == OfferType.Ask) {
      indexOfAskOfferId[offerId] = index;
      askOfferIdOfIndex[index] = offerId;
    } else {
      indexOfBidOfferId[offerId] = index;
      bidOfferIdOfIndex[index] = offerId;
    }
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
  ///@return baDual the type of offer that will re-invest inbound liquidity
  ///@return viewDual the view Monad for the dual offer
  ///@return args the argument for `populateIndex` specifying gives and wants
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OfferType baDual, SlotViewMonad memory viewDual, Direct.OfferArgs memory args);
}
