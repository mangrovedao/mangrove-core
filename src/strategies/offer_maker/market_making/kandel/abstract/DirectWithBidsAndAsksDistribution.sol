// SPDX-License-Identifier:	BSD-2-Clause

// DirectWithBidsAndAsksDistribution.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {HasIndexedBidsAndAsks} from "./HasIndexedBidsAndAsks.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";

///@title `Direct` strat with an indexed collection of bids and asks which can be populated according to a desired base and quote distribution for gives and wants.
abstract contract DirectWithBidsAndAsksDistribution is Direct, HasIndexedBidsAndAsks {
  ///@notice The offer has too low volume to be posted.
  bytes32 internal constant LOW_VOLUME = "Kandel/volumeTooLow";

  // why not have the constant here and as a factor of two?
  uint public constant PRICE_PRECISION = 2 ** 96;

  ///@notice logs the start of a call to populate
  event PopulateStart();
  ///@notice logs the end of a call to populate
  event PopulateEnd();

  ///@notice logs the start of a call to retractOffers
  event RetractStart();
  ///@notice logs the end of a call to retractOffers
  event RetractEnd();

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param gasreq the gasreq to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, uint gasreq, address reserveId)
    Direct(mgv, NO_ROUTER, gasreq, reserveId)
    HasIndexedBidsAndAsks(mgv)
  {}

  ///@notice returns the destination index to transport received liquidity to - a better (for Kandel) price index for the offer type.
  ///@param ba the offer type to transport to
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  ///@param pricePoints the number of price points
  ///@return better destination index
  ///@return spread the size of the price jump, which is `step` if the index boundaries were not reached
  function transportDestination(OfferType ba, uint index, uint step, uint pricePoints)
    internal
    pure
    returns (uint better, uint8 spread)
  {
    if (ba == OfferType.Ask) {
      better = index + step;
      if (better >= pricePoints) {
        better = pricePoints - 1;
        spread = uint8(better - index);
      } else {
        spread = uint8(step);
      }
    } else {
      if (index >= step) {
        better = index - step;
        spread = uint8(step);
      } else {
        // else better = 0
        spread = uint8(index - better);
      }
    }
  }

  ///@param indices the indices to populate, in ascending order
  ///@param baseDist base distribution for the indices (the `wants` for bids and the `gives` for asks)
  ///@param quoteDist the distribution of quote for the indices (the `gives` for bids and the `wants` for asks)
  struct Distribution {
    uint[] indices;
    uint[] baseDist;
    uint[] quoteDist;
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for indices.
  ///@param pivotIds the pivots to be used for the offers.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param gasreq the amount of gas units that are required to execute the trade.
  ///@param gasprice the gasprice used to compute offer's provision.
  function populateChunk(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint firstAskIndex,
    uint gasreq,
    uint gasprice
  ) internal {
    emit PopulateStart();

    uint[] calldata indices = distribution.indices;
    uint[] calldata quoteDist = distribution.quoteDist;
    uint[] calldata baseDist = distribution.baseDist;

    uint[] memory prices = new uint[](length);
    uint i;
    // read existing prices if any
    for (; i < length; i++) {
      (uint offerId,,) = offerIdOfIndex2(OfferType.Bid, i);
      (, uint dualPrice) = indexOfOfferId(OfferType.Bid, offerId);
      //TODO spread
      (uint dualIndex,) = transportDestination(OfferType.Ask, i, 1, length);

      if (prices[dualIndex] == 0) {
        prices[i] = dualPrice;
      }
      (offerId,,) = offerIdOfIndex2(OfferType.Ask, i);
      (, dualPrice) = indexOfOfferId(OfferType.Ask, offerId);
      (dualIndex,) = transportDestination(OfferType.Bid, i, 1, length);
      if (prices[dualIndex] == 0) {
        prices[i] = dualPrice;
      }
    }
    i = 0;
    for (; i < indices.length; ++i) {
      uint index = indices[i];
      prices[index] = (quoteDist[i] * PRICE_PRECISION) / baseDist[i];
      (uint offerId,, uint oldPending) = offerIdOfIndex2(OfferType.Bid, index);
      if (offerId > 0) {
        setPendingInMapping(OfferType.Bid, index, 0, true, 0, oldPending);
        setIndexAndPrice(OfferType.Bid, offerId, index, prices[index]);
      }

      (offerId,, oldPending) = offerIdOfIndex2(OfferType.Ask, index);
      if (offerId > 0) {
        setPendingInMapping(OfferType.Ask, index, 0, true, 0, oldPending);
        setIndexAndPrice(OfferType.Ask, offerId, index, prices[index]);
      }
    }

    i = 0;

    OfferArgs memory args;
    // args.fund = 0; offers are already funded
    // args.noRevert = false; we want revert in case of failure

    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(OfferType.Bid);
    for (; i < indices.length; ++i) {
      uint index = indices[i];
      if (index >= firstAskIndex) {
        break;
      }
      args.wants = baseDist[i];
      args.gives = quoteDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      (uint dualIndex,) = transportDestination(OfferType.Ask, index, 1, length);
      uint dualPrice = prices[dualIndex];
      require(dualPrice > 0, "Kandel/zeroDualAsk");
      (uint offerId,,) = offerIdOfIndex2(OfferType.Bid, index);

      (offerId,) = populateIndex(OfferType.Bid, offerId, index, args);
      setIndexAndPrice(OfferType.Bid, offerId, index, dualPrice);
      OfferIdPending memory offerIdPending =
        OfferIdPending(uint32(offerId), 0, 0, 0 /*pending is 0 otherwise we revert*/ );
      setIndexMapping(OfferType.Bid, index, offerIdPending);
    }

    (args.outbound_tkn, args.inbound_tkn) = (args.inbound_tkn, args.outbound_tkn);

    for (; i < indices.length; ++i) {
      uint index = indices[i];
      args.wants = quoteDist[i];
      args.gives = baseDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      (uint dualIndex,) = transportDestination(OfferType.Bid, index, 1, length);
      uint dualPrice = prices[dualIndex];
      require(dualPrice > 0, "Kandel/zeroDualBid");

      (uint offerId,,) = offerIdOfIndex2(OfferType.Ask, index);

      (offerId,) = populateIndex(OfferType.Ask, offerId, index, args);
      setIndexAndPrice(OfferType.Ask, offerId, index, dualPrice);
      OfferIdPending memory offerIdPending =
        OfferIdPending(uint32(offerId), 0, 0, 0 /*pending is 0 otherwise we revert*/ );
      setIndexMapping(OfferType.Ask, index, offerIdPending);
    }
    emit PopulateEnd();
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index.
  ///@param ba whether the offer is a bid or an ask.
  ///@param offerId the Mangrove offer id (0 for a new offer).
  ///@param index the price index.
  ///@param args the argument of the offer.
  ///@return offerId2 the Mangrove offer id (only 0 if offer failed to be created)
  ///@return result the result from Mangrove or Direct (an error if `args.noRevert` is `true`).
  function populateIndex(OfferType ba, uint offerId, uint index, OfferArgs memory args)
    internal
    returns (uint offerId2, bytes32 result)
  {
    // if offer does not exist on mangrove yet
    if (offerId == 0) {
      // and offer should exist
      if (args.gives > 0 && args.wants > 0) {
        // create it
        (offerId, result) = _newOffer(args);
      } else {
        // else offerId && gives are 0 and the offer is left not posted
        result = LOW_VOLUME;
      }
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0 || args.wants == 0) {
        // This may happen in the following cases:
        // * `gives == 0` may not come from `DualWantsGivesOfOffer` computation, but `wants==0` might.
        // * `gives == 0` may happen from populate in case of re-population where the offers in the spread are then retracted by setting gives to 0.
        _retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
        result = LOW_VOLUME;
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume
        result = _updateOffer(args, offerId);
      }
    }

    return (offerId, result);
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`.
  ///@param from the start index.
  ///@param to the end index.
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs.
  function retractOffers(uint from, uint to) public onlyAdmin {
    emit RetractStart();
    (IERC20 outbound_tknAsk, IERC20 inbound_tknAsk) = tokenPairOfOfferType(OfferType.Ask);
    (IERC20 outbound_tknBid, IERC20 inbound_tknBid) = (inbound_tknAsk, outbound_tknAsk);
    for (uint index = from; index < to; ++index) {
      // These offerIds could be recycled in a new populate
      (uint offerId,,) = offerIdOfIndex2(OfferType.Ask, index);
      if (offerId != 0) {
        _retractOffer(outbound_tknAsk, inbound_tknAsk, offerId, true);
      }
      (offerId,,) = offerIdOfIndex2(OfferType.Bid, index);
      if (offerId != 0) {
        _retractOffer(outbound_tknBid, inbound_tknBid, offerId, true);
      }
    }
    emit RetractEnd();
  }
}
