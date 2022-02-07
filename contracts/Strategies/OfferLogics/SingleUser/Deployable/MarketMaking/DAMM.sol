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
import "hardhat/console.sol";

contract DAMM is Persistent {
  using P.Offer for P.Offer.t;
  using P.OfferDetail for P.OfferDetail.t;

  event BidAtMaxPrice(address indexed outbound_tkn, address indexed inbound_tkn, uint offerId);
  event AskAtMinPrice(address indexed outbound_tkn, address indexed inbound_tkn, uint offerId);
  event PriceParamUpdated(uint delta);

  /** Immutables */
  // total number of Asks (resp. Bids)
  uint16 immutable NSLOTS; 

  // initial min price
  uint96 immutable BASE_0; 
  uint96 immutable QUOTE_0;

  address immutable BASE;
  address immutable QUOTE;

  /** Mutables */
  //NB if one wants to allow this contract to be multi-makers one should use uint[][] ASKS/BIDS and allocate a new array for each maker.
  uint[] ASKS;
  uint[] BIDS;
  mapping(uint => uint) index_of_bid; // bidId -> index
  mapping(uint => uint) index_of_ask; // askId -> index
  
  
  //NB if one wants to allow this contract to be multi-makers one should use uint[] for each mutable fields to allow user specific parameters.
  int public current_shift;

  // P_i = (Q_0 + i*delta)/B_0
  uint public current_delta; // price decimals precision
  bool public is_initialized;

  modifier initialized() {
    require(is_initialized, "DAMM/uninitialized");
    _; 
  }

  /** NB: constructor is `payable` in order to allow deployer to fund initial bids and asks */
  constructor(
    address payable mgv,
    address base,
    address quote,
    uint base_0,
    uint quote_0,
    uint nslots
  ) MangroveOffer(mgv) {
    // sanity check
    require(
      nslots>0 
    && mgv != address(0)
    && uint16(nslots) == nslots 
    && uint96(base_0) == base_0
    && uint96(quote_0) == quote_0,
    "DAMM/constructor/invalidArguments"
    );
    BASE = base;
    QUOTE = quote;
    NSLOTS = uint16(nslots);
    ASKS = new uint[](nslots);
    BIDS = new uint[](nslots);
    BASE_0 = uint96(base_0);
    QUOTE_0 = uint96(quote_0);
  }

  function _getPivot(uint[] calldata pivots, uint i) internal returns (uint) {
    if (pivots[i]!=0) {
      return pivots[i];
    } else {
      return i>0?pivots[i-1]:0;
    }
  }

  function initialize(
    uint delta, // parameter for quote progression as position in the OB increases (default is arithmetic progression)
    uint nbids, // `nbids <= NSLOTS`. Says how many bids should be placed
    uint[][2] calldata pivotIds // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
  ) public internalOrAdmin {
    /** Initializing Asks and Bids */
    /** NB we assume Mangrove is already provisioned for posting NSLOTS asks and NSLOTS bids*/
    /** NB cannot post newOffer with infinite gasreq since fallback OFR_GASREQ is not defined yet (and default is likely wrong) */
    require(nbids < NSLOTS, "DAMM/initialize/noSlotForAsk");
    require(nbids > 0, "DAMM/initialize/noSlotForBids");
    current_delta = delta;
    
    uint i;
    for(i=0; i<NSLOTS; i++) {
      // bidId is either fresh is contract is not initialized or already present at index
      uint bidId;
      if(is_initialized) {
        bidId = BIDS[i];
        updateOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: bases_of_position(i, QUOTE_0),
          gives: QUOTE_0,
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
          wants: bases_of_position(i, QUOTE_0),
          gives: QUOTE_0,
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
          wants: quotes_of_position(i, BASE_0),
          gives: BASE_0, 
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
          wants: quotes_of_position(i, BASE_0),
          gives: BASE_0, 
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
    return (i+1) % NSLOTS;
  }

  /**Previous index in the ring of offers */
  function prev_index(uint i) internal view returns (uint) {
    return i>0 ? i-1 : NSLOTS-1;
  }

  /** Price function to determine the price of position i of the OB depending on initial_price and paramater delta*/
  /** (1) Q/B = Q(i)/B_0 */
  /** from (1) one derives: */
  /** Q = Q(i)/B_0 * B (2) and B = B_0/Q(i) * Q (3)*/
  /** where Q(i) is the quote amount at position i (by default arithmetic progression) */
  function __quote_progression__(uint position) 
  internal virtual view returns (uint) {
    return (current_delta * position + QUOTE_0); 
  }

  /** Returns the quantity of quote tokens for an offer at position `p` given an amount of Base tokens (eq. 2)*/
  function quotes_of_position(uint p, uint base_amount) 
  internal view returns (uint) {
    return (__quote_progression__(p) * base_amount) / BASE_0;
  }

  /** Returns the quantity of base tokens for an offer at position `p` given an amount of quote tokens (eq. 3)*/
  function bases_of_position(uint p, uint quote_amount)
  internal returns (uint) {
    return quote_amount * BASE_0 / __quote_progression__(p);
  }

  function shift(int s) external onlyAdmin initialized {
    if (s<0) {
      negative_shift(uint(-s));
    } else {
      positive_shift(uint(s));
    }
  }

  /** Recenter the order book by shifting min price up `s` positions in the book */
  /** As a consequence `s` Bids will be cancelled and `s` new asks will be posted */
  function positive_shift(uint s) internal {
    uint index = index_of_position(0);
    current_shift += int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Bids[index],..,Bids[index+`s` % N]] are retracted
      retractOfferInternal({
        outbound_tkn: QUOTE, 
        inbound_tkn: BASE,
        offerId: BIDS[index], 
        deprovision: false
      });
      // slots are replaced by `s` Asks.
      // NB the price of Ask[index] is computed given the new position associated to `index`
      // because the shift has been updated above
      
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      // defining new_gives (in bases) based on default quote amount for new offers
      // in order to minimize base input to the strat
      uint new_gives = bases_of_position(pos, QUOTE_0);
      updateOfferInternal({
        outbound_tkn: BASE,
        inbound_tkn: QUOTE,
        offerId: ASKS[index],
        wants: QUOTE_0,
        gives: new_gives,
        gasprice: 0,
        gasreq: OFR_GASREQ,
        pivotId: pos>0 ? ASKS[index_of_position(pos-1)] : 0,
        provision:0
      });
      s--;
      index = next_index(index);
    }
  }

  /** Recenter the order book by shifting max price down `s` positions in the book */
  /** As a consequence `s` Asks will be cancelled and `s` new Bids will be posted */
  function negative_shift(uint s) internal {
    uint index = index_of_position(NSLOTS-1);
    current_shift -= int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Asks[index-`s` % N],..,Asks[index]] are retracted
      retractOfferInternal({
        outbound_tkn: BASE, 
        inbound_tkn: QUOTE, 
        offerId: ASKS[index],
        deprovision: false
      });
      // slots are replaced by `s` Bids.
      // NB the price of Bids[index] is computed given the new position associated to `index`
      // because the shift has been updated above

      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_wants = quotes_of_position(pos, BASE_0);
      updateOfferInternal({
        outbound_tkn: QUOTE,
        inbound_tkn: BASE,
        offerId: BIDS[index],
        wants: new_wants,
        gives: BASE_0,
        gasprice: 0,
        gasreq: OFR_GASREQ,
        pivotId: pos<NSLOTS-1 ? BIDS[index_of_position(pos+1)] : 0,
        provision:0
      });
      s--;
      index = prev_index(index);
    }
  }

  function lazyResetPriceParameter(uint delta) public internalOrAdmin {
    current_delta = delta;
    emit PriceParamUpdated(delta);
  }

  // for reposting partial filled offers one always gives the residual (default behavior)
  // and adapts wants to the new price (if different).
  function __residualWants__(MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    if (order.outbound_tkn == BASE){ // Ask offer (selling BASE) 
      uint index = index_of_ask[order.offerId];
      uint residual_base = __residualGives__(order); // default
      return quotes_of_position(
        position_of_index(index),
        residual_base
      );
    } else {
      // Bid order (buying BASE)
      uint index = index_of_bid[order.offerId];
      uint residual_quote = __residualGives__(order); // default
      return bases_of_position(
        position_of_index(index),
        residual_quote
      );
    }
  }

  /** Define what to do when the AMM boundaries are reached (either when reposting a bid or a ask) */
  function __boundariesReached__(bool bid, uint offerId) internal virtual {
    if (bid) {
      emit BidAtMaxPrice(QUOTE, BASE, offerId);
    } else {
      emit AskAtMinPrice(BASE, QUOTE, offerId);
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    super.__posthookSuccess__(order); // reposting residual of offer using `this.__newWants__` to update price
    if (order.outbound_tkn == BASE) { // Ask Offer (`this` contract just sold some BASE @ pos)
      uint pos = position_of_index(index_of_ask[order.offerId]);
      // bid for some BASE token with the received QUOTE tokens @ pos-1
      if (pos > 0) {
        uint ofrId = BIDS[index_of_position(pos-1)];
        updateBid({offerId:ofrId, quote_amount:order.gives, position:pos-1});
        if (pos == NSLOTS-1) {
          __boundariesReached__(true, ofrId);
        }
      } else { // Ask cannot be at Pmin unless a shift has eliminated all bids
        emit PosthookFail(
          order.outbound_tkn,
          order.inbound_tkn,
          order.offerId,
          "DAMM/posthook/BuyingOutOfPriceRange"  
        );
        return;
      }
    } else { // Bid offer (`this` contract just bought some BASE)
      uint pos = position_of_index(index_of_bid[order.offerId]);
      // ask for some QUOTE tokens in exchange of the received BASE tokens @ pos+1
      if (pos < NSLOTS-1) {
        uint ofrId = ASKS[index_of_position(pos+1)];
        updateAsk({offerId:ofrId, base_amount:order.gives, position: pos+1});
        if (pos == 1) {
          __boundariesReached__(false, ofrId);
        }
      } else { // Take profit
        emit PosthookFail(
          order.outbound_tkn,
          order.inbound_tkn,
          order.offerId,
          "DAMM/posthook/SellingOutOfPriceRange"  
        );
        return;
      }
    }
  }

  function updateBid(uint offerId, uint quote_amount, uint position) internal {
    // outbound : QUOTE, inbound: BASE
    uint old_gives = MGV.offers(QUOTE, BASE, offerId).gives();
    uint new_gives = old_gives + quote_amount;
    uint pivot;
    if (old_gives == 0) { // offer was not live
    // Warning: `position==0` here would be a bad situation: 
    // bids offer list is empty so we don't have a good pivot for inserting new bid
    // this will likely run out of gas.
      pivot = position == 0 ? 0 : BIDS[index_of_position(position-1)];
    } else {
      pivot = offerId;
    }
    // price * e-PD = gives / wants
    // hence wants = (gives*e+PD) / price 
    uint new_wants = bases_of_position(position, new_gives);
    updateOfferInternal({
      outbound_tkn: QUOTE,
      inbound_tkn: BASE,
      wants: new_wants,
      gives: new_gives,
      gasreq: OFR_GASREQ,
      gasprice: 0,
      pivotId: pivot,
      offerId: offerId,
      provision: 0
    });
  }

  function updateAsk(uint offerId, uint base_amount, uint position) internal {
    // outbound : BASE, inbound: QUOTE
    uint old_gives = MGV.offers(BASE, QUOTE, offerId).gives();
    uint new_gives = old_gives + base_amount;
    uint pivot;
    if (old_gives == 0) { // offer was not live
    // Warning: `position==NSLOTS-1` here would be a bad situation: 
    // asks offer list is empty so we don't have a good pivot for inserting new ask
    // this will likely run out of gas.
      pivot = position == NSLOTS-1 ? 0 : ASKS[index_of_position(position+1)];
    } else {
      pivot = offerId;
    }
    uint new_wants = quotes_of_position(position, new_gives);
    updateOfferInternal({
      outbound_tkn: BASE,
      inbound_tkn: QUOTE,
      wants: new_wants,
      gives: new_gives,
      gasreq: OFR_GASREQ,
      gasprice: 0,
      pivotId: pivot,
      offerId: offerId,
      provision: 0
    });
  }

  // TODO __posthookFail__
  // TODO initialize by chunks
  
}
