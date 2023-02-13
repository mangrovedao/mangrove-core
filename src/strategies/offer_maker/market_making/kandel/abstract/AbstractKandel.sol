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

///@title Core external functions and events for Kandel strats.
abstract contract AbstractKandel {
  ///@notice signals that the price has moved above Kandel's current price range.
  event AllAsks();
  ///@notice signals that the price has moved below Kandel's current price range.
  event AllBids();

  ///@notice the compound rates have been set to `compoundRateBase` and `compoundRateQuote` which will take effect for future compounding.
  event SetCompoundRates(uint compoundRateBase, uint compoundRateQuote);

  ///@notice the gasprice has been set.
  event SetGasprice(uint value);

  ///@notice the gasreq has been set.
  event SetGasreq(uint value);

  ///@notice the Kandel instance is credited of `amount` by its owner.
  event Credit(IERC20 indexed token, uint amount);

  ///@notice the Kandel instance is debited of `amount` by its owner.
  event Debit(IERC20 indexed token, uint amount);

  ///@notice the amount of liquidity that is available for the strat but not offered by the given offer type.
  ///@param ba the offer type.
  ///@return the amount of pending liquidity. Will be negative if more is offered than is available on the reserve balance.
  ///@dev Pending could be withdrawn or invested by increasing offered volume.
  function pending(OfferType ba) external view virtual returns (int);

  ///@notice the total balance available for the strat of the offered token for the given offer type.
  ///@param ba the offer type.
  ///@return balance the balance of the token.
  function reserveBalance(OfferType ba) public view virtual returns (uint balance);

  ///@notice deposits funds to be available for being offered. Will increase `pending`.
  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) public virtual;

  ///@notice withdraws the amounts of the given tokens to the recipient.
  ///@param tokens the tokens to withdraw.
  ///@param amounts the amounts of the tokens to withdraw.
  ///@param recipient the recipient of the funds.
  ///@dev it is up to the caller to make sure there are still enough funds for live offers.
  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient) public virtual;

  ///@notice set the compound rates. It will take effect for future compounding.
  ///@param compoundRateBase the compound rate for base.
  ///@param compoundRateQuote the compound rate for quote.
  ///@dev For low compound rates Kandel can end up with everything as pending and nothing offered.
  ///@dev To avoid this, then for equal compound rates `C` then $C >= 1/(sqrt(ratio^spread)+1)$.
  ///@dev With one rate being 0 and the other 1 the amount earned from the spread will accumulate as pending
  ///@dev for the token at 0 compounding and the offered volume will stay roughly static (modulo rounding).
  function setCompoundRates(uint compoundRateBase, uint compoundRateQuote) public virtual;

  ///@notice sets the gasprice for offers
  function setGasprice(uint gasprice) public virtual;

  ///@notice sets the gasreq (including router's gasreq) for offers
  function setGasreq(uint gasreq) public virtual;
}
