// SPDX-License-Identifier:	BSD-2-Clause

// Kandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs} from "./abstract/CoreKandel.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

contract Kandel is CoreKandel {
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice)
    CoreKandel(mgv, base, quote, gasreq, gasprice)
  {}

  function __reserve__(address) internal view override returns (address) {
    AbstractRouter router_ = router();
    return router_ == NO_ROUTER ? address(this) : address(router_);
  }

  ///@inheritdoc AbstractKandel
  function _transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OfferType ba_dual, SlotViewMonad memory v_dual, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory params_ = params;

    if (index == 0) {
      emit AllAsks();
    }
    if (index == params_.length - 1) {
      emit AllBids();
    }
    ba_dual = dual(ba);

    v_dual = _fresh(better(ba_dual, index, params_.spread, params_.length));

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);

    // computing gives/wants for dual offer
    // At least: gives = order.gives/ratio and wants is then order.wants
    // At most: gives = order.gives and wants is adapted to match the price
    (args.wants, args.gives) = dualWantsGivesOfOffer(ba_dual, v_dual, order, params_);
    args.gasprice = _offerDetail(ba_dual, v_dual).gasprice();
    args.gasreq = v_dual.offerDetail.gasreq() == 0 ? offerGasreq() : v_dual.offerDetail.gasreq();
    args.pivotId = v_dual.offer.gives() > 0 ? v_dual.offer.next() : 0;
    return (ba_dual, v_dual, args);
  }

  function depositFunds(OfferType ba, uint amount) external {
    IERC20 token = outboundOfOfferType(ba);
    require(
      TransferLib.transferTokenFrom(token, msg.sender, address(this), amount)
        && push({token: token, amount: amount}) == amount,
      "Kandel/depositFailed"
    );
  }

  /// @notice withdraw `amount` of funds from base (ask) or quote (bid) to `recipient`.
  /// @param ba the offer type.
  /// @param amount to withdraw.
  /// @param recipient who receives the tokens.
  /// @dev it is up to the caller to make sure there are still enough funds for live offers.
  function withdrawFunds(OfferType ba, uint amount, address recipient) external onlyAdmin {
    IERC20 token = outboundOfOfferType(ba);
    require(
      pull({token: token, amount: amount, strict: true}) == amount
        && TransferLib.transferToken(token, recipient, amount),
      "Kandel/NotEnoughFunds"
    );
  }

  /// @notice gets the total gives of all offers of the offer type
  /// @param ba offer type.
  function offeredVolume(OfferType ba) public view returns (uint volume_) {
    for (uint index = 0; index < params.length; index++) {
      (MgvStructs.OfferPacked offer,) = getOffer(ba, index);
      volume_ += offer.gives();
    }
  }

  function reserveBalance(IERC20 token, address reserve_) private view returns (uint) {
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      return token.balanceOf(reserve_);
    } else {
      return router_.reserveBalance(token, reserve_);
    }
  }

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  function pending(OfferType ba) external view returns (int pending_) {
    IERC20 token = outboundOfOfferType(ba);
    pending_ = int(reserveBalance(token, reserve(msg.sender))) - int(offeredVolume(ba));
  }
}
