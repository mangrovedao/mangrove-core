// SPDX-License-Identifier:	BSD-2-Clause

// AbstractKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {Direct, IMangrove, IERC20, MgvLib} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";

abstract contract AbstractKandel {
  ///@notice signals that the price has moved above Kandel's current price range
  event AllAsks(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids(IMangrove indexed mgv, IERC20 indexed base, IERC20 indexed quote);

  ///@notice a bid or an ask
  enum OrderType {
    Bid,
    Ask
  }

  ///@notice base distribution at given index
  ///@param index of the distribution of base tokens
  ///@return amount of base tokens that Kandel should give/want at `index`
  function baseOfIndex(uint index) public view virtual returns (uint amount);

  ///@notice quote distribution at given index
  ///@param index of the distribution of quote tokens
  ///@return amount of quote tokens that Kandel should give/want at `index`
  function quoteOfIndex(uint index) public view virtual returns (uint amount);

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return dualBa the type of order implementing the transport
  ///@return dualIndex the distribution index where liquidity is transported
  ///@return args the argument for `populateIndex` specifying volume and price
  function _transportLogic(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OrderType dualBa, uint dualIndex, Direct.OfferArgs memory args);
}
