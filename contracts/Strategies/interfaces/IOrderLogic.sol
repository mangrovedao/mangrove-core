// SPDX-License-Identifier:	BSD-2-Clause

// SwingingMarketMaker.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.0;
pragma abicoder v2;
import "./IMangrove.sol";
import "./IEIP20.sol";

interface IOrderLogic {
  struct TakerOrder {
    IEIP20 base; //identifying Mangrove market
    IEIP20 quote;
    bool partialFillNotAllowed; //revert if taker order cannot be filled and resting order failed or is not enabled
    bool selling; // whether this is a selling order (otherwise a buy order)
    uint wants; // if `selling` amount of quote tokens, otherwise amount of base tokens
    uint makerWants; // taker wants before slippage (`makerWants == wants` when `!selling`)
    uint gives; // if `selling` amount of base tokens, otherwise amount of quote tokens
    uint makerGives; // taker gives before slippage (`makerGives == gives` when `selling`)
    bool restingOrder; // whether the complement of the partial fill (if any) should be posted as a resting limit order
    uint retryNumber; // number of times filling the taker order should be retried (0 means 1 attempt).
    uint gasForMarketOrder; // gas limit per market order attempt
    uint blocksToLiveForRestingOrder; // number of blocks the resting order should be allowed to live, 0 means forever
  }

  struct TakerOrderResult {
    uint takerGot;
    uint takerGave;
    uint bounty;
    uint fee;
    uint offerId;
  }

  event OrderSummary(
    IMangrove mangrove,
    IEIP20 indexed base,
    IEIP20 indexed quote,
    address indexed taker,
    bool selling,
    uint takerGot,
    uint takerGave,
    uint penalty,
    uint restingOrderId
  );

  function expiring(
    IEIP20,
    IEIP20,
    uint
  ) external returns (uint);

  function take(TakerOrder memory)
    external
    payable
    returns (TakerOrderResult memory);
}
