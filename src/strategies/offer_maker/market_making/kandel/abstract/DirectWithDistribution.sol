// SPDX-License-Identifier:	BSD-2-Clause

// DirectWithDistribution.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./Trade.sol";
import {HasKandelSlotMemoizer} from "./HasKandelSlotMemoizer.sol";
import {HasIndexedBidsAndAsks} from "./HasIndexedBidsAndAsks.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

abstract contract DirectWithDistribution is Direct, HasKandelSlotMemoizer, HasIndexedBidsAndAsks {
  constructor(IMangrove mgv, uint gasreq, address owner)
    Direct(mgv, NO_ROUTER, gasreq, owner)
    HasKandelSlotMemoizer(mgv)
    HasIndexedBidsAndAsks(mgv)
  {}

  ///@notice a bid was populated near the mid (around lastBidIndex but not necessarily that one).
  event BidNearMidPopulated(uint index, uint96 gives, uint96 wants);

  ///@param indices the indices to populate, in ascending order
  ///@param baseDist base distribution for the indices
  ///@param quoteDist the distribution of quote for the indices
  struct Distribution {
    uint[] baseDist;
    uint[] quoteDist;
    uint[] indices;
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple calls are needed for initialization.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param lastBidIndex the index after which offer should be an ask. First index will never be an ask, either a bid or not published.
  function populateChunk(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint lastBidIndex,
    uint gasreq,
    uint gasprice
  ) internal {
    uint[] calldata indices = distribution.indices;
    uint[] calldata quoteDist = distribution.quoteDist;
    uint[] calldata baseDist = distribution.baseDist;

    require(
      indices.length == baseDist.length && indices.length == quoteDist.length && indices.length == pivotIds.length,
      "Kandel/ArraysMustBeSameSize"
    );

    uint i = 0;

    OfferArgs memory args;
    // args.fund = 0; offers are already funded
    // args.noRevert = false; we want revert in case of failure

    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(OfferType.Bid);
    for (i = 0; i < indices.length; i++) {
      uint index = indices[i];
      if (index > lastBidIndex) {
        break;
      }
      args.wants = baseDist[i];
      args.gives = quoteDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(OfferType.Bid, _fresh(index), args);
    }
    if (i > 0) {
      // At least one bid has been populated, emit it to make price derivable
      emit BidNearMidPopulated(indices[i - 1], uint96(args.gives), uint96(args.wants));
    }
    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(OfferType.Ask);

    for (; i < indices.length; i++) {
      uint index = indices[i];
      args.wants = quoteDist[i];
      args.gives = baseDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(OfferType.Ask, _fresh(index), args);
    }
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Memoizer for the offer to be published
  ///@param args the argument of the offer.
  ///@return result from Mangrove on error and `args.noRevert` is `true`.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndex(OfferType ba, SlotMemoizer memory v, OfferArgs memory args) internal returns (bytes32 result) {
    uint offerId = _offerId(ba, v);
    // if offer does not exist on mangrove yet
    if (offerId == 0) {
      // and offer should exist
      if (args.gives > 0) {
        // create it
        (offerId, result) = _newOffer(args);
        if (offerId != 0) {
          setIndexMapping(ba, _index(ba, v), offerId);
        }
      }
      // else offerId && gives are 0 and the offer is left not posted
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0) {
        // so we retract the offer. This does not happen when gives comes from dualWantsGivesOfOffer,
        // but may happen from populate in case of re-population where the offers in the spread
        // are then retracted by setting gives to 0.
        _retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume
        result = _updateOffer(args, offerId);
      }
    }
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`
  ///@param from the start index
  ///@param to the end index
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs
  function retractOffers(uint from, uint to) external onlyAdmin {
    (IERC20 outbound_tknAsk, IERC20 inbound_tknAsk) = tokenPairOfOfferType(OfferType.Ask);
    (IERC20 outbound_tknBid, IERC20 inbound_tknBid) = tokenPairOfOfferType(OfferType.Bid);
    for (uint index = from; index < to; index++) {
      // These offerIds could be recycled in a new populate
      uint offerId = offerIdOfIndex(OfferType.Ask, index);
      if (offerId != 0) {
        _retractOffer(outbound_tknAsk, inbound_tknAsk, offerId, true);
      }
      offerId = offerIdOfIndex(OfferType.Bid, index);
      if (offerId != 0) {
        _retractOffer(outbound_tknBid, inbound_tknBid, offerId, true);
      }
    }
  }
}
