// SPDX-License-Identifier:	BSD-2-Clause

// KandelLib.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {
  Kandel
} from "mgv_src/strategies/offer_maker/market_making/kandel/Kandel.sol";

library KandelLib {
  struct PopulateVars {
    uint[] baseDist;
    uint[] quoteDist;
    uint[] indices;
  }

  function populateVars(
    Kandel kandel,
    uint from,
    uint to,
    uint initBase,
    uint initQuote,
    uint ratio) internal view returns (PopulateVars memory vars) {
    vars.indices = new uint[](to-from);
    vars.baseDist = new uint[](to-from);
    vars.quoteDist = new uint[](to-from);
    uint i = 0;
    for (; from < to; from++) {
      vars.indices[i] = from;
      vars.baseDist[i] = initBase;
      vars.quoteDist[i] = initQuote;
      // the ratio gives the price difference between two price points - the spread is involved when calculating the jump between a bid and its dual ask.
      initQuote = (initQuote * uint(ratio)) / (10 ** kandel.PRECISION());
      i++;
    }
  }

  ///@notice publishes bids/asks in the distribution interval `[from, to[`
  ///@param kandel the kandel instance
  ///@param from start index
  ///@param to end index
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@param kandelSize the number of price points
  ///@param ratio the rate of the geometric distribution with PRECISION decimals.
  ///@param spread the distance between a ask in the distribution and its corresponding bid.
  ///@param initBase base given/wanted at index from
  ///@param initQuote quote given/wanted at index from
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@dev This function must be called w/o changing ratio
  ///@dev `from` > 0 must imply `initQuote` >= quote amount given/wanted at index from-1
  ///@dev msg.value must be enough to provision all posted offers
  function populate(
    Kandel kandel,
    uint from,
    uint to,
    uint lastBidIndex,
    uint8 kandelSize,
    uint16 ratio,
    uint8 spread,
    uint initBase,
    uint initQuote,
    uint[] memory pivotIds,
    uint funds
  ) internal {
    PopulateVars memory vars = populateVars(kandel, from, to, initBase, initQuote, ratio);
    kandel.populate{value: funds}(vars.indices, vars.baseDist, vars.quoteDist, pivotIds, lastBidIndex, kandelSize, ratio, spread);
  }

  ///@notice publishes bids/asks in the distribution interval `[from, to[`
  ///@param kandel the kandel instance
  ///@param from start index
  ///@param to end index
  ///@param lastBidIndex the index after which offer should be an Ask
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@param initBase base given/wanted at index from
  ///@param initQuote quote given/wanted at index from
  ///@param pivotIds `pivotIds[i]` is the pivot to be used for offer at index `from+i`.
  ///@dev This function must be called w/o changing ratio
  ///@dev `from` > 0 must imply `initQuote` >= quote amount given/wanted at index from-1
  ///@dev msg.value must be enough to provision all posted offers
  function populate(
    Kandel kandel,
    uint from,
    uint to,
    uint lastBidIndex,
    uint initBase,
    uint initQuote,
    uint ratio,
    uint[] memory pivotIds
  ) internal {
    PopulateVars memory vars = populateVars(kandel, from, to, initBase, initQuote, ratio);
    kandel.populateChunk(vars.indices, vars.baseDist, vars.quoteDist, pivotIds, lastBidIndex);
  }  
}