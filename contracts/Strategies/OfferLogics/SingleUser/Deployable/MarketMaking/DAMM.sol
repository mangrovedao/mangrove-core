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
  uint16 immutable NSLOTS; // total number of Asks (resp. Bids)
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
  int public current_shift;

  // offer[i+1] = offer[i] + current_delta for arithmetic progression. offer[i+1] = current_delta*offer[i] for geometric
  uint public current_delta; // quote decimals precision
  uint public current_new_base_amount; // new base amount for fresh offers
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
    require(nbids < NSLOTS, "DAMM/initialize/noSlotForAsk");
    require(nbids > 0, "DAMM/initialize/noSlotForBids");
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
          gives: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS, QUOTE_DECIMALS), 
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
          gives: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS, QUOTE_DECIMALS),
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
          wants: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS, QUOTE_DECIMALS),
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
          wants: quotes_of_position(i, delta, default_base, INIT_MINPRICE, BASE_DECIMALS, QUOTE_DECIMALS),
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
    return (i+1) % NSLOTS;
  }

  /**Previous index in the ring of offers */
  function prev_index(uint i) internal view returns (uint) {
    return i>0 ? i-1 : NSLOTS-1;
  }

  /** Price function to determine the price of position i of the OB depending on initial_price and paramater delta*/
  /** Default here is arithmetic progression, override this function to implement a geometric one for instance*/
  function __price_of_position__(uint position, uint delta, uint init_price, uint quote_decimals) 
  internal virtual pure returns (uint) {
    // price * e-QD = delta * e-QD * position * e-QD + init_price * e-QD
    // price = delta * position * e-QD + init_price

    return (delta * position)/10**quote_decimals + init_price;
  }

  /** Returns the quantity of quote tokens the offer at position `p` is asking (for selling base) or bidding (for buying base) according to actual shift */
  /** NB the returned quantity might not the one actually offered on Mangrove if the price has shifted or if the offer is not Live*/
  function quotes_of_position(uint p, uint delta, uint base_amount, uint init_price, uint8 base_decimals, uint8 quote_decimals) 
  internal pure returns (uint) {
    // price(@pos) * e-QD = quote_amount * e-QD / base_amount * e-BD
    // hence quote_amount = price(@pos) * base_amount * e-BD
    return (__price_of_position__(p,delta,init_price,quote_decimals)*base_amount) / 10**base_decimals;
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
      // defining new_wants (in quotes) based on default base amount for new offers
      uint new_wants = quotes_of_position(
        pos, 
        current_delta, 
        current_new_base_amount, 
        INIT_MINPRICE, 
        BASE_DECIMALS,
        QUOTE_DECIMALS
      );
      updateOfferInternal({
        outbound_tkn: BASE,
        inbound_tkn: QUOTE,
        offerId: ASKS[index],
        wants: new_wants,
        gives: current_new_base_amount,
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
      uint new_gives = quotes_of_position(
        pos, 
        current_delta, 
        current_new_base_amount, 
        INIT_MINPRICE, 
        BASE_DECIMALS,
        QUOTE_DECIMALS
      );
      updateOfferInternal({
        outbound_tkn: QUOTE,
        inbound_tkn: BASE,
        offerId: BIDS[index],
        wants: current_new_base_amount,
        gives: new_gives,
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
  }

  // for reposting partial filled offers one always gives the residual (default behavior)
  // and adapts wants to the new price (if different).
  function __residualWants__(MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    uint residual_gives = __residualGives__(order); // default
    uint index;
    if (order.outbound_tkn == BASE){ // Ask offer (selling BASE) 
      index = index_of_ask[order.offerId];
    } else {
      // Bid order (buying BASE)
      index = index_of_bid[order.offerId];
    }
    uint target_price = __price_of_position__(
      position_of_index(index), 
      current_delta, 
      INIT_MINPRICE,
      QUOTE_DECIMALS
    );
    // new_wants / (residual_gives * e-BD) = target_price
    // hence new_wants = target_price * residual_gives * e-BD
    return (target_price * residual_gives) / 10**BASE_DECIMALS;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    super.__posthookSuccess__(order); // reposting residual of offer using __newWants__ to update price
    if (order.outbound_tkn == BASE) { // Ask Offer (`this` contract just sold some BASE @ pos)
      uint pos = position_of_index(index_of_ask[order.offerId]);
      // bid for some BASE token with the received QUOTE tokens @ pos-1
      if (pos > 0) {
        uint ofrId = BIDS[index_of_position(pos-1)];
        updateBid({offerId:ofrId, quote_amount:order.gives, position:pos-1});
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
    uint price = __price_of_position__(position, current_delta, INIT_MINPRICE, QUOTE_DECIMALS);
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
    // price * e-QD = gives * e-QD / wants * e-BD
    // hence wants = (gives*e+BD) / price 
    uint new_wants = (new_gives * 10**BASE_DECIMALS) / price;
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
    uint price = __price_of_position__(position, current_delta, INIT_MINPRICE, QUOTE_DECIMALS);
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
    // price * e-QD = gives * e-QD / wants * e-BD
    // hence wants = (gives*e+BD) / price 
    uint new_wants = (new_gives * 10**BASE_DECIMALS) / price;
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
  
}
