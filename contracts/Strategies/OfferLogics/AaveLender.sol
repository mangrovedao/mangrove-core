// SPDX-License-Identifier:	BSD-2-Clause

//AaveLender.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.7.0;
pragma abicoder v2;
import "./SingleUser.sol";
import "./AaveModule.sol";

abstract contract AaveLender is SingleUser, AaveModule {
  /**************************************************************************/
  ///@notice Required functions to let `this` contract interact with Aave
  /**************************************************************************/

  ///@notice approval of ctoken contract by the underlying is necessary for minting and repaying borrow
  ///@notice user must use this function to do so.

  function approveLender(address token, uint amount) external onlyAdmin {
    _approveLender(token, amount);
  }

  ///@notice exits markets
  function exitMarket(IERC20 underlying) external onlyAdmin {
    _exitMarket(underlying);
  }

  function enterMarkets(IERC20[] calldata underlyings) external onlyAdmin {
    _enterMarkets(underlyings);
  }

  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    (
      uint redeemable, /*maxBorrowAfterRedeem*/

    ) = maxGettableUnderlying(order.outbound_tkn, false);
    if (amount > redeemable) {
      return amount; // give up if amount is not redeemable (anti flashloan manipulation of AAVE)
    }

    if (aaveRedeem(outbound_tkn, amount) == 0) {
      // amount was transfered to `this`
      return 0;
    }
    return amount;
  }

  function aaveRedeem(IERC20 asset, uint amountToRedeem)
    internal
    returns (uint)
  {
    try
      lendingPool.withdraw(order.outbound_tkn, amountToRedeem, address(this))
    returns (uint withdrawn) {
      //aave redeem was a success
      if (amountToRedeem == withdrawn) {
        return 0;
      } else {
        return (amountToRedeem - withdrawn);
      }
    } catch Error(string memory message) {
      emit ErrorOnRedeem(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        amountToRedeem,
        message
      );
      return amountToRedeem;
    }
  }

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
    return aaveMint(amount, order);
  }

  function mint(uint amount, address token) external onlyAdmin {
    lendingPool.deposit(token, amount, address(this), referralCode);
    aaveMint(inbound_tkn, amount);
  }
}
