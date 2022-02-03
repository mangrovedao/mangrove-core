// SPDX-License-Identifier:	BSD-2-Clause

// SwingingMarketMaker.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "../../Persistent.sol";

contract DAMM is Persistent {
  using P.Offer for P.Offer.t;
  using P.OfferDetail for P.OfferDetail.t;
  
  /** Immutables */
  uint immutable NSLOTS; // total number of Asks (Bids)
  uint immutable INIT_MINGIVES; // initial Gives for min offer 

  uint[] ASKS;
  uint[] BIDS;
  address immutable BASE;
  address immutable QUOTE;

  /** Mutables */
  int current_shift;
  uint current_delta; // offer[i+1].gives = offer[i].gives + current_delta
  bool is_initialized;

  modifier initialized() {
    require(is_initialized, "DAMM/uninitialized");
    _; 
  }

  /** NB: constructor is `payable` in order to fund initial bids and asks */
  constructor(
    address payable mgv,
    address base,
    address quote,
    uint nslots,
    uint init_gives
  ) MangroveOffer(mgv) payable {
    // sanity check
    require(nslots>0 && mgv!=address(0), "DAMM/constructor/invalidArguments");
    if (msg.value > 0) {
      fundMangroveInternal(msg.sender, msg.value);
    }
    BASE = base;
    QUOTE = quote;
    INIT_MINGIVES = init_gives;
    NSLOTS = nslots;
    ASKS = new uint[](nslots);
    BIDS = new uint[](nslots);
  }

  function initialize(
    uint init_wants,
    uint delta, // parameter for the price increment (default is arithmetic progression)
    uint nbids, // `nbids <= NSLOTS`. Says how many bids should be placed
    uint[][2] calldata pivotIds // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
  ) public internalOrAdmin {
    /** Initializing Asks and Bids */
    /** NB we assume Mangrove is already provisioned for posting NSLOTS asks and NSLOTS bids*/
    /** NB cannot post newOffer with infinite gasreq since fallback OFR_GASREQ is not defined yet (and default is likely wrong) */
    require(nbids<=NSLOTS, "DAMM/initialize/nbidsTooHigh");
    current_delta = delta;
    uint pivotId=0;
    uint i;
    for(i=0; i<NSLOTS; i++) {
      uint bidId;
      if(is_initialized) {
        bidId = BIDS[i];
        updateOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: init_wants,
          gives: __gives_of_position__(i, delta, INIT_MINGIVES), // arithmetic progression by default
          gasreq: OFR_GASREQ,
          gasprice: 0,
          offerId: bidId,
          pivotId: pivotIds[0][i]!=0?pivotIds[0][i]:pivotId, // use offchain computed pivot if available otherwise use last inserted offerId
          provision: 0 
        });
      } else {
        bidId = newOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: init_wants,
          gives: __gives_of_position__(i, delta, INIT_MINGIVES), // arithmetic progression by default
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: pivotIds[0][i]!=0?pivotIds[0][i]:pivotId, // use offchain computed pivot if available otherwise use last inserted offerId
          provision:0 
        });
      }
      pivotId = bidId;
      BIDS[i] = bidId;

      pivotId=0;
      uint askId;
      for(i=0; i<NSLOTS; i++) {
        if (is_initialized) {
          askId = ASKS[i];
          updateOfferInternal({
            outbound_tkn: BASE,
            inbound_tkn: QUOTE,
            wants: init_wants,
            gives: __gives_of_position__(i, delta, INIT_MINGIVES), // arithmetic progression by default
            gasreq: OFR_GASREQ,
            gasprice: 0,
            pivotId: pivotIds[1][i]!=0?pivotIds[1][i]:pivotId, // use offchain computed pivot if available otherwise use last inserted offerId
            provision: 0,
            offerId: askId
          });
        } else {
          askId = newOfferInternal({
            outbound_tkn: BASE,
            inbound_tkn: QUOTE,
            wants: init_wants,
            gives: __gives_of_position__(i, delta, INIT_MINGIVES), // arithmetic progression by default
            gasreq: OFR_GASREQ,
            gasprice: 0,
            pivotId: pivotIds[1][i]!=0?pivotIds[1][i]:pivotId, // use offchain computed pivot if available otherwise use last inserted offerId
            provision: 0
          });
        }
        pivotId = askId;
        ASKS[i] = askId;

        // If i<nbids, ask should be retracted, else bid should be retracted
        if (i<nbids) {
          retractOfferInternal({
            outbound_tkn:BASE,
            inbound_tkn:QUOTE,
            offerId: askId,
            deprovision:false // leaving provision
          });
        } else {
          retractOfferInternal({
            outbound_tkn:QUOTE,
            inbound_tkn:BASE,
            offerId: bidId,
            deprovision:false // leaving provision
          });
        }
      }
    }
    is_initialized = true;
  }
  
  /** Returns the position in the order book of the offer associated to this index `i` */
  function position_of_index(uint i) internal view returns (uint) {
    // position(i) = (i+shift) % N
    int p = (int(i) + current_shift) % int(NSLOTS); 
    return (p<0) ? uint(-p) : uint(p);
  }

  /** Returns the index in the ring of offers at which the offer Id at position `p` in the book is stored */
  function index_of_position(uint p) internal view returns (uint) {
    int i = (int(p) - current_shift) % int(NSLOTS);
    return (i<0) ? uint(-i) : uint(i);
  }

  /**Next index in the ring of offers */
  function next_index(uint i) internal view returns (uint) {
    return (i+1)%NSLOTS;
  }

  /**Previous index in the ring of offers */
  function prev_index(uint i) internal view returns (uint) {
    return i>0?i-1:NSLOTS-1;
  }

  /** Returns the quantity of outbound_tkn the offer at position `p` is supposed to offer according to actual shift */
  /** NB the returned `gives` might not the one actually offered on Mangrove if the price has shifted or if the offer is not Live*/
  function __gives_of_position__(uint p, uint delta, uint init_gives) internal virtual pure returns (uint) {
    return delta*p + init_gives;
  } 

/** Recenter the order book by shifting min price up `s` positions in the book */
/** As a consequence `s` Bids will be cancelled and `s` new asks will be posted */
  function positive_shift(uint s) public internalOrAdmin initialized {
    uint index = index_of_position(0);
    current_shift += int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Bids[index],..,Bids[index+`s` % N]] are retracted
      retractOfferInternal(BASE,QUOTE,BIDS[index],false);
      // slots are replaced by `s` Asks.
      // NB the price of Ask[index] is computed given the new position associated to `index`
      // because the shift has been updated above
      P.Offer.t offer = MGV.offers(
        QUOTE,
        BASE,
        ASKS[index]
      );
      P.OfferDetail.t offerDetail = MGV.offerDetails(
        QUOTE,
        BASE,
        ASKS[index]
      );
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives = __gives_of_position__(pos, current_delta, INIT_MINGIVES);
      uint new_wants = (offer.wants() * new_gives) / offer.gives();
      updateOfferInternal({
        outbound_tkn:QUOTE,
        inbound_tkn:BASE,
        offerId:ASKS[index],
        wants: new_wants,
        gives: new_gives,
        gasprice: offerDetail.gasprice(),
        gasreq: offerDetail.gasreq(),
        pivotId: pos>0 ? index_of_position(pos-1) : 0,
        provision:0
      });
      s--;
      index = next_index(index);
    }
  }

  /** Recenter the order book by shifting max price down `s` positions in the book */
  /** As a consequence `s` Asks will be cancelled and `s` new Bids will be posted */
  function negative_shift(uint s) public internalOrAdmin initialized {
    uint index = index_of_position(NSLOTS-1);
    current_shift -= int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Asks[index-`s` % N],..,Asks[index]] are retracted
      retractOfferInternal(QUOTE,BASE,ASKS[index],false);
      // slots are replaced by `s` Bids.
      // NB the price of Bids[index] is computed given the new position associated to `index`
      // because the shift has been updated above
      P.Offer.t offer = MGV.offers(
        BASE,
        QUOTE,
        BIDS[index]
      );
      P.OfferDetail.t offerDetail = MGV.offerDetails(
        BASE,
        QUOTE,
        BIDS[index]
      );
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives = __gives_of_position__(pos, current_delta, INIT_MINGIVES);
      uint new_wants = (offer.wants() * new_gives) / offer.gives();
      updateOfferInternal({
        outbound_tkn:BASE,
        inbound_tkn:QUOTE,
        offerId:BIDS[index],
        wants: new_wants,
        gives: new_gives,
        gasprice: offerDetail.gasprice(),
        gasreq: offerDetail.gasreq(),
        pivotId: pos<NSLOTS-1 ? index_of_position(pos+1) : 0,
        provision:0
      });
      s--;
      index = prev_index(index);
    }
  }

  // TODO  __posthookSuccess__
  // TODO  compact/dilate functions
  // TODO __posthookFail__
  
}
