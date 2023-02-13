// SPDX-License-Identifier:	BSD-2-Clause

// KandelLib.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, OfferType} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/CoreKandel.sol";
import {GeometricKandel} from "mgv_src/strategies/offer_maker/market_making/kandel/abstract/GeometricKandel.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

library KandelLib {
  function calculateDistribution(uint from, uint to, uint initBase, uint initQuote, uint ratio, uint precision)
    internal
    pure
    returns (CoreKandel.Distribution memory vars, uint lastQuote)
  {
    vars.indices = new uint[](to-from);
    vars.baseDist = new uint[](to-from);
    vars.quoteDist = new uint[](to-from);
    uint i = 0;
    for (; from < to; ++from) {
      vars.indices[i] = from;
      vars.baseDist[i] = initBase;
      vars.quoteDist[i] = initQuote;
      // the ratio gives the price difference between two price points - the spread is involved when calculating the jump between a bid and its dual ask.
      initQuote = (initQuote * uint(ratio)) / (10 ** precision);
      ++i;
    }
    return (vars, initQuote);
  }

  /// @notice should be invoked as an rpc call or via snapshot-revert - populates and returns pivots and amounts.
  function estimatePivotsAndRequiredAmount(
    CoreKandel.Distribution memory distribution,
    GeometricKandel kandel,
    uint firstAskIndex,
    GeometricKandel.Params memory params,
    uint funds
  ) internal returns (uint[] memory pivotIds, uint baseAmountRequired, uint quoteAmountRequired) {
    pivotIds = new uint[](distribution.indices.length);
    kandel.populate{value: funds}(
      distribution, pivotIds, firstAskIndex, params, new IERC20[](0), new uint[](0)
    );
    for (uint i = 0; i < pivotIds.length; ++i) {
      uint index = distribution.indices[i];
      OfferType ba = index < firstAskIndex ? OfferType.Bid : OfferType.Ask;
      MgvStructs.OfferPacked offer = kandel.getOffer(ba, index);
      pivotIds[i] = offer.next();
      if (ba == OfferType.Bid) {
        quoteAmountRequired += offer.gives();
      } else {
        baseAmountRequired += offer.gives();
      }
    }
  }
}
