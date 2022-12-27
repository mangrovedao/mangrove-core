// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs} from "./abstract/CoreKandel.sol";
// import {console} from "forge-std/console.sol";

contract ExplicitKandel is CoreKandel {
  ///@notice quote distribution: `baseOfIndex[i]` is the amount of base tokens Kandel must give or want at index i
  uint[] baseOfIndex;
  ///@notice quote distribution: `quoteOfIndex[i]` is the amount of quote tokens Kandel must give or want at index i
  uint[] quoteOfIndex;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots)
    CoreKandel(mgv, base, quote, gasreq, nslots)
  {
    baseOfIndex = new uint[](nslots);
    quoteOfIndex = new uint[](nslots);
  }

  function __reserve__(address) internal view override returns (address) {
    return address(this);
  }

  ///@notice sets the base/quote distribution that Kandel should follow using continuous slices
  ///@param from start index (included). Must be less than `to`.
  ///@param to end index (excluded). Must be less than `NSLOT`.
  ///@param slice slice[i][0/1] is the distribution of base/quote at index i.
  /// `slice[i][0/1] = 0` is interpreted as keep old distribution
  function setDistribution(uint from, uint to, uint[][2] calldata slice) external onlyAdmin {
    for (uint i = from; i < to; i++) {
      if (slice[0][i] > 0) {
        baseOfIndex[i] = slice[0][i];
      }
      if (slice[1][i] > 0) {
        quoteOfIndex[i] = slice[1][i];
      }
    }
  }

  ///@inheritdoc AbstractKandel
  function _baseOfIndex(uint index) internal view override returns (uint) {
    return baseOfIndex[index];
  }

  ///@inheritdoc AbstractKandel
  function _quoteOfIndex(uint index) internal view override returns (uint) {
    return quoteOfIndex[index];
  }

  ///@inheritdoc AbstractKandel
  function _transportLogic(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OrderType dualBa, uint dualIndex, OfferArgs memory args)
  {
    uint index = _indexOfOfferId(ba, order.offerId);

    if (index == 0) {
      emit AllAsks(MGV, BASE, QUOTE);
    }
    if (index == NSLOTS - 1) {
      emit AllBids(MGV, BASE, QUOTE);
    }
    (dualIndex, dualBa) = ba == OrderType.Ask ? (index - 1, OrderType.Bid) : (index + 1, OrderType.Ask);
    (MgvStructs.OfferPacked dualOffer, MgvStructs.OfferDetailPacked dualOfferDetails) = getOffer(dualBa, dualIndex);

    // can repost (at max) what the current taker order gave
    uint maxDualGives = dualOffer.gives() + order.gives;

    // what the distribution says the dual order should ask/bid
    uint shouldGive = _givesOfIndex(dualBa, dualIndex);
    uint shouldWant = _wantsOfIndex(dualBa, dualIndex);

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);

    uint pending = _getPending(dualBa);
    if (shouldGive >= maxDualGives + pending) {
      if (dualBa == OrderType.Ask) {
        pendingBase = 0;
      } else {
        pendingQuote = 0;
      }
      args.gives = maxDualGives + pending;
    } else {
      // maxDualGives + pending > shouldGive
      args.gives = shouldGive;
      _setPending(dualBa, maxDualGives + pending - shouldGive);
    }

    // note at this stage, maker's profit is `maxDualGives - args.gives`
    // those additional funds are just left on reserve, w/o being published.
    // if giving less volume than distribution, one must adapt wants to match distribution price
    args.wants = args.gives == shouldGive ? shouldWant : (maxDualGives * shouldWant) / shouldGive;
    args.fund = 0;
    args.noRevert = true;
    args.gasreq = dualOfferDetails.gasreq();
    args.gasprice = dualOfferDetails.gasprice();
    args.pivotId = dualOffer.next();
  }
}
