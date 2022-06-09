// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./SingleUser.sol";
import "../../Modules/aave/v3/AaveModule.sol";

abstract contract AaveV3Lender is SingleUser, AaveV3Module {
  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice exits markets
  function exitMarket(IEIP20 underlying) external onlyAdmin {
    _exitMarket(underlying);
  }

  function enterMarkets(IEIP20[] calldata underlyings) external onlyAdmin {
    _enterMarkets(underlyings);
  }

  function approveLender(IEIP20 token, uint amount) external onlyAdmin {
    _approveLender(token, amount);
  }

  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    (
      uint redeemable, /*maxBorrowAfterRedeem*/

    ) = maxGettableUnderlying(IEIP20(order.outbound_tkn), false, address(this));
    if (amount > redeemable) {
      return amount; // give up if amount is not redeemable (anti flashloan manipulation of AAVE)
    }

    // A more gas efficient strategy if this offer is not alone in the book is to redeem `redeemable` here
    // in the deployable contract, the `__get__` method should call `AaveV2Lender.__get__` only if it does not have the cash
    // `__posthookSuccess__` should then deposit back the unspent underlying
    // NB redeeming all underlying would put the user at risk of a liquiditation (when user is borrowing) if the posthook fails to put back money
    if (_redeem(IEIP20(order.outbound_tkn), amount, address(this)) == amount) {
      // amount was transfered to `this`
      return 0;
    } else {
      return amount;
    }
  }

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
    _supply(IEIP20(order.inbound_tkn), amount, address(this));
    return 0;
  }

  function redeem(
    IEIP20 token,
    uint amount,
    address to
  ) external onlyAdmin returns (uint redeemed) {
    redeemed = _redeem(token, amount, to);
  }

  function mint(
    IEIP20 token,
    uint amount,
    address to
  ) external onlyAdmin {
    _supply(token, amount, to);
  }
}
