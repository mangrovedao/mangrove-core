// SPDX-License-Identifier:	BSD-2-Clause

// HasKandelSlotMemoizer.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {IHasOfferIdIndexMap} from "./HasIndexedBidsAndAsks.sol";
import {IHasTokenPairOfOfferType} from "./TradesBaseQuotePair.sol";

///@title Memoizes offer id, index, and the actual Mangrove offer for an index in a strat with an indexable collection of offers.
///@dev Utilizes the IHasTokenPairOfOfferType and IHasOfferIdIndexMap interface contracts to perform the mapping.
abstract contract HasKandelSlotMemoizer is IHasTokenPairOfOfferType, IHasOfferIdIndexMap {
  IMangrove private immutable MGV;

  constructor(IMangrove mgv) {
    MGV = mgv;
  }

  ///@param indexMemoized whether the index has been memoized.
  ///@param index the memoized index.
  ///@param offerIdMemoized whether the offer id has been memoized.
  ///@param the memoized offer id.
  ///@param offerMemoized whether the offer has been memoized.
  ///@param offer the memoized offer.
  struct SlotMemoizer {
    bool indexMemoized;
    uint index;
    bool offerIdMemoized;
    uint offerId;
    bool offerMemoized;
    MgvStructs.OfferPacked offer;
  }

  ///@notice Initializes a new memoizer for the slot at the given index.
  ///@param index the index in the offer collection.
  function newSlotMemoizer(uint index) internal pure returns (SlotMemoizer memory m) {
    m.indexMemoized = true;
    m.index = index;
    return m;
  }

  ///@notice Gets the Mangrove offer id for the indexed slot.
  ///@param ba the offer type.
  ///@param m the memoizer.
  function getOfferId(OfferType ba, SlotMemoizer memory m) internal view returns (uint) {
    if (m.offerIdMemoized) {
      return m.offerId;
    } else {
      require(m.indexMemoized, "HasKandelSlotMemoizer/UninitializedIndex");
      m.offerIdMemoized = true;
      m.offerId = offerIdOfIndex(ba, m.index);
      return m.offerId;
    }
  }

  ///@notice Gets the index of the memoized slot.
  ///@param ba the offer type.
  ///@param m the memoizer.
  function getIndex(OfferType ba, SlotMemoizer memory m) internal view returns (uint) {
    if (m.indexMemoized) {
      return m.index;
    } else {
      require(m.offerIdMemoized, "HasKandelSlotMemoizer/UninitializedOfferId");
      m.indexMemoized = true;
      m.index = indexOfOfferId(ba, m.offerId);
      return m.index;
    }
  }

  ///@notice gets the Mangrove offer at the memoized index for the offer type.
  ///@param ba the offer type.
  ///@param m the memoizer.
  function getOffer(OfferType ba, SlotMemoizer memory m) internal view returns (MgvStructs.OfferPacked) {
    if (m.offerMemoized) {
      return m.offer;
    } else {
      m.offerMemoized = true;
      uint id = getOfferId(ba, m);
      (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(ba);
      m.offer = MGV.offers(address(outbound), address(inbound), id);
      return m.offer;
    }
  }
}
