// SPDX-License-Identifier:	BSD-2-Clause

// AaveTrader.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;
import "./AaveLender.sol";

abstract contract AaveTrader is AaveLender {
  uint public immutable interestRateMode;

  constructor(uint _interestRateMode) {
    interestRateMode = _interestRateMode;
  }

  event ErrorOnBorrow(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    uint amount,
    string errorCode
  );
  event ErrorOnRepay(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    uint amount,
    string errorCode
  );

  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint redeemable, uint liquidity_after_redeem) = maxGettableUnderlying(
      IEIP20(order.outbound_tkn),
      true,
      address(this)
    );

    if (add_(redeemable, liquidity_after_redeem) < amount) {
      return amount; // give up early if not possible to fetch amount of underlying
    }
    // 2. trying to redeem liquidity from Compound
    uint toRedeem = min(redeemable, amount);

    uint notRedeemed = aaveRedeem(toRedeem, address(this), order);
    if (notRedeemed > 0 && toRedeem > 0) {
      // => notRedeemed == toRedeem
      // this should not happen unless compound is out of cash, thus no need to try to borrow
      // log already emitted by `compoundRedeem`
      return amount;
    }
    amount = sub_(amount, toRedeem);
    uint toBorrow = min(liquidity_after_redeem, amount);
    if (toBorrow == 0) {
      return amount;
    }
    // 3. trying to borrow missing liquidity
    try
      lendingPool.borrow(
        order.outbound_tkn,
        toBorrow,
        interestRateMode,
        referralCode,
        address(this)
      )
    {
      return sub_(amount, toBorrow);
    } catch Error(string memory message) {
      emit ErrorOnBorrow(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        toBorrow,
        message
      );
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
    // trying to repay debt if user is in borrow position for inbound_tkn token
    DataTypes.ReserveData memory reserveData = lendingPool.getReserveData(
      order.inbound_tkn
    );

    uint debtOfUnderlying;
    if (interestRateMode == 1) {
      debtOfUnderlying = IEIP20(reserveData.stableDebtTokenAddress).balanceOf(
        address(this)
      );
    } else {
      debtOfUnderlying = IEIP20(reserveData.variableDebtTokenAddress).balanceOf(
          address(this)
        );
    }

    uint toRepay = min(debtOfUnderlying, amount);

    uint toMint;
    try
      lendingPool.repay(
        order.inbound_tkn,
        toRepay,
        interestRateMode,
        address(this)
      )
    {
      toMint = sub_(amount, toRepay);
    } catch Error(string memory message) {
      emit ErrorOnRepay(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        toRepay,
        message
      );
      toMint = amount;
    }
    return aaveMint(toMint, address(this), order);
  }
}
