// SPDX-License-Identifier:	BSD-2-Clause

// AbstractKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";

abstract contract AbstractKandel {
  ///@notice signals that the price has moved above Kandel's current price range
  event AllAsks();
  ///@notice signals that the price has moved below Kandel's current price range
  event AllBids();

  ///@notice the compound rates have been set to `compoundRateBase` and `compoundRateQuote` which will take effect for future compounding.
  event SetCompoundRates(uint compoundRateBase, uint compoundRateQuote);

  ///@notice the gasprice has been set.
  event SetGasprice(uint16 gasprice);

  ///@notice the gasreq has been set.
  event SetGasreq(uint24 gasreq);

  // `ratio`, `compoundRateBase`, and `compoundRateQuote` have PRECISION decimals.
  // setting PRECISION higher than 4 might produce overflow in limit cases.
  uint8 public constant PRECISION = 4;

  function pending(OfferType ba) external view virtual returns (int pending_);
  function reserveBalance(IERC20 token) public view virtual returns (uint);
  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) public virtual;

  /// @dev it is up to the caller to make sure there are still enough funds for live offers.
  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient) public virtual;
}
