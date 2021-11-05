// SPDX-License-Identifier:	BSD-2-Clause

// CompoundTrader.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;
import "./CompoundLender.sol";
import "hardhat/console.sol";

abstract contract CompoundTrader is CompoundLender {
  event ErrorOnBorrow(address cToken, uint amount, uint errorCode);
  event ErrorOnRepay(address cToken, uint amount, uint errorCode);

  ///@notice method to get `outbound_tkn` during makerExecute
  ///@param outbound_tkn address of the ERC20 managing `outbound_tkn` token
  ///@param amount of token that the trade is still requiring
  function __get__(IERC20 outbound_tkn, uint amount)
    internal
    virtual
    override
    returns (uint)
  {
    if (!isPooled(address(outbound_tkn))) {
      return amount;
    }
    IcERC20 outbound_cTkn = IcERC20(overlyings[outbound_tkn]); // this is 0x0 if outbound_tkn is not compound sourced for borrow.

    if (address(outbound_cTkn) == address(0)) {
      return amount;
    }

    // 1. Computing total borrow and redeem capacities of underlying asset
    (uint redeemable, uint liquidity_after_redeem) = maxGettableUnderlying(
      address(outbound_cTkn)
    );

    // 2. trying to redeem liquidity from Compound
    uint toRedeem = min(redeemable, amount);

    uint notRedeemed = compoundRedeem(outbound_cTkn, toRedeem);
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
    uint errorCode = outbound_cTkn.borrow(toBorrow);
    if (errorCode != 0) {
      emit ErrorOnBorrow(address(outbound_cTkn), toBorrow, errorCode);
      return amount; // unable to borrow requested amount
    }
    // if ETH were borrowed, one needs to turn them into wETH
    if (isCeth(outbound_cTkn)) {
      weth.deposit{value: toBorrow}();
    }
    return sub_(amount, toBorrow);
  }

  /// @notice contract need to have approved `inbound_tkn` overlying in order to repay borrow
  function __put__(IERC20 inbound_tkn, uint amount) internal virtual override {
    //optim
    if (amount == 0 || !isPooled(address(inbound_tkn))) {
      return;
    }
    // NB: overlyings[wETH] = cETH
    IcERC20 inbound_cTkn = IcERC20(overlyings[inbound_tkn]);
    if (address(inbound_cTkn) == address(0)) {
      return;
    }
    // trying to repay debt if user is in borrow position for inbound_tkn token
    uint toRepay = min(
      inbound_cTkn.borrowBalanceCurrent(address(this)),
      amount
    ); //accrues interests

    uint errCode;
    if (isCeth(inbound_cTkn)) {
      // turning WETHs to ETHs
      weth.withdraw(toRepay);
      // OK since repayBorrow throws if failing in the case of Eth
      inbound_cTkn.repayBorrow{value: toRepay}();
    } else {
      errCode = inbound_cTkn.repayBorrow(toRepay);
    }
    uint toMint;
    if (errCode != 0) {
      emit ErrorOnRepay(address(inbound_cTkn), toRepay, errCode);
      toMint = amount;
    } else {
      toMint = amount - toRepay;
    }
    compoundMint(inbound_cTkn, toMint);
  }
}
