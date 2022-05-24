// SPDX-License-Identifier:	BSD-2-Clause

// Mango.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

library MangoStorage {
  /** Strat specific events */

  struct Layout {
    uint[] asks;
    uint[] bids;
    // amount of base (resp quote) tokens that failed to be published on the Market
    uint pending_base;
    uint pending_quote;
    // offerId -> index in ASKS/BIDS maps
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
    bool paused;
    // Base and quote token treasuries
    // default is `this` for both
    address current_base_treasury;
    address current_quote_treasury;
    // address of the Mango implementation
  }

  function get_storage() internal pure returns (Layout storage st) {
    bytes32 storagePosition = keccak256("Mangrove.MangoLib.MangoStorage");
    assembly {
      st.slot := storagePosition
    }
  }
}
