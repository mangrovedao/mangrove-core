// SPDX-License-Identifier:	BSD-2-Clause

// HasIndexedBidsAndAsks.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IHasTokenPairOfOfferType, OfferType} from "./TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title Adds a [0..length] index <--> offerId map to a strat.
///@dev utilizes the `IHasTokenPairOfOfferType` contract.
abstract contract HasIndexedBidsAndAsks is IHasTokenPairOfOfferType {
  ///@notice The Mangrove deployment.
  IMangrove private immutable MGV;

  ///@notice the length of the index has been set.
  ///@param value the length.
  event SetLength(uint value);

  ///@notice a new offer of type `ba` with `offerId` was created at price `index`
  ///@param ba the offer type
  ///@param index the index
  ///@param offerId the Mangrove offer id.
  event SetIndexMapping(OfferType indexed ba, uint index, uint offerId);

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  constructor(IMangrove mgv) {
    MGV = mgv;
  }

  ///@notice the length of the map.
  uint internal length;

  struct OfferIdPending {
    uint32 offerId;
    uint96 pending;
  }

  mapping(uint => uint) internal priceOfIndex;

  function getPriceOfIndex(uint index) public view returns (uint price) {
    return priceOfIndex[index];
  }

  ///@notice Mangrove's offer id of an ask at a given index.
  mapping(uint => OfferIdPending) private askOfferIdOfIndex;
  ///@notice Mangrove's offer id of a bid at a given index.
  mapping(uint => OfferIdPending) private bidOfferIdOfIndex;

  struct IndexAndPrice {
    uint8 index;
    uint248 dualPrice;
  }

  ///@notice An inverse mapping of askOfferIdOfIndex. E.g., indexOfAskOfferId[42] is the index in askOfferIdOfIndex at which ask of id #42 on Mangrove is stored.
  mapping(uint => IndexAndPrice) private indexOfAskOfferId;

  ///@notice An inverse mapping of bidOfferIdOfIndex. E.g., indexOfBidOfferId[42] is the index in bidOfferIdOfIndex at which bid of id #42 on Mangrove is stored.
  mapping(uint => IndexAndPrice) private indexOfBidOfferId;

  ///@notice maps index of offers to offer id on Mangrove.
  ///@param ba the offer type
  ///@param index the index
  ///@return offerId the Mangrove offer id.
  function offerIdOfIndex(OfferType ba, uint index) public view returns (uint offerId, uint pending) {
    OfferIdPending memory p = ba == OfferType.Ask ? askOfferIdOfIndex[index] : bidOfferIdOfIndex[index];
    return (p.offerId, p.pending);
  }

  ///@notice Maps an offer type and Mangrove offer id to index.
  ///@param ba the offer type
  ///@param offerId the Mangrove offer id.
  ///@return index the index.
  ///@return dualPrice the price at the dual index.
  function indexOfOfferId(OfferType ba, uint offerId) public view returns (uint index, uint dualPrice) {
    IndexAndPrice memory p = ba == OfferType.Ask ? indexOfAskOfferId[offerId] : indexOfBidOfferId[offerId];
    return (p.index, p.dualPrice);
  }

  ///@notice Sets the Mangrove offer id for an index and vice versa.
  ///@param ba the offer type
  ///@param index the index
  ///@param offerIdPending the Mangrove offer id and pending amount.
  function setIndexMapping(OfferType ba, uint index, OfferIdPending memory offerIdPending) internal {
    if (ba == OfferType.Ask) {
      askOfferIdOfIndex[index] = offerIdPending;
    } else {
      bidOfferIdOfIndex[index] = offerIdPending;
    }
    emit SetIndexMapping(ba, index, offerIdPending.offerId);
  }

  event SetPending(OfferType indexed ba, uint indexed index, uint pending);
  event SetIndexAndPrice(OfferType indexed ba, uint indexed offerId, uint indexed index, uint dualPrice);

  function setIndexAndPriceFromDual(OfferType ba, uint offerId, uint index, uint dualPrice) internal {
    IndexAndPrice memory indexAndPrice = IndexAndPrice(uint8(index), uint248(dualPrice));

    if (ba == OfferType.Ask) {
      indexOfAskOfferId[offerId] = indexAndPrice;
    } else {
      indexOfBidOfferId[offerId] = indexAndPrice;
    }
    emit SetIndexAndPrice(ba, offerId, indexAndPrice.index, indexAndPrice.dualPrice);
  }

  function setIndexAndPrice(OfferType ba, uint offerId, uint index, uint dualPrice) internal {
    IndexAndPrice memory indexAndPrice = IndexAndPrice(uint8(index), uint248(dualPrice));

    if (ba == OfferType.Ask) {
      indexOfAskOfferId[offerId] = indexAndPrice;
    } else {
      indexOfBidOfferId[offerId] = indexAndPrice;
    }
    emit SetIndexAndPrice(ba, offerId, indexAndPrice.index, indexAndPrice.dualPrice);
  }

  function setPendingInMapping(
    OfferType ba,
    uint index,
    uint expectedGives,
    bool offerUpdated,
    uint oldGives,
    uint oldPending
  ) internal {
    uint pending;
    if (!offerUpdated) {
      if (expectedGives != oldGives) {
        // We only ever expect to give more - if we already gave some, then the more becomes pending since we failed to update.
        // We could already have some pending which we add.
        pending = oldPending + (expectedGives - oldGives);
      }
    }
    if (pending != oldPending) {
      if (ba == OfferType.Ask) {
        askOfferIdOfIndex[index].pending = uint96(pending);
      } else {
        bidOfferIdOfIndex[index].pending = uint96(pending);
      }
      emit SetPending(ba, index, pending);
    }
  }

  ///@notice sets the length of the map.
  ///@param length_ the new length.
  function setLength(uint length_) internal {
    length = length_;
    emit SetLength(length);
  }

  ///@notice gets the Mangrove offer at the given index for the offer type.
  ///@param ba the offer type.
  ///@param index the index.
  ///@return offer the Mangrove offer.
  function getOffer(OfferType ba, uint index) public view returns (MgvStructs.OfferPacked offer) {
    (uint offerId,) = offerIdOfIndex(ba, index);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(ba);
    offer = MGV.offers(address(outbound), address(inbound), offerId);
  }

  /// @notice gets the total gives of all offers of the offer type.
  /// @param ba offer type.
  /// @return volume the total gives of all offers of the offer type.
  /// @dev function is very gas costly, for external calls only.
  function offeredVolume(OfferType ba) public view returns (uint volume) {
    for (uint index = 0; index < length; ++index) {
      MgvStructs.OfferPacked offer = getOffer(ba, index);
      volume += offer.gives();
    }
  }
}
