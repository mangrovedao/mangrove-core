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
  uint16 immutable NSLOTS; // total number of Asks (Bids)
  uint immutable INIT_MINPRICE; // initial min price with QUOTE decimals precision

  address immutable BASE;
  address immutable QUOTE;
  uint8 immutable QUOTE_DECIMALS;
  uint8 immutable BASE_DECIMALS;

  /** Mutables */
  //NB if one wants to allow this contract to be multi-makers one should use uint[][] ASKS/BIDS and allocate a new array for each maker.
  uint[] ASKS;
  uint[] BIDS;
  mapping(uint => uint) index_of_bid; // bidId -> index
  mapping(uint => uint) index_of_ask; // askId -> index
  
  
  //NB if one wants to allow this contract to be multi-makers one should use uint[] for each mutable fields to allow user specific parameters.
  int current_shift;
  // offer[i+1] = offer[i] + current_delta for arithmetic progression. offer[i+1] = current_delta*offer[i] for geometric
  uint current_delta; 
  uint current_new_base_amount; // new base amount for fresh offers
  bool is_initialized;

  modifier initialized() {
    require(is_initialized, "DAMM/uninitialized");
    _; 
  }

  /** NB: constructor is `payable` in order to allow deployer to fund initial bids and asks */
  constructor(
    address payable mgv,
    address base,
    address quote,
    uint init_price,
    uint nslots
  ) MangroveOffer(mgv) {
    // sanity check
    require(
      nslots>0 
    && mgv!=address(0)
    && uint16(nslots)==nslots, 
    "DAMM/constructor/invalidArguments"
    );
    BASE = base;
    QUOTE = quote;
    INIT_MINPRICE = init_price;
    NSLOTS = uint16(nslots);
    ASKS = new uint[](nslots);
    BIDS = new uint[](nslots);
    BASE_DECIMALS = IERC20(base).decimals();
    QUOTE_DECIMALS = IERC20(quote).decimals();
  }

  function _getPivot(uint[] calldata pivots, uint i) internal returns (uint) {
    if (pivots[i]!=0) {
      return pivots[i];
    } else {
      return i>0?pivots[i-1]:0;
    }
  }

  function initialize(
    uint default_base,
    uint delta, // parameter for the price increment (default is arithmetic progression)
    uint nbids, // `nbids <= NSLOTS`. Says how many bids should be placed
    uint[][2] calldata pivotIds // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
  ) public internalOrAdmin {
    /** Initializing Asks and Bids */
    /** NB we assume Mangrove is already provisioned for posting NSLOTS asks and NSLOTS bids*/
    /** NB cannot post newOffer with infinite gasreq since fallback OFR_GASREQ is not defined yet (and default is likely wrong) */
    require(nbids<=NSLOTS, "DAMM/initialize/nbidsTooHigh");
    current_delta = delta;
    current_new_base_amount = default_base;
    
    uint i;
    for(i=0; i<NSLOTS; i++) {
      // bidId is either fresh is contract is not initialized or already present at index
      uint bidId;
      if(is_initialized) {
        bidId = BIDS[i];
        updateOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: default_base,
          gives: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS), 
          gasreq: OFR_GASREQ,
          gasprice: 0,
          offerId: bidId,
          pivotId: _getPivot(pivotIds[0],i), // use offchain computed pivot if available otherwise use last inserted bid id if any
          provision: 0 
        });
      } else {
        bidId = newOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: default_base,
          gives: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS),
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: _getPivot(pivotIds[0],i) , // use offchain computed pivot if available otherwise use last inserted offerId
          provision:0 
        });
        index_of_bid[bidId] = i;
      }
      BIDS[i] = bidId;
      
      uint askId;
      if (is_initialized) {
        askId = ASKS[i];
        updateOfferInternal({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          wants: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS),
          gives: default_base, 
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: _getPivot(pivotIds[1],i), // use offchain computed pivot if available otherwise use last inserted offerId
          provision: 0,
          offerId: askId
        });
      } else {
        askId = newOfferInternal({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          wants: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS),
          gives: default_base, 
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: _getPivot(pivotIds[1],i), // use offchain computed pivot if available otherwise use last inserted offerId
          provision: 0
        });
        index_of_ask[askId] = i;
      }
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
    is_initialized = true;
  }
  
  /** Returns the position in the order book of the offer associated to this index `i` */
  function position_of_index(uint i) internal view returns (uint) {
    // position(i) = (i+shift) % N
    int p = (int(i) + current_shift) % int(uint(NSLOTS)); 
    return (p<0) ? uint(-p) : uint(p);
  }

  /** Returns the index in the ring of offers at which the offer Id at position `p` in the book is stored */
  function index_of_position(uint p) internal view returns (uint) {
    int i = (int(p) - current_shift) % int(uint(NSLOTS));
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

  /** Price function to determine the price of position i of the OB depending on initial_price and paramater delta*/
  /** Default here is arithmetic progression, override this function to implement a geometric one for instance*/
  function __price_of_position__(uint p, uint delta, uint init_price) internal virtual pure returns (uint) {
    return delta * p + init_price;
  }

  /** Returns the quantity of quote tokens the offer at position `p` is asking (for selling base) or bidding (for buying base) according to actual shift */
  /** NB the returned quantity might not the one actually offered on Mangrove if the price has shifted or if the offer is not Live*/
  function quotes_of_position(uint p, uint delta, uint base_amount, uint init_price, uint8 base_decimals) internal pure returns (uint) {
    return __price_of_position__(p,delta,init_price)*base_amount / 10**base_decimals;
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
      
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      // defining new_gives (in quotes) based on default base amount for new offers
      uint new_gives = quotes_of_position(pos, current_delta, current_new_base_amount, INIT_MINPRICE, BASE_DECIMALS);
      updateOfferInternal({
        outbound_tkn:QUOTE,
        inbound_tkn:BASE,
        offerId:ASKS[index],
        wants: current_new_base_amount,
        gives: new_gives,
        gasprice: 0,
        gasreq: OFR_GASREQ,
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

      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_wants = quotes_of_position(pos, current_delta, current_new_base_amount, INIT_MINPRICE, BASE_DECIMALS);
      updateOfferInternal({
        outbound_tkn:BASE,
        inbound_tkn:QUOTE,
        offerId:BIDS[index],
        wants: new_wants,
        gives: current_new_base_amount,
        gasprice: 0,
        gasreq: OFR_GASREQ,
        pivotId: pos<NSLOTS-1 ? index_of_position(pos+1) : 0,
        provision:0
      });
      s--;
      index = prev_index(index);
    }
  }

  // if price has increased one should lower gives, otherwise give the residual of the offer
  // function __newGives__(MgvLib.SingleOrder calldata order) virtual overrides returns (uint) {
  //   uint index;
  //   if (order.outbound_tkn == BASE){ // order is buying BASE so offer was an ASK
  //     index = index_of_ask[order.offerId];
  //     uint old_price = (order.offer.wants*10**BASE_DECIMALS) / order.offer.gives;
  //     uint new_price = __price_of_position__(
  //       position_of_index(index), 
  //       current_delta, INIT_MINPRICE
  //     );
  //     if (old_price < new_price) {

  //     } 
  //   } else {
  //     index = index_of_bid[order.offerId];
  //   }
  //   return __gives_of_position__(
  //     position_of_index(index),
  //     current_delta,
  //     INIT_MINGIVES
  //   ); 
  // }

  // function __newWants__(MgvLib.SingleOrder calldata order) virtual overrides returns (uint) {

  // }


  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {

  }

  // TODO  __posthookSuccess__
  // TODO  compact/dilate functions
  // TODO __posthookFail__
  
}
