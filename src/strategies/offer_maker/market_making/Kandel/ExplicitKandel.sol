// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs} from "./abstract/CoreKandel.sol";
import "mgv_src/strategies/utils/TransferLib.sol";
import {console} from "forge-std/console.sol";

contract ExplicitKandel is CoreKandel {
  ///@notice quote distribution: `baseOfIndex[i]` is the amount of base tokens Kandel must give or want at index i
  uint96[] _baseOfIndex;
  ///@notice quote distribution: `quoteOfIndex[i]` is the amount of quote tokens Kandel must give or want at index i
  uint96[] _quoteOfIndex;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots)
    CoreKandel(mgv, base, quote, gasreq, nslots)
  {
    _baseOfIndex = new uint96[](nslots);
    _quoteOfIndex = new uint96[](nslots);
  }

  function __reserve__(address) internal view override returns (address) {
    return address(this);
  }

  ///@notice sets the base/quote distribution that Kandel should follow using continuous slices
  ///@param from start index (included). Must be less than `to`.
  ///@param to end index (excluded). Must be less than `NSLOT`.
  ///@param slice slice[i][0/1] is the distribution of base/quote at index i.
  function setDistribution(uint from, uint to, uint[][2] calldata slice) external onlyAdmin {
    for (uint i = from; i < to; i++) {
      uint sliceIndex = i - from;
      require(uint96(slice[0][sliceIndex]) == slice[0][sliceIndex], "Kandel/baseOverflow");
      require(uint96(slice[1][sliceIndex]) == slice[1][sliceIndex], "Kandel/quoteOverflow");
      _baseOfIndex[i] = uint96(slice[0][sliceIndex]);
      _quoteOfIndex[i] = uint96(slice[1][sliceIndex]);
    }
  }

  ///@inheritdoc AbstractKandel
  function baseOfIndex(uint index) public view override mgvOrAdmin returns (uint96) {
    return _baseOfIndex[index];
  }

  ///@inheritdoc AbstractKandel
  function quoteOfIndex(uint index) public view override mgvOrAdmin returns (uint96) {
    return _quoteOfIndex[index];
  }

  function baseDist() external view onlyAdmin returns (uint96[] memory) {
    return _baseOfIndex;
  }

  function quoteDist() external view onlyAdmin returns (uint96[] memory) {
    return _quoteOfIndex;
  }

  ///@notice checks whether offer whose logic is being executed is currently the best on Mangrove (may not be true during a snipe)
  ///@param order the taker order that is being executed
  ///@dev `isBest` => `order.offer` is the best bid/ask of this strat (but the converse is not true in general).
  function _isBest(MgvLib.SingleOrder calldata order) internal view returns (bool) {
    uint lookup = MGV.offers(order.outbound_tkn, order.inbound_tkn, order.offerId).prev();
    return lookup == 0 || MGV.offers(order.outbound_tkn, order.inbound_tkn, lookup).gives() == 0;
  }

  ///@inheritdoc AbstractKandel
  function _transportLogic(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OrderType dualBa, uint dualIndex, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);

    if (index == 0) {
      emit AllAsks(MGV, BASE, QUOTE);
    }
    if (index == NSLOTS - 1) {
      emit AllBids(MGV, BASE, QUOTE);
    }
    dualIndex = dual(ba, index);
    dualBa = dual(ba);

    (MgvStructs.OfferPacked dualOffer, MgvStructs.OfferDetailPacked dualOfferDetails) = getOffer(dualBa, dualIndex);

    // can repost (at max) what the current taker order gave
    uint maxDualGives = dualOffer.gives() + order.gives;
    // what the distribution says the dual order should ask/bid
    uint shouldGive = _givesOfIndex(dualBa, dualIndex);
    uint shouldWant = _wantsOfIndex(dualBa, dualIndex);
    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);

    // letting dual offer complements taker's liquidity with pending when current offer is not sniped.
    // Adding pending to compute dual offer's volume would allow taker to drain liquidity
    // by sniping an offer far from the mid price for a low quantity, dual offer would then only be posted for a
    // proportionally low volume if not complemented with pending.
    uint pending = _isBest(order) ? getPending(dualBa) : 0;

    if (shouldGive >= maxDualGives + pending) {
      args.gives = maxDualGives + pending;
      popPending(dualBa, pending);
    } else {
      args.gives = shouldGive;
      uint leftover = (maxDualGives + pending - shouldGive);
      if (leftover > pending) {
        pushPending(dualBa, leftover - pending);
      } else {
        popPending(dualBa, pending - leftover);
      }
    }

    // note at this stage, maker's profit is `maxDualGives - args.gives`
    // those additional funds are just left on reserve, w/o being published.
    // if giving less volume than distribution, one must adapt wants to match distribution price
    args.wants = args.gives == shouldGive ? shouldWant : (maxDualGives * shouldWant) / shouldGive;
    args.fund = 0;
    args.noRevert = true;
    args.gasreq = dualOfferDetails.gasreq() == 0 ? offerGasreq() : dualOfferDetails.gasreq();
    args.gasprice = dualOfferDetails.gasprice() == 0 ? 0 : dualOfferDetails.gasprice();
    args.pivotId = dualOffer.gives() > 0 ? offerIdOfIndex(dualBa, dualIndex) : dualOffer.next();
  }

  function depositFunds(OrderType ba, uint amount) external {
    IERC20 token = ba == OrderType.Ask ? BASE : QUOTE;
    require(
      TransferLib.transferTokenFrom(token, msg.sender, address(this), amount)
        && push({token: token, amount: amount}) == amount,
      "Kandel/depositFailed"
    );
  }

  function withdrawFunds(OrderType ba, uint amount, address recipient) external onlyAdmin {
    IERC20 token = ba == OrderType.Ask ? BASE : QUOTE;
    require(
      pull({token: token, amount: amount, strict: true}) == amount
        && TransferLib.transferToken(token, recipient, amount),
      "Kandel/NotEnoughFunds"
    );
  }
}
