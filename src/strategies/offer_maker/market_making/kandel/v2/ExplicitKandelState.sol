// SPDX-License-Identifier:	BSD-2-Clause

// ExplicitKandelState.sol

// Copyright (c) 2023 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {OfferType} from "../abstract/TradesBaseQuotePair.sol";

///@title Explicit Kandel storage
contract ExplicitKandelState {
  ///@notice a new offer of type `ba` with `offerId` was created at price `index`
  ///@param ba the offer type
  ///@param index the index
  ///@param offerId the Mangrove offer id.
  event SetIndexMapping(OfferType indexed ba, uint index, uint offerId);

  uint public constant PRICE_DECIMALS = 18;
  uint public immutable LENGTH;
  uint internal immutable INIT_GASREQ;
  uint internal immutable INIT_GASPRICE;

  struct PriceIndex {
    uint16 index;
    uint136 dualPrice; //price of dual offer
  }

  struct OfferStatus {
    uint32 bidId;
    uint32 askId;
    uint96 pending;
    uint16 gasprice;
    uint24 gasreq;
  }

  mapping(uint => PriceIndex) internal priceIndexOfBidOfferId_;
  mapping(uint => PriceIndex) internal priceIndexOfAskOfferId_;
  mapping(uint => OfferStatus) internal offerStatusOfIndex_;

  uint[] internal initialBidPrices_;
  uint[] internal initialAskPrices_;

  constructor(uint gasreq, uint gasprice, uint[] memory bidPrices, uint[] memory askPrices) {
    INIT_GASREQ = gasreq;
    INIT_GASPRICE = gasprice;
    require(askPrices.length == bidPrices.length, "ExplicitKandel/invalidPrices");
    LENGTH = askPrices.length;
    initialAskPrices_ = askPrices;
    initialBidPrices_ = bidPrices;
  }

  // getter
  function offerIdOfIndex(OfferType ba, uint index) internal view returns (uint) {
    return ba == OfferType.Ask ? offerStatusOfIndex_[index].askId : offerStatusOfIndex_[index].bidId;
  }

  // setter

  function setIndexMapping(OfferType ba, uint index, uint offerId) internal {
    PriceIndex memory p;
    p.index = uint16(index);
    // price stored is the dual offer's price
    p.dualPrice = uint136(ba == OfferType.Ask ? initialBidPrices_[index] : initialAskPrices_[index]);
    if (ba == OfferType.Ask) {
      priceIndexOfAskOfferId_[offerId] = p;
    } else {
      priceIndexOfBidOfferId_[offerId] = p;
    }
    emit SetIndexMapping(ba, p.index, offerId);
  }
}
