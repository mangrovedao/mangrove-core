// SPDX-License-Identifier:	BSD-2-Clause

//HasAaveBalanceMemoizer.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {IERC20} from "../AbstractRouter.sol";
import {AaveV3Lender} from "mgv_src/strategies/integrations/AaveV3Lender.sol";

contract HasAaveBalanceMemoizer is AaveV3Lender {
  struct BalanceMemoizer {
    uint localBalance;
    bool localBalanceMemoized;
    uint aaveBalance;
    bool aaveBalanceMemoized;
    IERC20 overlying;
    bool overlyingMemoized;
  }

  constructor(address addressesProvider) AaveV3Lender(addressesProvider) {}

  function _overlying(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (IERC20) {
    if (memoizer.overlyingMemoized) {
      return memoizer.overlying;
    } else {
      memoizer.overlyingMemoized = true;
      memoizer.overlying = overlying(token);
      return memoizer.overlying;
    }
  }

  function _balanceOfOverlying(IERC20 token, address owner, BalanceMemoizer memory memoizer)
    internal
    view
    returns (uint)
  {
    if (memoizer.aaveBalanceMemoized) {
      return memoizer.aaveBalance;
    } else {
      memoizer.aaveBalanceMemoized = true;
      IERC20 aToken = _overlying(token, memoizer);
      if (aToken == IERC20(address(0))) {
        memoizer.aaveBalance = 0;
      } else {
        memoizer.aaveBalance = aToken.balanceOf(owner);
      }
      return memoizer.aaveBalance;
    }
  }

  function _balanceOf(IERC20 token, address owner, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (memoizer.localBalanceMemoized) {
      return memoizer.localBalance;
    } else {
      memoizer.localBalanceMemoized = true;
      memoizer.localBalance = token.balanceOf(owner);
      return memoizer.localBalance;
    }
  }
}
