// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, MgvStructs, AbstractRouter} from "./abstract/CoreKandel.sol";
import {OfferType} from "./abstract/Trade.sol";
import {HasIndexedOffers} from "./abstract/HasIndexedOffers.sol";

contract Kandel is CoreKandel {
  constructor(
    HasIndexedOffers.MangroveWithBaseQuote memory mangroveWithBaseQuote,
    uint gasreq,
    uint gasprice,
    address owner
  ) CoreKandel(mangroveWithBaseQuote, gasreq, gasprice, owner) {
    // since we won't add a router later, we can activate the strat now
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(gasreq);
  }

  function reserveBalance(IERC20 token) public view override returns (uint) {
    return token.balanceOf(address(this));
  }

  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) public override {
    _depositFunds(tokens, amounts);
  }

  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient)
    public
    override
    onlyAdmin
  {
    _withdrawFunds(tokens, amounts, recipient);
  }

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return pending_ the pending amount
  function pending(OfferType ba) external view override returns (int pending_) {
    IERC20 token = outboundOfOfferType(ba);
    pending_ = int(reserveBalance(token)) - int(offeredVolume(ba));
  }
}
