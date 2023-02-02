// SPDX-License-Identifier:	BSD-2-Clause

// HasIndexedOffers.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IHasTokenPairOfOfferType} from "./TradesBaseQuote.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./Trade.sol";

abstract contract IHasOfferIdIndexMap {
  ///@notice maps index of offers to offer id on Mangrove.
  function offerIdOfIndex(OfferType ba, uint index) public view virtual returns (uint);
  ///@notice Maps an offer type and Mangrove offer id to Kandel index.
  function indexOfOfferId(OfferType ba, uint offerId) public view virtual returns (uint);
}

abstract contract HasIndexedOffers is IHasTokenPairOfOfferType, IHasOfferIdIndexMap {
  struct MangroveWithBaseQuote {
    IMangrove mgv;
    IERC20 base;
    IERC20 quote;
  }

  IMangrove private immutable MGV;

  constructor(IMangrove mgv) {
    MGV = mgv;
  }

  ///@notice Mangrove's offer id of an ask at a given price index.
  uint[] askOfferIdOfIndex;
  ///@notice Mangrove's offer id of a bid at a given price index.
  uint[] bidOfferIdOfIndex;

  ///@notice An inverse mapping of askOfferIdOfIndex. E.g., indexOfAskOfferId[42] is the index in askOfferIdOfIndex at which ask of id #42 on Mangrove is stored.
  mapping(uint => uint) indexOfAskOfferId;

  ///@notice An inverse mapping of bidOfferIdOfIndex. E.g., indexOfBidOfferId[42] is the index in bidOfferIdOfIndex at which bid of id #42 on Mangrove is stored.
  mapping(uint => uint) indexOfBidOfferId;

  ///@inheritdoc IHasOfferIdIndexMap
  function offerIdOfIndex(OfferType ba, uint index) public view override returns (uint) {
    return ba == OfferType.Ask ? askOfferIdOfIndex[index] : bidOfferIdOfIndex[index];
  }

  ///@inheritdoc IHasOfferIdIndexMap
  function indexOfOfferId(OfferType ba, uint offerId) public view override returns (uint) {
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

  function setLength(uint length) internal {
    askOfferIdOfIndex = new uint[](length);
    bidOfferIdOfIndex = new uint[](length);
  }

  function getOffer(OfferType ba, uint index) public view returns (MgvStructs.OfferPacked offer) {
    uint offerId = offerIdOfIndex(ba, index);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(ba);
    offer = MGV.offers(address(outbound), address(inbound), offerId);
  }

  /// @notice gets the total gives of all offers of the offer type
  /// @param ba offer type.
  /// @dev function is very gas costly, for external calls only
  function offeredVolume(OfferType ba) public view returns (uint volume) {
    for (uint index = 0; index < askOfferIdOfIndex.length; index++) {
      MgvStructs.OfferPacked offer = getOffer(ba, index);
      volume += offer.gives();
    }
  }
}
