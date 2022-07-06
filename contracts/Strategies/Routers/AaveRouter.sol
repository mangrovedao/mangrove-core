// SPDX-License-Identifier:	BSD-2-Clause

//AaveRouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "contracts/Strategies/Modules/aave/v3/AaveModule.sol";
import "contracts/Strategies/utils/AccessControlled.sol";
import "contracts/Strategies/utils/TransferLib.sol";
import "./AbstractRouter.sol";

// Underlying on AAVE
// Overlying on reserve
// `this` must approve Lender for outbound token transfer (pull)
// `this` must approve Lender for inbound token transfer (flush)
// `this` must be approved by reserve for *overlying* of inbound token transfer
// `this` must be approved by maker contract for outbound token transfer

// gas overhead:
// - supply ~ 250K
// - borrow ~ 360K
contract AaveRouter is AbstractRouter, AaveV3Module {
  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode
  )
    AaveV3Module(_addressesProvider, _referralCode, _interestRateMode)
    AbstractRouter(700_000)
  {}

  // 1. pulls aTokens from reserve
  // 2. redeems underlying on AAVE to calling maker contract
  function __pull__(
    IEIP20 token,
    address reserve,
    address maker,
    uint amount,
    bool strict
  ) internal virtual override returns (uint pulled) {
    uint available = reserveBalance(token, reserve);
    // if strict enable one should pull at most `amount` from reserve
    if (strict) {
      amount = amount < available ? amount : available;
    } else {
      // one is pulling all availble funds from reserve
      amount = available;
    }
    // transfer below is a noop (almost 0 gas) if reserve == address(this)
    // needs to temporarily deposit tokens to `this` in order to be able to redeem to maker contract
    TransferLib.transferTokenFrom(
      overlying(token),
      reserve,
      address(this),
      amount
    );
    // redeem below is a noop if amount_ == 0
    return _redeem(token, amount, maker);
  }

  // Liquidity : MAKER --> `onBehalf`
  function __push__(
    IEIP20 token,
    address reserve,
    address maker,
    uint amount
  ) internal virtual override {
    require(
      TransferLib.transferTokenFrom(token, maker, address(this), amount),
      "AaveRouter/push/transferFail"
    );
    // repay and supply on behalf of `reserve`
    repayThenDeposit(token, reserve, amount);
  }

  // this fonction is called immediately after a payable function has received funds
  function __push_native__(address reserve, uint amount)
    internal
    virtual
    override
    returns (bool success)
  {
    (success, ) = reserve.call{value: amount}("");
    require(success, "mgvOrder/mo/refundFail");
  }

  function reserveNativeBalance(address reserve)
    public
    view
    override
    returns (uint)
  {
    return reserve.balance;
  }

  // returns 0 if redeem failed (amount > balance).
  // Redeems user balance if amount == type(uint).max
  function __withdrawToken__(
    IEIP20 token,
    address reserve,
    address to,
    uint amount
  ) internal override returns (bool) {
    // note there is no possible redeem on behalf
    require(
      TransferLib.transferTokenFrom(
        overlying(token),
        reserve,
        address(this),
        amount
      ),
      "AaveRouter/supply/transferFromFail"
    );
    require(
      _redeem(token, amount, to) == amount,
      "AaveRouter/withdrawToken/Fail"
    );
    return true;
  }

  // Admin function to manage position on AAVE
  function borrow(
    IEIP20 token,
    address reserve,
    uint amount,
    address to
  ) external onlyAdmin {
    // NB if `reserve` != this, it must approve this router for increasing overlying debt token
    _borrow(token, amount, reserve);
    require(
      TransferLib.transferToken(token, to, amount),
      "AaveRouter/borrow/transferFail"
    );
  }

  function repay(
    IEIP20 token,
    address reserve,
    uint amount,
    address from
  ) external onlyAdmin {
    require(
      TransferLib.transferTokenFrom(token, from, reserve, amount),
      "AaveRouter/repay/transferFromFail"
    );
    _repay(token, amount, reserve);
  }

  function supply(
    IEIP20 token,
    address reserve,
    uint amount,
    address from
  ) external onlyAdmin {
    require(
      TransferLib.transferTokenFrom(token, from, reserve, amount),
      "AaveRouter/supply/transferFromFail"
    );
    _supply(token, amount, reserve);
  }

  function claimRewards(
    IRewardsControllerIsh rewardsController,
    address[] calldata assets
  )
    external
    onlyAdmin
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    return _claimRewards(rewardsController, assets);
  }

  function reserveBalance(IEIP20 token, address reserve)
    public
    view
    virtual
    override
    returns (uint available)
  {
    (available, ) = maxGettableUnderlying(token, false, reserve);
  }

  function approveLender(IEIP20 token) external {
    _approveLender(token, type(uint).max);
  }
}
