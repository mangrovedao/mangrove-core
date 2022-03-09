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

contract Mango is Persistent {
  using P.Offer for P.Offer.t;
  using P.OfferDetail for P.OfferDetail.t;

  event BidAtMaxPosition(address quote, address base, uint offerId);
  event AskAtMinPosition(address quote, address base, uint offerId);
  event Initialized(uint from, uint to);

  /** Immutables */
  // total number of Asks (resp. Bids)
  uint16 public immutable NSLOTS;

  // initial min price given by `QUOTE_0/BASE_0`
  uint96 immutable BASE_0;
  uint96 immutable QUOTE_0;

  address public immutable BASE;
  address public immutable QUOTE;

  /** Mutables */
  //NB if one wants to allow this contract to be multi-makers one should use uint[][] ASKS/BIDS and allocate a new array for each maker.
  uint[] ASKS;
  uint[] BIDS;
  mapping(uint => uint) index_of_bid; // bidId -> index
  mapping(uint => uint) index_of_ask; // askId -> index

  //NB if one wants to allow this contract to be multi-makers one should use uint[] for each mutable fields to allow user specific parameters.
  int current_shift;

  // price increment is current_delta / BASE_0
  uint current_delta; // quote increment

  // triggers `__boundariesReached__` whenever amounts of bids/asks is below `current_min_offer_type`
  uint current_min_offer_type;

  // whether the strat reneges on offers
  bool paused = false;

  // Base and quote token treasuries
  address current_base_treasury;
  address current_quote_treasury;

  constructor(
    address payable mgv,
    address base,
    address quote,
    uint base_0,
    uint quote_0,
    uint nslots,
    uint delta
  ) MangroveOffer(mgv) {
    // sanity check
    require(
      nslots > 0 &&
        mgv != address(0) &&
        uint16(nslots) == nslots &&
        uint96(base_0) == base_0 &&
        uint96(quote_0) == quote_0,
      "Mango/constructor/invalidArguments"
    );
    BASE = base;
    QUOTE = quote;
    NSLOTS = uint16(nslots);
    ASKS = new uint[](nslots);
    BIDS = new uint[](nslots);
    BASE_0 = uint96(base_0);
    QUOTE_0 = uint96(quote_0);
    current_delta = delta;
    current_min_offer_type = 1;
    current_quote_treasury = msg.sender;
    current_base_treasury = msg.sender;
    OFR_GASREQ = 400_000; // dry run OK with 200_000
  }

  function initialize(
    uint lastBidPosition, // [0,..,lastBidPosition] are bids
    bool withBase,
    uint from, // slice (from included)
    uint to, // to index excluded
    uint[][2] calldata pivotIds, // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
    uint[] calldata tokenAmounts
  ) public mgvOrAdmin {
    /** Initializing Asks and Bids */
    /** NB we assume Mangrove is already provisioned for posting NSLOTS asks and NSLOTS bids*/
    /** NB cannot post newOffer with infinite gasreq since fallback OFR_GASREQ is not defined yet (and default is likely wrong) */
    require(
      to > from && pivotIds[0].length == to - from,
      "Mango/initialize/invalidSlice"
    );
    require(
      tokenAmounts.length == to - from,
      "Mango/initialize/invalidBaseAmounts"
    );
    require(lastBidPosition < NSLOTS - 1, "Mango/initialize/NoSlotForAsks"); // bidding => slice doesn't fill the book
    uint i;
    for (i = from; i < to; i++) {
      if (i <= lastBidPosition) {
        uint bidPivot = pivotIds[0][i - from];
        bidPivot = bidPivot > 0
          ? bidPivot // taking pivot from the user
          : i > 0
          ? BIDS[i - 1]
          : 0; // otherwise getting last inserted offer as pivot
        updateBid({
          index: i,
          withBase: withBase,
          reset: true, // overwrites old value
          amount: tokenAmounts[i - from],
          pivotId: bidPivot
        });
      } else {
        uint askPivot = pivotIds[1][i - from];
        askPivot = askPivot > 0
          ? askPivot // taking pivot from the user
          : i > 0
          ? ASKS[i - 1]
          : 0; // otherwise getting last inserted offer as pivot
        updateAsk({
          index: i,
          withBase: withBase,
          reset: true,
          amount: tokenAmounts[i - from],
          pivotId: askPivot
        });
      }
    }
    emit Initialized({from: from, to: to});
  }

  /** Sets the account from which base (resp. quote) tokens need to be fetched or put during trade execution*/
  function set_treasury(bool base, address treasury) external onlyAdmin {
    require(treasury != address(0), "Mango/set_treasury/zeroAddress");
    if (base) {
      current_base_treasury = treasury;
    } else {
      current_quote_treasury = treasury;
    }
  }

  function get_treasury(bool base) external view onlyAdmin returns (address) {
    return base ? current_base_treasury : current_quote_treasury;
  }

  /** Deposits received tokens into the corresponding treasury*/
  function __put__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    if (order.inbound_tkn == BASE && current_base_treasury != address(this)) {
      return IERC20(BASE).transfer(current_base_treasury, amount) ? 0 : amount;
    }
    if (current_quote_treasury != address(this)) {
      return
        IERC20(QUOTE).transfer(current_quote_treasury, amount) ? 0 : amount;
    }
    // order.inbound_tkn has to be either BASE or QUOTE so only possibility is `this` is treasury
    return 0;
  }

  /** Fetches required tokens from the corresponding treasury*/
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    if (order.outbound_tkn == BASE && current_base_treasury != address(this)) {
      return
        IERC20(BASE).transferFrom(current_base_treasury, address(this), amount)
          ? 0
          : amount;
    }
    if (current_quote_treasury != address(this)) {
      return
        IERC20(QUOTE).transferFrom(
          current_quote_treasury,
          address(this),
          amount
        )
          ? 0
          : amount;
    }
    // order.outbound_tkn has to be either BASE or QUOTE so only possibility is `this` is treasury
    return 0;
  }

  // with ba=0:bids only, ba=1: asks only ba>1 all
  function retractOffers(
    uint ba,
    uint from,
    uint to
  ) external onlyAdmin returns (uint collected) {
    for (uint i = from; i < to; i++) {
      if (ba > 0) {
        // asks or bids+asks
        collected += ASKS[i] > 0
          ? retractOfferInternal(BASE, QUOTE, ASKS[i], true)
          : 0;
      }
      if (ba == 0 || ba > 1) {
        // bids or bids + asks
        collected += BIDS[i] > 0
          ? retractOfferInternal(QUOTE, BASE, BIDS[i], true)
          : 0;
      }
    }
  }

  /** Setters and getters */
  function get_delta() external view onlyAdmin returns (uint) {
    return current_delta;
  }

  function set_delta(uint delta) public mgvOrAdmin {
    current_delta = delta;
  }

  function get_shift() external view onlyAdmin returns (int) {
    return current_shift;
  }

  /** Shift the price (induced by quote amount) of n slots down or up */
  /** price at position i will be shifted (up or down depending on the sign of `shift`) */
  /** New positions 0<= i < s are initialized with amount[i] in base tokens if `withBase`. In quote tokens otherwise*/
  function set_shift(
    int s,
    bool withBase,
    uint[] calldata amounts
  ) public mgvOrAdmin {
    require(
      amounts.length == (s < 0 ? uint(-s) : uint(s)),
      "Mango/set_shift/notEnoughAmounts"
    );
    if (s < 0) {
      negative_shift(uint(-s), withBase, amounts);
    } else {
      positive_shift(uint(s), withBase, amounts);
    }
  }

  function set_min_offer_type(uint m) public mgvOrAdmin {
    current_min_offer_type = m;
  }

  // return Mango offer Ids on Mangrove. If `liveOnly` will only return offer Ids that are live (0 otherwise).
  function get_offers(bool liveOnly)
    external
    view
    returns (uint[][2] memory offers)
  {
    offers[0] = new uint[](NSLOTS);
    offers[1] = new uint[](NSLOTS);
    for (uint i = 0; i < NSLOTS; i++) {
      uint askId = ASKS[index_of_position(i)];
      uint bidId = BIDS[index_of_position(i)];

      offers[0][i] = (MGV.offers(QUOTE, BASE, bidId).gives() > 0 || !liveOnly)
        ? BIDS[index_of_position(i)]
        : 0;
      offers[1][i] = (MGV.offers(BASE, QUOTE, askId).gives() > 0 || !liveOnly)
        ? ASKS[index_of_position(i)]
        : 0;
    }
  }

  // starts reneging all offers
  // NB reneged offers will not be reposted
  function pause() public mgvOrAdmin {
    paused = true;
  }

  function restart() external onlyAdmin {
    paused = false;
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool proceed)
  {
    order; //shh
    proceed = !paused;
  }

  function writeOffer(
    uint index,
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId
  ) internal {
    inbound_tkn; // shh
    if (outbound_tkn == BASE) {
      // Asks
      if (ASKS[index] == 0) {
        // offer slot not initialized yet
        ASKS[index] = newOfferInternal({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          wants: wants,
          gives: gives,
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: pivotId,
          provision: 0
        });
        index_of_ask[ASKS[index]] = index;
      } else {
        ASKS[index] = updateOfferInternal({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          wants: wants,
          gives: gives,
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: pivotId,
          provision: 0,
          offerId: ASKS[index]
        });
      }
      require(ASKS[index] > 0, "Mango/writeOfferFailed");
      if (position_of_index(index) <= current_min_offer_type) {
        __boundariesReached__(false, ASKS[index]);
      }
    } else {
      // Bids
      if (BIDS[index] == 0) {
        BIDS[index] = newOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: wants,
          gives: gives,
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: pivotId,
          provision: 0
        });
        index_of_bid[BIDS[index]] = index;
      } else {
        BIDS[index] = updateOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          wants: wants,
          gives: gives,
          gasreq: OFR_GASREQ,
          gasprice: 0,
          pivotId: pivotId,
          provision: 0,
          offerId: BIDS[index]
        });
      }
      require(BIDS[index] > 0, "Mango/writeOfferFailed");
      if (position_of_index(index) >= NSLOTS - 1 - current_min_offer_type) {
        __boundariesReached__(true, BIDS[index]);
      }
    }
  }

  // returns the value of x in the ring [0,m]
  // i.e if x>=0 this is just x % m
  // if x<0 this is m + (x % m)
  function modulo(int x, uint m) internal pure returns (uint) {
    if (x >= 0) {
      return uint(x) % m;
    } else {
      return uint(int(m) + (x % int(m)));
    }
  }

  /** Minimal amount of quotes for the general term of the `__quote_progression__` */
  /** If min price was not shifted this is just `QUOTE_0` */
  /** In general this is QUOTE_0 + shift*delta */
  function quote_min() internal view returns (uint) {
    int qm = int(uint(QUOTE_0)) + current_shift * int(current_delta);
    require(qm > 0, "Mango/quote_min/ShiftUnderflow");
    return (uint(qm));
  }

  /** Returns the position in the order book of the offer associated to this index `i` */
  function position_of_index(uint i) internal view returns (uint) {
    // position(i) = (i+shift) % N
    return modulo(int(i) - current_shift, NSLOTS);
  }

  /** Returns the index in the ring of offers at which the offer Id at position `p` in the book is stored */
  function index_of_position(uint p) internal view returns (uint) {
    return modulo(int(p) + current_shift, NSLOTS);
  }

  /**Next index in the ring of offers */
  function next_index(uint i) internal view returns (uint) {
    return (i + 1) % NSLOTS;
  }

  /**Previous index in the ring of offers */
  function prev_index(uint i) internal view returns (uint) {
    return i > 0 ? i - 1 : NSLOTS - 1;
  }

  /** Function that determines the amount of quotes that are offered at position i of the OB depending on initial_price and paramater delta*/
  /** Here the default is an arithmetic progression */
  function __quote_progression__(uint position)
    internal
    view
    virtual
    returns (uint)
  {
    return current_delta * position + quote_min();
  }

  /** Returns the quantity of quote tokens for an offer at position `p` given an amount of Base tokens (eq. 2)*/
  function quotes_of_position(uint p, uint base_amount)
    internal
    view
    returns (uint)
  {
    return (__quote_progression__(p) * base_amount) / BASE_0;
  }

  /** Returns the quantity of base tokens for an offer at position `p` given an amount of quote tokens (eq. 3)*/
  function bases_of_position(uint p, uint quote_amount)
    internal
    view
    returns (uint)
  {
    return (quote_amount * BASE_0) / __quote_progression__(p);
  }

  /** Recenter the order book by shifting min price up `s` positions in the book */
  /** As a consequence `s` Bids will be cancelled and `s` new asks will be posted */
  function positive_shift(
    uint s,
    bool withBase,
    uint[] calldata amounts
  ) internal {
    require(s < NSLOTS, "Mango/shift/positiveShiftTooLarge");
    uint index = index_of_position(0);
    current_shift += int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    uint cpt = 0;
    while (cpt < s) {
      // slots occupied by [Bids[index],..,Bids[index+`s` % N]] are retracted
      if (BIDS[index] != 0) {
        retractOfferInternal({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          offerId: BIDS[index],
          deprovision: false
        });
      }
      // slots are replaced by `s` Asks.
      // NB the price of Ask[index] is computed given the new position associated to `index`
      // because the shift has been updated above

      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives;
      uint new_wants;
      if (withBase) {
        // posting new ASKS with base amount fixed
        new_gives = amounts[cpt];
        new_wants = quotes_of_position(pos, amounts[cpt]);
      } else {
        // posting new ASKS with quote amount fixed
        new_wants = amounts[cpt];
        new_gives = bases_of_position(pos, amounts[cpt]);
      }
      writeOffer({
        index: index,
        outbound_tkn: BASE,
        inbound_tkn: QUOTE,
        wants: new_wants,
        gives: new_gives,
        pivotId: pos > 0 ? ASKS[index_of_position(pos - 1)] : 0
      });
      cpt++;
      index = next_index(index);
    }
  }

  /** Recenter the order book by shifting max price down `s` positions in the book */
  /** As a consequence `s` Asks will be cancelled and `s` new Bids will be posted */
  function negative_shift(
    uint s,
    bool withBase,
    uint[] calldata amounts
  ) internal {
    require(s < NSLOTS, "Mango/shift/NegativeShiftTooLarge");
    uint index = index_of_position(NSLOTS - 1);
    current_shift -= int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    uint cpt;
    while (cpt < s) {
      // slots occupied by [Asks[index-`s` % N],..,Asks[index]] are retracted
      if (ASKS[index] != 0) {
        retractOfferInternal({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          offerId: ASKS[index],
          deprovision: false
        });
      }
      // slots are replaced by `s` Bids.
      // NB the price of Bids[index] is computed given the new position associated to `index`
      // because the shift has been updated above

      // `pos` is the offer position in the OB (not the array)
      uint pos = position_of_index(index);
      uint new_gives;
      uint new_wants;
      if (withBase) {
        // amounts in base
        new_wants = amounts[cpt];
        new_gives = quotes_of_position(pos, amounts[cpt]);
      } else {
        // amounts in quote
        new_wants = bases_of_position(pos, amounts[cpt]);
        new_gives = amounts[cpt];
      }
      writeOffer({
        index: index,
        outbound_tkn: QUOTE,
        inbound_tkn: BASE,
        wants: new_wants,
        gives: new_gives,
        pivotId: pos < NSLOTS - 1 ? BIDS[index_of_position(pos + 1)] : 0
      });
      cpt++;
      index = prev_index(index);
    }
  }

  // for reposting partial filled offers one always gives the residual (default behavior)
  // and adapts wants to the new price (if different).
  function __residualWants__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    if (order.outbound_tkn == BASE) {
      // Ask offer (wants QUOTE)
      uint index = index_of_ask[order.offerId];
      uint residual_base = __residualGives__(order); // default
      if (residual_base == 0) {
        return 0;
      }
      return quotes_of_position(position_of_index(index), residual_base);
    } else {
      // Bid order (wants BASE)
      uint index = index_of_bid[order.offerId];
      uint residual_quote = __residualGives__(order); // default
      if (residual_quote == 0) {
        return 0;
      }
      return bases_of_position(position_of_index(index), residual_quote);
    }
  }

  /** Define what to do when the AMM boundaries are reached (either when reposting a bid or a ask) */
  function __boundariesReached__(bool bid, uint offerId) internal virtual {
    if (bid) {
      emit BidAtMaxPosition(QUOTE, BASE, offerId);
    } else {
      emit AskAtMinPosition(BASE, QUOTE, offerId);
    }
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
  {
    // reposting residual of offer using override `__newWants__` and default `__newGives` for new price
    super.__posthookSuccess__(order);
    if (order.outbound_tkn == BASE) {
      // Ask Offer (`this` contract just sold some BASE @ pos)
      uint index = index_of_ask[order.offerId];
      if (index == 0) {
        // offer was posted using newOffer, not during initialization
        return;
      }
      uint pos = position_of_index(index);
      // bid for some BASE token with the received QUOTE tokens @ pos-1
      if (pos > 0) {
        updateBid({
          index: index_of_position(pos - 1),
          withBase: false, // order gave QUOTES
          reset: false, // top up old value with received amount
          amount: order.gives, // in QUOTES
          pivotId: 0
        });
      } else {
        // Ask cannot be at Pmin unless a shift has eliminated all bids
        emit PosthookFail(
          order.outbound_tkn,
          order.inbound_tkn,
          order.offerId,
          "Mango/posthook/BuyingOutOfPriceRange"
        );
        return;
      }
    } else {
      // Bid offer (`this` contract just bought some BASE)
      uint index = index_of_bid[order.offerId];
      if (index == 0) {
        // offer was posted using newOffer, not during initialization
        return;
      }
      uint pos = position_of_index(index);
      // ask for some QUOTE tokens in exchange of the received BASE tokens @ pos+1
      if (pos < NSLOTS - 1) {
        updateAsk({
          index: index_of_position(pos + 1),
          withBase: true, // order gave BASE
          reset: false, // top up old value with received amount
          amount: order.gives, // in BASE
          pivotId: 0
        });
      } else {
        // Take profit
        emit PosthookFail(
          order.outbound_tkn,
          order.inbound_tkn,
          order.offerId,
          "Mango/posthook/SellingOutOfPriceRange"
        );
        return;
      }
    }
  }

  function updateBid(
    uint index,
    bool withBase,
    bool reset,
    uint amount,
    uint pivotId
  ) internal {
    // outbound : QUOTE, inbound: BASE
    P.Offer.t offer = MGV.offers(QUOTE, BASE, BIDS[index]);

    uint position = position_of_index(index);
    uint new_wants;
    uint new_gives;
    if (withBase) {
      // amount: BASE
      new_wants = reset ? amount : amount + offer.wants();
      new_gives = quotes_of_position(position, new_wants);
    } else {
      // amount: QUOTE
      new_gives = reset ? amount : amount + offer.gives();
      new_wants = bases_of_position(position, new_gives);
    }
    uint pivot;
    if (offer.gives() == 0) {
      // offer was not live
      if (pivotId != 0) {
        pivot = pivotId;
      } else {
        if (position > 0) {
          pivot = BIDS[index_of_position(position - 1)]; // if this offer is no longer in the book will start form best
        } else {
          pivot = offer.prev(); // trying previous offer on Mangrove as a pivot
        }
      }
    } else {
      // offer is live, so reusing its id for pivot
      pivot = BIDS[index];
    }
    writeOffer({
      index: index,
      outbound_tkn: QUOTE,
      inbound_tkn: BASE,
      wants: new_wants,
      gives: new_gives,
      pivotId: pivot
    });
  }

  function updateAsk(
    uint index,
    bool withBase,
    bool reset,
    uint amount,
    uint pivotId
  ) internal {
    // outbound : BASE, inbound: QUOTE
    P.Offer.t offer = MGV.offers(BASE, QUOTE, ASKS[index]);
    uint position = position_of_index(index);
    uint new_gives;
    uint new_wants;
    if (withBase) {
      // amount: BASE
      new_gives = reset ? amount : amount + offer.gives(); // in BASE
      new_wants = quotes_of_position(position, new_gives);
    } else {
      new_wants = reset ? amount : amount + offer.wants(); // in QUOTES
      new_gives = bases_of_position(position, new_wants);
    }

    uint pivot;
    if (offer.gives() == 0) {
      // offer was not live
      if (pivotId != 0) {
        pivot = pivotId;
      } else {
        if (position > 0) {
          pivot = ASKS[index_of_position(position - 1)]; // if this offer is no longer in the book will start form best
        } else {
          pivot = offer.prev(); // trying previous offer on Mangrove as a pivot
        }
      }
    } else {
      // offer is live, so reusing its id for pivot
      pivot = ASKS[index];
    }
    writeOffer({
      index: index,
      outbound_tkn: BASE,
      inbound_tkn: QUOTE,
      wants: new_wants,
      gives: new_gives,
      pivotId: pivot
    });
  }
}
