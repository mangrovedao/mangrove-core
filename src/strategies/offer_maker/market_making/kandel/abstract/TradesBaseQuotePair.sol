// SPDX-License-Identifier:	BSD-2-Clause

// TradesBaseQuotePair.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvLib} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title a bid or an ask.
enum OfferType {
  Bid,
  Ask
}

///@title Interface contract for strats needing offer type to token pair mapping.
abstract contract IHasTokenPairOfOfferType {
  ///@notice turns an offer type into an (outbound, inbound) pair identifying an offer list.
  ///@param ba whether one wishes to access the offer lists where asks or bids are posted.
  function tokenPairOfOfferType(OfferType ba) internal view virtual returns (IERC20, IERC20);

  ///@notice returns the offer type of the offer list whose outbound token is given in the argument.
  ///@param outbound_tkn the outbound token of the offer list.
  function offerTypeOfOutbound(IERC20 outbound_tkn) internal view virtual returns (OfferType);
}

///@title Adds basic base/quote trading pair for bids and asks and couples it to Mangrove's gives, wants, outbound, inbound terminology.
///@dev Implements the IHasTokenPairOfOfferType interface contract.
abstract contract TradesBaseQuotePair is IHasTokenPairOfOfferType {
  ///@notice base of the market Kandel is making
  IERC20 public immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 public immutable QUOTE;

  constructor(IERC20 base, IERC20 quote) {
    BASE = base;
    QUOTE = quote;
  }

  ///@inheritdoc IHasTokenPairOfOfferType
  function tokenPairOfOfferType(OfferType ba) internal view override returns (IERC20, IERC20) {
    return ba == OfferType.Bid ? (QUOTE, BASE) : (BASE, QUOTE);
  }

  ///@inheritdoc IHasTokenPairOfOfferType
  function offerTypeOfOutbound(IERC20 outbound_tkn) internal view override returns (OfferType) {
    return outbound_tkn == BASE ? OfferType.Ask : OfferType.Bid;
  }

  ///@notice returns the outbound token for the offer type
  ///@param ba the offer type
  function outboundOfOfferType(OfferType ba) internal view returns (IERC20 token) {
    token = ba == OfferType.Ask ? BASE : QUOTE;
  }

  ///@notice returns the wants and gives for a Mangrove offer for the offer type given the base and quote amounts.
  ///@param ba the offer type
  ///@param baseAmount the amount of the base token
  ///@param quoteAmount the amount of the quote token
  function wantsGivesOfBaseQuote(OfferType ba, uint baseAmount, uint quoteAmount)
    internal
    pure
    returns (uint wants, uint gives)
  {
    if (ba == OfferType.Ask) {
      wants = quoteAmount;
      gives = baseAmount;
    } else {
      wants = baseAmount;
      gives = quoteAmount;
    }
  }

  ///@notice returns the dual offer type
  ///@param ba whether the offer is an ask or a bid
  ///@return dualBa is the dual offer type (ask for bid and conversely)
  function dual(OfferType ba) public pure returns (OfferType dualBa) {
    return OfferType((uint(ba) + 1) % 2);
  }
}
