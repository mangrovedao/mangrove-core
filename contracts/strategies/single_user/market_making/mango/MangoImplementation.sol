// SPDX-License-Identifier:	BSD-2-Clause

// MangoImplementation.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "./MangoStorage.sol";
import "../../abstract/Persistent.sol";
import "mgv_src/strategies/utils/TransferLib.sol";

//import "../routers/AbstractRouter.sol";

/** Discrete automated market making strat */
/** This AMM is headless (no price model) and market makes on `NSLOTS` price ranges*/
/** current `Pmin` is the price of an offer at position `0`, current `Pmax` is the price of an offer at position `NSLOTS-1`*/
/** Initially `Pmin = P(0) = QUOTE_0/BASE_0` and the general term is P(i) = __quote_progression__(i)/BASE_0 */
/** NB `__quote_progression__` is a hook that defines how price increases with positions and is by default an arithmetic progression, i.e __quote_progression__(i) = QUOTE_0 + `delta`*i */
/** When one of its offer is matched on Mangrove, the headless strat does the following: */
/** Each time this strat receives b `BASE` tokens (bid was taken) at price position i, it increases the offered (`BASE`) volume of the ask at position i+1 of 'b'*/
/** Each time this strat receives q `QUOTE` tokens (ask was taken) at price position i, it increases the offered (`QUOTE`) volume of the bid at position i-1 of 'q'*/
/** In case of a partial fill of an offer at position i, the offer residual is reposted (see `Persistent` strat class)*/

contract MangoImplementation is Persistent {
  event BidAtMaxPosition();
  // emitted when strat has reached max amount of Asks and needs rebalancing (should shift of x<0 positions in order to have ask prices that are better for the taker)
  event AskAtMinPosition();

  modifier delegated() {
    require(address(this) == PROXY, "MangoImplementation/invalidCall");
    _;
  }

  // total number of Asks (resp. Bids)
  uint immutable NSLOTS;
  // initial min price given by `QUOTE_0/BASE_0`
  uint96 immutable BASE_0;
  uint96 immutable QUOTE_0;
  // Market on which Mango will be acting
  IERC20 immutable BASE;
  IERC20 immutable QUOTE;

  address immutable PROXY;

  constructor(
    IMangrove mgv,
    IERC20 base,
    IERC20 quote,
    uint96 base_0,
    uint96 quote_0,
    uint nslots
  )
    Persistent(
      mgv,
      0,
      AbstractRouter(address(0)) /* router*/
    )
  {
    // setting immutable fields to match those of `Mango`
    BASE = base;
    QUOTE = quote;
    NSLOTS = nslots;
    BASE_0 = base_0;
    QUOTE_0 = quote_0;
    PROXY = msg.sender;
  }

  // populate mangrove order book with bids or/and asks in the price range R = [`from`, `to`[
  // tokenAmounts are always expressed `gives`units, i.e in BASE when asking and in QUOTE when bidding
  function $initialize(
    bool reset,
    uint lastBidPosition, // if `lastBidPosition` is in R, then all offers before `lastBidPosition` (included) will be bids, offers strictly after will be asks.
    uint from, // first price position to be populated
    uint to, // last price position to be populated
    uint[][2] calldata pivotIds, // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
    uint[] calldata tokenAmounts // `tokenAmounts[i]` is the amount of `BASE` or `QUOTE` tokens (dePENDING on `withBase` flag) that is used to fixed one parameter of the price at position `from+i`.
  ) external delegated {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    // making sure a router has been defined between deployment and initialization
    require(address(router()) != address(0), "Mango/initialize/0xRouter");
    /** Initializing Asks and Bids */
    /** NB we assume Mangrove is already provisioned for posting NSLOTS asks and NSLOTS bids*/
    /** NB cannot post newOffer with infinite gasreq since fallback ofr_gasreq is not defined yet (and default is likely wrong) */
    require(to > from, "Mango/initialize/invalidSlice");
    require(
      tokenAmounts.length == NSLOTS &&
        pivotIds.length == 2 &&
        pivotIds[0].length == NSLOTS &&
        pivotIds[1].length == NSLOTS,
      "Mango/initialize/invalidArrayLength"
    );
    require(lastBidPosition < NSLOTS - 1, "Mango/initialize/NoSlotForAsks"); // bidding => slice doesn't fill the book
    uint pos;
    for (pos = from; pos < to; pos++) {
      // if shift is not 0, must convert
      uint i = index_of_position(pos);

      if (pos <= lastBidPosition) {
        uint bidPivot = pivotIds[0][pos];
        bidPivot = bidPivot > 0
          ? bidPivot // taking pivot from the user
          : pos > 0
          ? mStr.bids[index_of_position(pos - 1)]
          : 0; // otherwise getting last inserted offer as pivot
        updateBid({
          index: i,
          reset: reset, // overwrites old value
          amount: tokenAmounts[pos],
          pivotId: bidPivot
        });
        if (mStr.asks[i] > 0) {
          // if an ASK is also positioned, remove it to prevent spread crossing
          // (should not happen if this is the first initialization of the strat)
          retractOffer(BASE, QUOTE, mStr.asks[i], false);
        }
      } else {
        uint askPivot = pivotIds[1][pos];
        askPivot = askPivot > 0
          ? askPivot // taking pivot from the user
          : pos > 0
          ? mStr.asks[index_of_position(pos - 1)]
          : 0; // otherwise getting last inserted offer as pivot
        updateAsk({
          index: i,
          reset: reset,
          amount: tokenAmounts[pos],
          pivotId: askPivot
        });
        if (mStr.bids[i] > 0) {
          // if a BID is also positioned, remove it to prevent spread crossing
          // (should not happen if this is the first initialization of the strat)
          retractOffer(QUOTE, BASE, mStr.bids[i], false);
        }
      }
    }
  }

  // with ba=0:bids only, ba=1: asks only ba>1 all
  function $retractOffers(
    uint ba,
    uint from,
    uint to
  ) external delegated returns (uint collected) {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    for (uint i = from; i < to; i++) {
      if (ba > 0) {
        // asks or bids+asks
        collected += mStr.asks[i] > 0
          ? retractOffer(BASE, QUOTE, mStr.asks[i], true)
          : 0;
      }
      if (ba == 0 || ba > 1) {
        // bids or bids + asks
        collected += mStr.bids[i] > 0
          ? retractOffer(QUOTE, BASE, mStr.bids[i], true)
          : 0;
      }
    }
  }

  /** Shift the price (induced by quote amount) of n slots down or up */
  /** price at position i will be shifted (up or down dePENDING on the sign of `shift`) */
  /** New positions 0<= i < s are initialized with amount[i] in base tokens if `withBase`. In quote tokens otherwise*/
  function $set_shift(
    int s,
    bool withBase,
    uint[] calldata amounts
  ) external delegated {
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

  // return Mango offer Ids on Mangrove. If `liveOnly` will only return offer Ids that are live (0 otherwise).
  function $get_offers(bool liveOnly)
    external
    view
    returns (uint[][2] memory offers)
  {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    offers[0] = new uint[](NSLOTS);
    offers[1] = new uint[](NSLOTS);
    for (uint i = 0; i < NSLOTS; i++) {
      uint askId = mStr.asks[index_of_position(i)];
      uint bidId = mStr.bids[index_of_position(i)];

      offers[0][i] = (MGV.offers($(QUOTE), $(BASE), bidId).gives() > 0 ||
        !liveOnly)
        ? mStr.bids[index_of_position(i)]
        : 0;
      offers[1][i] = (MGV.offers($(BASE), $(QUOTE), askId).gives() > 0 ||
        !liveOnly)
        ? mStr.asks[index_of_position(i)]
        : 0;
    }
  }

  // posts or updates ask at position of `index`
  // returns the amount of `BASE` tokens that failed to be published at that position
  // `writeOffer` is split into `writeAsk` and `writeBid` to avoid stack too deep exception
  function writeAsk(
    uint index,
    uint wants,
    uint gives,
    uint pivotId
  ) internal returns (uint) {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    if (mStr.asks[index] == 0) {
      // offer slot not initialized yet
      try
        MGV.newOffer({
          outbound_tkn: $(BASE),
          inbound_tkn: $(QUOTE),
          wants: wants,
          gives: gives,
          gasreq: ofr_gasreq(),
          gasprice: 0,
          pivotId: pivotId
        })
      returns (uint offerId) {
        mStr.asks[index] = offerId;
        mStr.index_of_ask[mStr.asks[index]] = index;
        return 0;
      } catch (bytes memory reason) {
        // `newOffer` can fail when Mango is underprovisioned or if `offer.gives` is below density
        if (keccak256(reason) == keccak256("mgv/insufficientProvision")) {
          emit LogIncident(MGV, BASE, QUOTE, 0, "Mango/newAsk/outOfProvision");
        }
        return gives;
      }
    } else {
      try
        MGV.updateOffer({
          outbound_tkn: $(BASE),
          inbound_tkn: $(QUOTE),
          wants: wants,
          gives: gives,
          gasreq: ofr_gasreq(),
          gasprice: 0,
          pivotId: pivotId,
          offerId: mStr.asks[index]
        })
      {
        // updateOffer succeeded
        return 0;
      } catch (bytes memory reason) {
        // update offer might fail because residual is below density (this is OK)
        // it may also fail because there is not enough provision on Mangrove (this is Not OK so we log)
        if (keccak256(reason) == keccak256("mgv/insufficientProvision")) {
          emit LogIncident(
            MGV,
            BASE,
            QUOTE,
            mStr.asks[index],
            "Mango/updateAsk/outOfProvision"
          );
        }
        // updateOffer failed but `offer` might still be live (i.e with `offer.gives>0`)
        uint oldGives = MGV.offers($(BASE), $(QUOTE), mStr.asks[index]).gives();
        // if not during initialize we necessarily have gives > oldGives
        // otherwise we are trying to reset the offer and oldGives is irrelevant
        return (gives > oldGives) ? gives - oldGives : gives;
      }
    }
  }

  function writeBid(
    uint index,
    uint wants,
    uint gives,
    uint pivotId
  ) internal returns (uint) {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    if (mStr.bids[index] == 0) {
      try
        MGV.newOffer({
          outbound_tkn: $(QUOTE),
          inbound_tkn: $(BASE),
          wants: wants,
          gives: gives,
          gasreq: ofr_gasreq(),
          gasprice: 0,
          pivotId: pivotId
        })
      returns (uint offerId) {
        mStr.bids[index] = offerId;
        mStr.index_of_bid[mStr.bids[index]] = index;
        return 0;
      } catch (bytes memory reason) {
        if (keccak256(reason) == keccak256("mgv/insufficientProvision")) {
          emit LogIncident(MGV, QUOTE, BASE, 0, "Mango/newBid/outOfProvision");
        }
        return gives;
      }
    } else {
      try
        MGV.updateOffer({
          outbound_tkn: $(QUOTE),
          inbound_tkn: $(BASE),
          wants: wants,
          gives: gives,
          gasreq: ofr_gasreq(),
          gasprice: 0,
          pivotId: pivotId,
          offerId: mStr.bids[index]
        })
      {
        return 0;
      } catch (bytes memory reason) {
        if (keccak256(reason) == keccak256("mgv/insufficientProvision")) {
          emit LogIncident(
            MGV,
            QUOTE,
            BASE,
            mStr.bids[index],
            "Mango/writeBid/updateOfferFail"
          );
        }
        // updateOffer failed but `offer` might still be live (i.e with `offer.gives>0`)
        uint oldGives = MGV.offers($(QUOTE), $(BASE), mStr.bids[index]).gives();
        // if not during initialize we necessarily have gives > oldGives
        // otherwise we are trying to reset the offer and oldGives is irrelevant
        return (gives > oldGives) ? gives - oldGives : gives;
      }
    }
  }

  /** Writes (creates or updates) a maker offer on Mangrove's order book*/
  function safeWriteOffer(
    uint index,
    IERC20 outbound_tkn,
    uint wants,
    uint gives,
    bool withPending, // whether `gives` amount includes current pending tokens
    uint pivotId
  ) internal {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    if (outbound_tkn == BASE) {
      uint not_published = writeAsk(index, wants, gives, pivotId);
      if (not_published > 0) {
        // Ask could not be written on the book (density or provision issue)
        mStr.pending_base = withPending
          ? not_published
          : (mStr.pending_base + not_published);
      } else {
        if (withPending) {
          mStr.pending_base = 0;
        }
      }
    } else {
      uint not_published = writeBid(index, wants, gives, pivotId);
      if (not_published > 0) {
        mStr.pending_quote = withPending
          ? not_published
          : (mStr.pending_quote + not_published);
      } else {
        if (withPending) {
          mStr.pending_quote = 0;
        }
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

  /** Minimal amount of quotes for the general term of the `quote_progression` */
  /** If min price was not shifted this is just `QUOTE_0` */
  /** In general this is QUOTE_0 + shift*delta */
  function quote_min() internal view returns (uint) {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    int qm = int(uint(QUOTE_0)) + mStr.shift * int(mStr.delta);
    require(qm > 0, "Mango/quote_min/ShiftUnderflow");
    return (uint(qm));
  }

  /** Returns the price position in the order book of the offer associated to this index `i` */
  function position_of_index(uint i) internal view returns (uint) {
    // position(i) = (i+shift) % N
    return modulo(int(i) - MangoStorage.get_storage().shift, NSLOTS);
  }

  /** Returns the index in the ring of offers at which the offer Id at position `p` in the book is stored */
  function index_of_position(uint p) internal view returns (uint) {
    return modulo(int(p) + MangoStorage.get_storage().shift, NSLOTS);
  }

  /**Next index in the ring of offers */
  function next_index(uint i) internal view returns (uint) {
    return (i + 1) % NSLOTS;
  }

  /**Previous index in the ring of offers */
  function prev_index(uint i) internal view returns (uint) {
    return i > 0 ? i - 1 : NSLOTS - 1;
  }

  /** Function that determines the amount of quotes that are offered at position i of the OB dePENDING on initial_price and paramater delta*/
  /** Here the default is an arithmetic progression */
  function quote_progression(uint position) internal view returns (uint) {
    return
      MangoStorage.quote_price_jumps(
        MangoStorage.get_storage().delta,
        position,
        quote_min()
      );
  }

  /** Returns the quantity of quote tokens for an offer at position `p` given an amount of Base tokens (eq. 2)*/
  function quotes_of_position(uint p, uint base_amount)
    internal
    view
    returns (uint)
  {
    return (quote_progression(p) * base_amount) / BASE_0;
  }

  /** Returns the quantity of base tokens for an offer at position `p` given an amount of quote tokens (eq. 3)*/
  function bases_of_position(uint p, uint quote_amount)
    internal
    view
    returns (uint)
  {
    return (quote_amount * BASE_0) / quote_progression(p);
  }

  /** Recenter the order book by shifting min price up `s` positions in the book */
  /** As a consequence `s` Bids will be cancelled and `s` new asks will be posted */
  function positive_shift(
    uint s,
    bool withBase,
    uint[] calldata amounts
  ) internal {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    require(s < NSLOTS, "Mango/shift/positiveShiftTooLarge");
    uint index = index_of_position(0);
    mStr.shift += int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    uint cpt = 0;
    while (cpt < s) {
      // slots occupied by [Bids[index],..,Bids[index+`s` % N]] are retracted
      if (mStr.bids[index] != 0) {
        retractOffer({
          outbound_tkn: QUOTE,
          inbound_tkn: BASE,
          offerId: mStr.bids[index],
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
      safeWriteOffer({
        index: index,
        outbound_tkn: BASE,
        wants: new_wants,
        gives: new_gives,
        withPending: false, // don't add pending liqudity in new offers (they are far from mid price)
        pivotId: pos > 0 ? mStr.asks[index_of_position(pos - 1)] : 0
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
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    require(s < NSLOTS, "Mango/shift/NegativeShiftTooLarge");
    uint index = index_of_position(NSLOTS - 1);
    mStr.shift -= int(s); // updating new shift
    // Warning: from now on position_of_index reflects the new shift
    // One must progress relative to index when retracting offers
    uint cpt;
    while (cpt < s) {
      // slots occupied by [Asks[index-`s` % N],..,Asks[index]] are retracted
      if (mStr.asks[index] != 0) {
        retractOffer({
          outbound_tkn: BASE,
          inbound_tkn: QUOTE,
          offerId: mStr.asks[index],
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
      safeWriteOffer({
        index: index,
        outbound_tkn: QUOTE,
        wants: new_wants,
        gives: new_gives,
        withPending: false,
        pivotId: pos < NSLOTS - 1 ? mStr.bids[index_of_position(pos + 1)] : 0
      });
      cpt++;
      index = prev_index(index);
    }
  }

  // residual gives is default (i.e offer.gives - order.wants) + PENDING
  // this overrides the corresponding function in `Persistent`
  function __residualGives__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    if (order.outbound_tkn == $(BASE)) {
      // Ask offer
      return super.__residualGives__(order) + mStr.pending_base;
    } else {
      // Bid offer
      return super.__residualGives__(order) + mStr.pending_quote;
    }
  }

  // for reposting partial filled offers one always gives the residual (default behavior)
  // and adapts wants to the new price (if different).
  // this overrides the corresponding function in `Persistent`
  function __residualWants__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    if (order.outbound_tkn == address(BASE)) {
      // Ask offer (wants QUOTE)
      uint index = mStr.index_of_ask[order.offerId];
      uint residual_base = __residualGives__(order); // default
      if (residual_base == 0) {
        return 0;
      }
      return quotes_of_position(position_of_index(index), residual_base);
    } else {
      // Bid order (wants BASE)
      uint index = mStr.index_of_bid[order.offerId];
      uint residual_quote = __residualGives__(order); // default
      if (residual_quote == 0) {
        return 0;
      }
      return bases_of_position(position_of_index(index), residual_quote);
    }
  }

  // TODO add LogIncident and Bid/AskatMax logs
  function $posthookSuccess(ML.SingleOrder calldata order)
    external
    delegated
    returns (bool success)
  {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();

    // manage source of BASE and QUOTE whose reserve may have changed during the trade execution
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = BASE;
    tokens[1] = QUOTE;

    // reposting residual of offer using override `__newWants__` and `__newGives__` for new price
    if (order.outbound_tkn == $(BASE)) {
      // order is an Ask
      //// Reposting Offer residual
      if (!super.__posthookSuccess__(order)) {
        // residual could not be reposted --either below density or Mango went out of provision on Mangrove
        mStr.pending_base = __residualGives__(order); // this includes previous `pending_base`
      } else {
        mStr.pending_base = 0;
      }
      //// Posting dual bid offer
      uint index = mStr.index_of_ask[order.offerId];

      uint pos = position_of_index(index);
      // bid for some BASE token with the received QUOTE tokens @ pos-1
      if (pos > 0) {
        // updateBid will include PENDING_QUOTES if any
        updateBid({
          index: index_of_position(pos - 1),
          reset: false, // top up old value with received amount
          amount: order.gives, // in QUOTES
          pivotId: 0
        });
        if (pos - 1 <= mStr.min_buffer) {
          emit BidAtMaxPosition();
        }
        return true;
      } else {
        // Ask cannot be at Pmin unless a shift has eliminated all bids
        revert("Mango/BidOutOfRange");
      }
    } else {
      // Bid offer (`this` contract just bought some BASE)

      if (!super.__posthookSuccess__(order)) {
        // residual could not be reposted --either below density or Mango went out of provision on Mangrove
        mStr.pending_quote = __residualGives__(order); // this includes previous `PENDING_QUOTE`
      } else {
        mStr.pending_quote = 0;
      }

      uint index = mStr.index_of_bid[order.offerId];
      // offer was not posted using newOffer
      uint pos = position_of_index(index);
      // ask for some QUOTE tokens in exchange of the received BASE tokens @ pos+1
      if (pos < NSLOTS - 1) {
        // updateAsk will include mStr.pending_baseS if any
        updateAsk({
          index: index_of_position(pos + 1),
          reset: false, // top up old value with received amount
          amount: order.gives, // in BASE
          pivotId: 0
        });
        if (pos + 1 >= NSLOTS - mStr.min_buffer) {
          emit AskAtMinPosition();
        }
        return true;
      } else {
        revert("Mango/AskOutOfRange");
      }
    }
  }

  function updateBid(
    uint index,
    bool reset, // whether this call is part of an `initialize` procedure
    uint amount, // in QUOTE tokens
    uint pivotId
  ) internal {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    // outbound : QUOTE, inbound: BASE
    P.Offer.t offer = MGV.offers($(QUOTE), $(BASE), mStr.bids[index]);

    uint position = position_of_index(index);

    uint new_gives = reset
      ? amount
      : (amount + offer.gives() + mStr.pending_quote);
    uint new_wants = bases_of_position(position, new_gives);

    uint pivot;
    if (offer.gives() == 0) {
      // offer was not live
      if (pivotId != 0) {
        pivot = pivotId;
      } else {
        if (position > 0) {
          pivot = mStr.bids[index_of_position(position - 1)]; // if this offer is no longer in the book will start form best
        } else {
          pivot = offer.prev(); // trying previous offer on Mangrove as a pivot
        }
      }
    } else {
      // offer is live, so reusing its id for pivot
      pivot = mStr.bids[index];
    }
    safeWriteOffer({
      index: index,
      outbound_tkn: QUOTE,
      wants: new_wants,
      gives: new_gives,
      withPending: !reset,
      pivotId: pivot
    });
  }

  function updateAsk(
    uint index,
    bool reset, // whether this call is part of an `initialize` procedure
    uint amount, // in BASE tokens
    uint pivotId
  ) internal {
    MangoStorage.Layout storage mStr = MangoStorage.get_storage();
    // outbound : BASE, inbound: QUOTE
    P.Offer.t offer = MGV.offers($(BASE), $(QUOTE), mStr.asks[index]);
    uint position = position_of_index(index);

    uint new_gives = reset
      ? amount
      : (amount + offer.gives() + mStr.pending_base); // in BASE
    uint new_wants = quotes_of_position(position, new_gives);

    uint pivot;
    if (offer.gives() == 0) {
      // offer was not live
      if (pivotId != 0) {
        pivot = pivotId;
      } else {
        if (position > 0) {
          pivot = mStr.asks[index_of_position(position - 1)]; // if this offer is no longer in the book will start form best
        } else {
          pivot = offer.prev(); // trying previous offer on Mangrove as a pivot
        }
      }
    } else {
      // offer is live, so reusing its id for pivot
      pivot = mStr.asks[index];
    }
    safeWriteOffer({
      index: index,
      outbound_tkn: BASE,
      wants: new_wants,
      gives: new_gives,
      withPending: !reset,
      pivotId: pivot
    });
  }
}
