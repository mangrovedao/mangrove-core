// SPDX-License-Identifier:	BSD-2-Clause

//AavePoolManager.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import "./AaveRouter.sol";

contract AavePoolManager is AaveRouter {
  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode, uint overhead)
    AaveRouter(_addressesProvider, _referralCode, _interestRateMode, overhead)
  {}

  // Admin function to manage position on AAVE
  function redeem(IERC20 token, address reserve, uint amount, address to) external onlyAdmin {
    // NB if `reserve` != this, it must approve this router for increasing overlying debt token
    require(
      TransferLib.transferTokenFrom(overlying(token), reserve, address(this), amount),
      "AavePoolManager/borrow/transferFail"
    );
    _redeem(token, amount, to);
  }

  // Admin function to manage position on AAVE
  function borrow(IERC20 token, address reserve, uint amount, address to) external onlyAdmin {
    // NB if `reserve` != this, it must approve this router for increasing overlying debt token
    _borrow(token, amount, reserve);
    require(TransferLib.transferToken(token, to, amount), "AavePoolManager/borrow/transferFail");
  }

  function repay(IERC20 token, address reserve, uint amount, address from) external onlyAdmin {
    require(TransferLib.transferTokenFrom(token, from, reserve, amount), "AavePoolManager/repay/transferFromFail");
    _repay(token, amount, reserve);
  }

  function supply(IERC20 token, address reserve, uint amount, address from) external onlyAdmin {
    require(TransferLib.transferTokenFrom(token, from, reserve, amount), "AavePoolManager/supply/transferFromFail");
    _supply(token, amount, reserve);
  }

  function claimRewards(IRewardsControllerIsh rewardsController, address[] calldata assets)
    external
    onlyAdmin
    returns (address[] memory rewardsList, uint[] memory claimedAmounts)
  {
    return _claimRewards(rewardsController, assets);
  }
}
