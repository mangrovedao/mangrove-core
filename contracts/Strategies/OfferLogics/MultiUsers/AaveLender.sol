// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.7.0;
pragma abicoder v2;
import "./MultiUser.sol";
import "../AaveModule.sol";

abstract contract MultiUserAaveLender is MultiUser, AaveModule {
  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  function mint(
    uint amount,
    address asset,
    address onBehalf
  ) external onlyAdmin {
    _mint(amount, asset, onBehalf);
  }

  // tokens are fetched on Aave (on behalf of offer owner)
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    address owner = ownerOf(
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId
    );
    if (owner == address(0)) {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
    (
      uint redeemable, /*maxBorrowAfterRedeem*/

    ) = maxGettableUnderlying(order.outbound_tkn, false, owner);
    if (amount > redeemable) {
      return amount; // give up if amount is not redeemable (anti flashloan manipulation of AAVE)
    }
    // need to retreive overlyings from msg.sender (we suppose `this` is approved for that)
    IERC20 aToken = overlying(IERC20(order.outbound_tkn));
    try aToken.transferFrom(owner, address(this), amount) returns (
      bool success
    ) {
      if (aaveRedeem(amount, owner, order) == 0) {
        // amount was transfered to `this`
        return 0;
      }
      emit ErrorOnRedeem(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        amount,
        "lender/multi/redeemFailed"
      );
    } catch {
      emit ErrorOnRedeem(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        amount,
        "lender/multi/transferFromFail"
      );
    }
    return amount; // nothing was fetched
  }

  // received inbound token are put on Aave on behalf of offer owner
  function __put__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    //optim
    if (amount == 0) {
      return 0;
    }
    address owner = ownerOf(
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId
    );
    if (owner == address(0)) {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
    // minted Atokens are sent to owner
    return aaveMint(amount, owner, order);
  }
}
