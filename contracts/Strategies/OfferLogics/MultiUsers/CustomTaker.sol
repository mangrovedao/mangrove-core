// SPDX-License-Identifier:	BSD-2-Clause

// Persistent.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "./Persistent.sol";

abstract contract CustomTaker is MultiUserPersistent {
  // `blockToLive[token1][token2][offerId]` gives block number beyond which the offer should renege on trade.
  mapping(address => mapping(address => mapping(uint => uint))) expiring;

  struct TakerOrder {
    address base; //identifying Mangrove market
    address quote;
    bool partialFillNotAllowed; //revert if taker order cannot be filled
    bool selling; // whether this is a selling order (otherwise a buy order)
    uint wants;
    uint gives;
    bool restingOrder; // whether the complement of the partial fill (if any) should be posted as a resting limit order
    uint retryNumber; // number of times filling the taker order should be retried (0 means 1 attempt).
    uint blocksToLiveForRestingOrder; // number of blocks the resting order should be allowed to live, 0 means for ever
    uint pivotId; // computed pivot for resting order
  }

  function __lastLook__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    uint exp = expiring[order.outbound_tkn][order.inbound_tkn][order.offerId];
    return (exp == 0 || block.number <= exp);
  }

  // `this` contract MUST have approved Mangrove for inbound token transfer
  // `msg.sender` MUST have approved `this` contract for at least the same amount
  // provision for posting a resting order should be sent when calling this function
  function take(TakerOrder calldata tko)
    external
    payable
    returns (
      uint takerGot,
      uint takerGave,
      uint bounty,
      uint offerId
    )
  {
    require(msg.sender != address(this), "CustomTaker/noReentrancy");

    (address out, address inb) = tko.selling
      ? (tko.quote, tko.base)
      : (tko.base, tko.quote);
    require(
      IEIP20(inb).transferFrom(msg.sender, address(this), tko.gives),
      "CustomTaker/transferFailed"
    );

    for (uint i = 0; i < tko.retryNumber; i++) {
      (uint takerGot_, uint takerGave_, uint bounty_) = MGV.marketOrder({
        outbound_tkn: out, // expecting quote (outbound) when selling
        inbound_tkn: inb,
        takerWants: tko.wants,
        takerGives: tko.gives,
        fillWants: tko.selling ? false : true // only buy order should try to fill takerWants
      });
      takerGot += takerGot_;
      takerGave += takerGave_;
      bounty += bounty_;
      if (takerGot_ == 0) {
        break;
      }
    }
    if (tko.selling && tko.partialFillNotAllowed) {
      require(takerGave == tko.gives, "CustomTaker/noPartialFill");
    }
    if (tko.selling && tko.partialFillNotAllowed) {
      require(takerGot == tko.wants, "CustomTaker/noPartialFill");
    }
    if (bounty > 0) {
      (bool noRevert, ) = msg.sender.call{value: bounty}("");
      require(noRevert, "CustomTaker/transferBountyFailed");
    }
    // resting limit order for the residual of the taker order
    // tko.wants / tko.gives = (tko.wants - totalGot) / new_gives
    // hence new_gives = (tko.wants - totalGot) * tko.gives / tko.wants
    if (tko.restingOrder) {
      uint offerId = newOfferInternal({
        outbound_tkn: inb,
        inbound_tkn: out,
        wants: tko.wants - takerGot,
        gives: ((tko.wants - takerGot) * tko.gives) / tko.wants,
        gasreq: OFR_GASREQ,
        gasprice: 0,
        pivotId: tko.pivotId,
        caller: msg.sender,
        provision: msg.value
      });
      if (tko.blocksToLiveForRestingOrder > 0) {
        expiring[inb][out][offerId] =
          block.number +
          tko.blocksToLiveForRestingOrder;
      }
    }
  }
}
