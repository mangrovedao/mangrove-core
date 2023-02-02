// SPDX-License-Identifier:	BSD-2-Clause

// HasKandelSlotViewMemoizer.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {OfferType} from "./Trade.sol";
import {IHasOfferIdIndexMap} from "./HasIndexedOffers.sol";
import {IHasTokenPairOfOfferType} from "./TradesBaseQuote.sol";

abstract contract HasKandelSlotViewMemoizer is IHasTokenPairOfOfferType, IHasOfferIdIndexMap {
  IMangrove private immutable MGV;

  constructor(IMangrove mgv) {
    MGV = mgv;
  }

  struct SlotViewMemoizer {
    bool indexMemoized;
    uint index;
    bool offerIdMemoized;
    uint offerId;
    bool offerMemoized;
    MgvStructs.OfferPacked offer;
  }

  function _fresh(uint index) internal pure returns (SlotViewMemoizer memory v) {
    v.indexMemoized = true;
    v.index = index;
    return v;
  }

  function _offerId(OfferType ba, SlotViewMemoizer memory v) internal view returns (uint) {
    if (v.offerIdMemoized) {
      return v.offerId;
    } else {
      require(v.indexMemoized, "Kandel/monad/UninitializedIndex");
      v.offerIdMemoized = true;
      v.offerId = offerIdOfIndex(ba, v.index);
      return v.offerId;
    }
  }

  function _index(OfferType ba, SlotViewMemoizer memory v) internal view returns (uint) {
    if (v.indexMemoized) {
      return v.index;
    } else {
      require(v.offerIdMemoized, "Kandel/monad/UninitializedOfferId");
      v.indexMemoized = true;
      v.index = indexOfOfferId(ba, v.offerId);
      return v.index;
    }
  }

  function _offer(OfferType ba, SlotViewMemoizer memory v) internal view returns (MgvStructs.OfferPacked) {
    if (v.offerMemoized) {
      return v.offer;
    } else {
      v.offerMemoized = true;
      uint id = _offerId(ba, v);
      (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(ba);
      v.offer = MGV.offers(address(outbound), address(inbound), id);
      return v.offer;
    }
  }
}
