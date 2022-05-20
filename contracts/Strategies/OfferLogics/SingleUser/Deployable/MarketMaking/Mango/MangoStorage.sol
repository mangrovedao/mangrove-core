// SPDX-License-Identifier:	BSD-2-Clause

// Mango.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

contract MangoStorage {
  /** Strat specific events */

  // emitted when strat has reached max amount of Bids and needs rebalancing (should shift of x>0 positions in order to have bid prices that are better for the taker)
  event BidAtMaxPosition(address quote, address base, uint offerId);

  // emitted when strat has reached max amount of Asks and needs rebalancing (should shift of x<0 positions in order to have ask prices that are better for the taker)
  event AskAtMinPosition(address quote, address base, uint offerId);

  // emitted when init function has been called and AMM becomes active
  event Initialized(uint from, uint to);

  /** Immutable fields */
  // total number of Asks (resp. Bids)
  uint16 public immutable NSLOTS;

  // initial min price given by `QUOTE_0/BASE_0`
  uint96 immutable BASE_0;
  uint96 immutable QUOTE_0;

  address public immutable BASE;
  address public immutable QUOTE;

  /** Mutable fields */
  // Asks and bids offer Ids are stored in `ASKS` and `BIDS` arrays respectively.
  uint[] ASKS;
  uint[] BIDS;

  uint PENDING_BASE;
  uint PENDING_QUOTE;

  mapping(uint => uint) index_of_bid; // bidId -> index
  mapping(uint => uint) index_of_ask; // askId -> index

  // Price shift is in number of price increments (or decrements when current_shift < 0) since deployment of the strat.
  // e.g. for arithmetic progression, `current_shift = -3` indicates that Pmin is now (`QUOTE_0` - 3*`current_delta`)/`BASE_0`
  int current_shift;

  // parameter for price progression
  // NB for arithmetic progression, price(i+1) = price(i) + current_delta/`BASE_0`
  uint current_delta; // quote increment

  // triggers `__boundariesReached__` whenever amounts of bids/asks is below `current_min_buffer`
  uint current_min_buffer;

  // puts the strat into a (cancellable) state where it reneges on all incoming taker orders.
  // NB reneged offers are removed from Mangrove's OB
  bool paused = false;

  // Base and quote token treasuries
  // default is `this` for both
  address current_base_treasury;
  address current_quote_treasury;

  constructor(
    address base,
    address quote,
    uint base_0,
    uint quote_0,
    uint nslots,
    uint delta,
    address deployer
  ) {
    // sanity check
    require(
      nslots > 0 &&
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
    current_min_buffer = 1;
    current_quote_treasury = deployer;
    current_base_treasury = deployer;
  }
}
