// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./MultiUser.sol";
import "../../Modules/aave/v3/AaveModule.sol";

// NB make sure to inherit AaveV3Module first to maintain storage layout
abstract contract MultiUserAaveV3Lender is MultiUser, AaveV3Module {
  function approveLender(IEIP20 token, uint amount) external onlyAdmin {
    _approveLender(token, amount);
  }

  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  // tokens are fetched on Aave (on behalf of offer owner)
  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    address owner = ownerOf(
      IEIP20(order.outbound_tkn),
      IEIP20(order.inbound_tkn),
      order.offerId
    );
    (
      uint redeemable, /*maxBorrowAfterRedeem*/

    ) = maxGettableUnderlying(IEIP20(order.outbound_tkn), false, owner);
    if (amount > redeemable) {
      return amount; // give up if amount is not redeemable (anti flashloan manipulation of AAVE)
    }
    // need to retreive overlyings from msg.sender (we suppose `this` is approved for that)
    IEIP20 aToken = overlying(IEIP20(order.outbound_tkn));
    try aToken.transferFrom(owner, address(this), amount) returns (
      bool success
    ) {
      if (success) {
        // amount overlying was transfered from `owner`'s wallet
        // anything wrong beyond this point should revert
        // trying to redeem from AAVE
        require(
          _redeem(IEIP20(order.outbound_tkn), amount, address(this)) == amount,
          "mgvOffer/aave/redeemFailed"
        );
        return 0;
      }
    } catch {
      // same as `success == false`
    }
    return amount; // nothing was fetched
  }

  // received inbound token are put on Aave on behalf of offer owner
  function __put__(uint amount, ML.SingleOrder calldata order)
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
      IEIP20(order.outbound_tkn),
      IEIP20(order.inbound_tkn),
      order.offerId
    );
    // minted Atokens are sent to owner
    _supply(IEIP20(order.inbound_tkn), amount, owner);
    return 0;
  }
}
