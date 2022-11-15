// SPDX-License-Identifier:	BSD-2-Clause

// IOrderLogic.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.0;

pragma abicoder v2;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title Interface for resting orders functionality.
interface IOrderLogic {
  ///@notice Information for creating a market order with a GTC or FOK semantics.
  ///@param outbound_tkn outbound token used to identify the order book
  ///@param inbound_tkn the inbound token used to identify the order book
  ///@param fillOrKill true to revert if market order cannot be filled and resting order failed or is not enabled; otherwise, false
  ///@param takerWants desired total amount of `outbound_tkn` (slippage included)
  ///@param takerGives available total amount of `inbound_tkn` (slippage included)
  ///@param slippageAmount if `fillWants` (buying) this is the amount of inbound tokens that must be substracted from `takerGives` to obtain the taker price before slippage. Else this is the amount of outbound tokens that must be added to `takerWants`
  ///@dev e.g for a `fillWants` order at price  `(gives/takerWants) * (1+slippage) `, one should set `takerGives = gives + slippageAmount` with `slippageAmount = (gives * slippage) / 100` for a slippage expressed in percent.
  ///@dev e.g for `!fillWants` order at price `(wants/takerGives) * (1+slippage)`, one should set `takerWants = wants + slippageAmount` with `slippageAmount = (wants * slippage) / 100` for a slippage expressed in percent.
  ///@param fillWants if true (buying), the market order stops when `takerWants` units of `outbound_tkn` have been obtained (fee included); otherwise (selling), the market order stops when `takerGives` units of `inbound_tkn` have been sold.
  ///@param restingOrder whether the complement of the partial fill (if any) should be posted as a resting limit order.
  ///@param pivotId in case a resting order is required, the best pivot estimation of its position in the offer list (if the market order led to a non empty partial fill, then `pivotId` should be 0 unless the order book is crossed).
  ///@param expiryDate timestamp (expressed in seconds since unix epoch) beyond which the order is no longer valid, 0 means forever
  struct TakerOrder {
    IERC20 outbound_tkn;
    IERC20 inbound_tkn;
    bool fillOrKill;
    uint takerWants;
    uint takerGives;
    uint slippageAmount;
    bool fillWants;
    bool restingOrder;
    uint pivotId;
    uint expiryDate;
  }

  ///@notice Result of an order from the takers side.
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param bounty How much bounty was givin to the taker
  ///@param fee The fee paid by the taker
  ///@param offerId The id of the offer that was taken
  struct TakerOrderResult {
    uint takerGot;
    uint takerGave;
    uint bounty;
    uint fee;
    uint offerId;
  }

  ///@notice Information about the order.
  ///@param mangrove The Mangrove contract on which the offer was posted
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param taker The address of the taker
  ///@param fillWants If true, the market order stopped when `takerWants` units of `outbound_tkn` had been obtained; otherwise, the market order stopped when `takerGives` units of `inbound_tkn` had been sold.
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param penalty How much penalty was given
  event OrderSummary(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    address indexed taker,
    bool fillWants,
    uint takerGot,
    uint takerGave,
    uint penalty
  );

  ///@notice Timestamp beyond which the given `offerId` should renege on trade.
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param offerId The id of the offer to query for expiry for.
  ///@return res The timestamp beyond which `offerId` on the `(outbound_tkn, inbound_tkn)` offer list should renege on trade. 0 means no expiry.
  function expiring(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) external returns (uint);

  ///@notice Updates the expiry date for a specific offer.
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param offerId The offer id whose expiry date is to be set.
  ///@param date in seconds since unix epoch
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  function setExpiry(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, uint date) external;

  ///@notice Implements "Fill or kill" or "Good till cancelled" orders on a given offer list.
  ///@param tko the arguments in memory of the taker order
  ///@return res the result of the taker order. If `offerId==0`, no resting order was posted on `msg.sender`'s behalf.
  function take(TakerOrder memory tko) external payable returns (TakerOrderResult memory res);

  ///@notice Increase gas requirement for all new offers.
  ///@param additionalGasreq_ additional gas requirement
  function setAdditionalGasreq(uint additionalGasreq_) external;
}
