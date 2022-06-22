// SPDX-License-Identifier:	BSD-2-Clause

//AaveRouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "contracts/strategies/Modules/aave/v3/AaveModule.sol";
import "contracts/strategies/utils/AccessControlled.sol";
import "contracts/strategies/utils/TransferLib.sol";
import "../AbstractRouter.sol";

// Underlying on AAVE
// Overlying on router contract
// `this` must approve Lender for outbound token transfer (redeem)
// `this` must approve Lender for inbound token transfer (repay/supply)
// `this` must be approved by maker contract for inbound token transfer

contract AaveRouter is AbstractRouter, AaveV3Module {
  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode,
    address deployer
  )
    AbstractRouter(deployer) // admin is deployer, main source of liquidity is `this` contract
    AaveV3Module(_addressesProvider, _referralCode, _interestRateMode)
  {}

  // Liquidity : draws requested funds from aave (burning overlyings) and sends the retrived tokens to the maker contract
  function __pull__(IEIP20 token, uint amount)
    internal
    virtual
    override
    returns (uint pulled)
  {
    (uint amount_, ) = maxGettableUnderlying(token, false, address(this));
    amount_ = amount < amount_ ? amount : amount_;
    return _redeem(token, amount_, msg.sender);
  }

  // Liquidity :
  function __flush__(IEIP20[] calldata tokens) internal virtual override {
    for (uint i = 0; i < tokens.length; i++) {
      // checking how much tokens are stored on MAKER's balance as a consequence of __put__
      uint amount = tokens[i].balanceOf(msg.sender);
      require(
        TransferLib.transferTokenFrom(
          tokens[i],
          msg.sender,
          address(this),
          amount
        ),
        "AaveRouter/flush/transferFail"
      );
      repayThenDeposit(tokens[i], address(this), amount);
    }
  }

  function balance(IEIP20 token)
    public
    view
    virtual
    override
    returns (uint available)
  {
    return overlying(token).balanceOf(address(this));
  }

  function borrow(
    IEIP20 token,
    uint amount,
    address to
  ) external onlyAdmin {
    _borrow(token, amount, address(this));
    require(
      TransferLib.transferToken(token, to, amount),
      "AaveRouter/borrow/transferFail"
    );
  }

  function repay(
    IEIP20 token,
    uint amount,
    address from
  ) external onlyAdmin {
    require(
      TransferLib.transferTokenFrom(token, from, address(this), amount),
      "AaveRouter/repay/transferFromFail"
    );
    _repay(token, amount, address(this));
  }

  function supply(
    IEIP20 token,
    uint amount,
    address from
  ) external onlyAdmin {
    require(
      TransferLib.transferTokenFrom(token, from, address(this), amount),
      "AaveRouter/supply/transferFromFail"
    );
    _supply(token, amount, address(this));
  }

  // returns 0 if redeem failed (amount > balance).
  // Redeems user balance is amount == type(uint).max
  function withdraw(
    IEIP20 token,
    uint amount,
    address to
  ) external onlyAdmin returns (uint) {
    return _redeem(token, amount, to);
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

  function approveLender(IEIP20 token) external onlyAdmin {
    _approveLender(token, type(uint).max);
  }

  function transferToken(
    IEIP20 token,
    uint amount,
    address to
  ) external onlyAdmin {
    require(
      TransferLib.transferToken(token, to, amount),
      "AaveRouter/transferTokenFail"
    );
  }
}
