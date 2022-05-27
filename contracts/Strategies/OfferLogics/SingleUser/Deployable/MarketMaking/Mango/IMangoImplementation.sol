// SPDX-License-Identifier:	BSD-2-Clause

// Mango.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "./MangoStorage.sol";
//import "./MangoImplementation.sol";
import "../../../Persistent.sol";

/** Discrete automated market making strat */
/** This AMM is headless (no price model) and market makes on `NSLOTS` price ranges*/
/** current `Pmin` is the price of an offer at position `0`, current `Pmax` is the price of an offer at position `NSLOTS-1`*/
/** Initially `Pmin = P(0) = QUOTE_0/BASE_0` and the general term is P(i) = __quote_progression__(i)/BASE_0 */
/** NB `__quote_progression__` is a hook that defines how price increases with positions and is by default an arithmetic progression, i.e __quote_progression__(i) = QUOTE_0 + `current_delta`*i */
/** When one of its offer is matched on Mangrove, the headless strat does the following: */
/** Each time this strat receives b `BASE` tokens (bid was taken) at price position i, it increases the offered (`BASE`) volume of the ask at position i+1 of 'b'*/
/** Each time this strat receives q `QUOTE` tokens (ask was taken) at price position i, it increases the offered (`QUOTE`) volume of the bid at position i-1 of 'q'*/
/** In case of a partial fill of an offer at position i, the offer residual is reposted (see `Persistent` strat class)*/

interface IMangoImplementation {
  // populate mangrove order book with bids or/and asks in the price range R = [`from`, `to`[
  // tokenAmounts are always expressed `gives`units, i.e in BASE when asking and in QUOTE when bidding
  function $initialize(
    uint lastBidPosition, // if `lastBidPosition` is in R, then all offers before `lastBidPosition` (included) will be bids, offers strictly after will be asks.
    uint from, // first price position to be populated
    uint to, // last price position to be populated
    uint[][2] calldata pivotIds, // `pivotIds[0][i]` ith pivots for bids, `pivotIds[1][i]` ith pivot for asks
    uint[] calldata tokenAmounts // `tokenAmounts[i]` is the amount of `BASE` or `QUOTE` tokens (dePENDING on `withBase` flag) that is used to fixed one parameter of the price at position `from+i`.
  ) external;

  /** Deposits received tokens into the corresponding treasury*/
  function $put(uint amount, ML.SingleOrder calldata order)
    external
    returns (uint);

  /** Fetches required tokens from the corresponding treasury*/
  function $get(uint amount, ML.SingleOrder calldata order)
    external
    returns (uint);

  // with ba=0:bids only, ba=1: asks only ba>1 all
  function $retractOffers(
    uint ba,
    uint from,
    uint to
  ) external returns (uint collected);

  /** Shift the price (induced by quote amount) of n slots down or up */
  /** price at position i will be shifted (up or down dePENDING on the sign of `shift`) */
  /** New positions 0<= i < s are initialized with amount[i] in base tokens if `withBase`. In quote tokens otherwise*/
  function $set_shift(
    int s,
    bool withBase,
    uint[] calldata amounts
  ) external;

  // return Mango offer Ids on Mangrove. If `liveOnly` will only return offer Ids that are live (0 otherwise).
  function $get_offers(bool liveOnly)
    external
    view
    returns (uint[][2] memory offers);

  function $posthookSuccess(ML.SingleOrder calldata order)
    external
    returns (bytes32 retcode);
}
