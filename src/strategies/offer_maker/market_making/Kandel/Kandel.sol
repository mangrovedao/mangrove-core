// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs, console} from "./abstract/CoreKandel.sol";
import "mgv_src/strategies/utils/TransferLib.sol";

contract Kandel is CoreKandel {
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint16 nslots)
    CoreKandel(mgv, base, quote, gasreq, nslots)
  {}

  function __reserve__(address) internal view override returns (address) {
    return address(this);
  }

  ///@inheritdoc AbstractKandel
  function _transportLogic(OrderType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OrderType ba_dual, SlotViewMonad memory v_dual, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    console.log("index taken:", index);

    if (index == 0) {
      emit AllAsks(MGV, BASE, QUOTE);
    }
    if (index == NSLOTS - 1) {
      emit AllBids(MGV, BASE, QUOTE);
    }
    ba_dual = dual(ba);

    console.log("will post a", ba_dual == OrderType.Ask ? "n Ask" : "Bid");
    v_dual = _fresh(better(ba_dual, index, params.spread));

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);

    // computing gives/wants for dual offer
    // At least: gives = order.gives/ratio and wants is then order.wants
    // At most: gives = order.gives and wants is adapted to match the price
    uint pending;
    (args.wants, args.gives, pending) = dualWantsGivesOfOrder(ba_dual, v_dual, order);
    pushPending(ba_dual, pending);

    console.log("dual wants:", args.wants, "dual gives", args.gives);

    args.gasprice = _offerDetail(ba_dual, v_dual).gasprice();
    args.gasreq = v_dual.offerDetail.gasreq();
    args.pivotId = v_dual.offer.gives() > 0 ? v_dual.offer.next() : 0;
    console.log("dry powder:", args.wants - order.wants);
    return (ba_dual, v_dual, args);
  }

  function depositFunds(OrderType ba, uint amount) external {
    IERC20 token = ba == OrderType.Ask ? BASE : QUOTE;
    require(
      TransferLib.transferTokenFrom(token, msg.sender, address(this), amount)
        && push({token: token, amount: amount}) == amount,
      "Kandel/depositFailed"
    );
    pushPending(ba, amount);
  }

  function withdrawFunds(OrderType ba, uint amount, address recipient) external onlyAdmin {
    IERC20 token = ba == OrderType.Ask ? BASE : QUOTE;
    // call below will throw if amount > pending
    popPending(ba, amount);
    require(
      pull({token: token, amount: amount, strict: true}) == amount
        && TransferLib.transferToken(token, recipient, amount),
      "Kandel/NotEnoughFunds"
    );
  }
}
