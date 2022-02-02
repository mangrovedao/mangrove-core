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

  uint[NSLOTS] immutable ASKS;
  uint[NSLOTS] immutable BIDS;
  address immutable BASE;
  address immutable QUOTE;

  /** Mutables */
  int current_shift=0;
  uint current_delta; // offer[i+1].gives = offer[i].gives + current_delta
  
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
    return i>0?i-1:NSLOTS-1
  }

  /** Returns the quantity of outbound_tkn the offer at position `p` is supposed to offer according to actual shift */
  /** NB the returned `gives` might not the one actually offered on Mangrove if the price has shifted or if the offer is not Live*/
  function __gives_of_position__(uint p) internal virtual view returns (uint) {
    return current_delta*p*INIT_MINGIVES;
  } 

/** Recenter the order book by shifting min price up `s` positions in the book */
/** As a consequence `s` Bids will be cancelled and `s` new asks will be posted */
  function positive_shift(uint s) public internalOrAdmin {
    uint index = index_of_position(0);
    current_shift += int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Bids[index],..,Bids[index+`s` % N]] are retracted
      retractOffer(BASE,QUOTE,BIDS[index],false);
      // slots are replaced by `s` Asks.
      // NB the price of Ask[index] is computed given the new position associated to `index`
      // because the shift has been updated above
      P.Offer.t memory offer = MGV.offers(
        QUOTE,
        BASE,
        ASKS[index]
      );
      P.OfferDetail.t memory offerDetail = MGV.offers(
        QUOTE,
        BASE,
        ASKS[index]
      );
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives = __gives_of_position__(pos);
      uint new_wants = (offer.wants() * new_gives) / offer.gives();
      updateOffer({
        outbound_tkn:QUOTE,
        inbound_tkn:BASE,
        offerId:ASKS[index],
        wants: new_wants,
        gives: new_gives,
        gasprice: offerDetail.gasprice(),
        gasreq: offerDetail.gasreq(),
        pivotId: pos>0 ? index_of_position(pos-1) : 0
      });
      s--;
      index = next_index(index);
    }
  }

  /** Recenter the order book by shifting max price down `s` positions in the book */
  /** As a consequence `s` Asks will be cancelled and `s` new Bids will be posted */
  function negative_shift(uint s) public internalOrAdmin {
    uint index = index_of_position(NSLOTS-1);
    current_shift -= int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    while (s>0) {
      // slots occupied by [Asks[index-`s` % N],..,Asks[index]] are retracted
      retractOffer(QUOTE,BASE,ASKS[index],false);
      // slots are replaced by `s` Bids.
      // NB the price of Bids[index] is computed given the new position associated to `index`
      // because the shift has been updated above
      P.Offer.t memory offer = MGV.offers(
        BASE,
        QUOTE,
        BIDS[index]
      );
      P.OfferDetail.t memory offerDetail = MGV.offers(
        BASE,
        QUOTE,
        BIDS[index]
      );
      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives = __gives_of_position__(pos);
      uint new_wants = (offer.wants() * new_gives) / offer.gives();
      updateOffer({
        outbound_tkn:BASE,
        inbound_tkn:QUOTE,
        offerId:BIDS[index],
        wants: new_wants,
        gives: new_gives,
        gasprice: offerDetail.gasprice(),
        gasreq: offerDetail.gasreq(),
        pivotId: pos<NSLOTS-1 ? index_of_position(pos+1) : 0
      });
      s--;
      index = prev_index(index);
    }
  }

  constructor(
    address _MGV,
    address _BASE,
    address _QUOTE,
    uint _pmin,
    uint _NSLOTS // initial mid-price will be price_of_position(_NSLOTS/2)
  ) MangroveOffer(_MGV) {}

  // sets P(tk0|tk1)
  // one wants P(tk0|tk1).P(tk1|tk0) >= 1
  function setPrice(
    address tk0,
    address tk1,
    uint p
  ) external onlyAdmin {
    price[tk0][tk1] = p; // has tk0.decimals() decimals
  }

  function startStrat(
    address tk0,
    address tk1,
    uint gives // amount of tk0 (with tk0.decimals() decimals)
  ) external payable onlyAdmin {
    MGV.fund{value: msg.value}();
    require(repostOffer(tk0, tk1, gives), "Could not start strategy");
    IERC20(tk0).approve(address(MGV), type(uint).max); // approving MGV for tk0 transfer
    IERC20(tk1).approve(address(MGV), type(uint).max); // approving MGV for tk1 transfer
  }

  // at this stage contract has `received` amount in token0
  function repostOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint gives // in outbound_tkn
  ) internal returns (bool) {
    // computing how much inbound_tkn one should ask for `gives` amount of outbound tokens
    // NB p_10 has inbound_tkn.decimals() number of decimals
    uint p_10 = price[inbound_tkn][outbound_tkn];
    if (p_10 == 0) {
      // ! p_10 has the decimals of inbound_tkn
      emit MissingPriceConverter(inbound_tkn, outbound_tkn);
      return false;
    }
    uint wants = div_(
      mul_(p_10, gives), // p(base|quote).(gives:quote) : base
      10**(IERC20(outbound_tkn).decimals())
    ); // in base units
    uint offerId = offers[outbound_tkn][inbound_tkn];
    if (offerId == 0) {
      try
        MGV.newOffer(outbound_tkn, inbound_tkn, wants, gives, OFR_GASREQ, 0, 0)
      returns (uint id) {
        if (id > 0) {
          offers[outbound_tkn][inbound_tkn] = id;
          return true;
        } else {
          return false;
        }
      } catch {
        return false;
      }
    } else {
      try
        MGV.updateOffer(
          outbound_tkn,
          inbound_tkn,
          wants,
          gives,
          // offerId is already on the book so a good pivot
          OFR_GASREQ, // default value
          0, // default value
          offerId,
          offerId
        )
      {
        return true;
      } catch Error(string memory message) {
        emit PosthookFail(outbound_tkn, inbound_tkn, offerId, message);
        return false;
      }
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    override
  {
    address token0 = order.outbound_tkn;
    address token1 = order.inbound_tkn;
    uint offer_received = order.offer.wants(); // amount with token1.decimals() decimals
    repostOffer({
      outbound_tkn: token1,
      inbound_tkn: token0,
      gives: offer_received
    });
  }

  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    // checks whether `this` contract has enough `base` token
    uint missingGet = SingleUser.__get__(amount, order);
    // if not tries to fetch missing liquidity on compound using `CompoundTrader`'s strat
    return super.__get__(missingGet, order);
  }
}
