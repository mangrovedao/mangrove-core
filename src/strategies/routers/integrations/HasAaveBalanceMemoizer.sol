// SPDX-License-Identifier:	BSD-2-Clause

//HasAaveBalanceMemoizer.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {AaveV3Lender} from "mgv_src/strategies/integrations/AaveV3Lender.sol";

///@title Memoizes values for AAVE to reduce gas cost and simplify code flow.
///@dev the memoizer works in the context of a single token and therefore should not be used across multiple tokens.
contract HasAaveBalanceMemoizer is AaveV3Lender {
  ///@param balanceOf the owner's balance of the token
  ///@param balanceOfMemoized whether the `balanceOf` has been memoized.
  ///@param balanceOfOverlying the balance of the overlying.
  ///@param balanceOfOverlyingMemoized whether the `balanceOfOverlying` has been memoized.
  ///@param overlying the overlying
  ///@param overlyingMemoized whether the `overlying` has been memoized.
  struct BalanceMemoizer {
    uint balanceOf;
    bool balanceOfMemoized;
    uint balanceOfOverlying;
    bool balanceOfOverlyingMemoized;
    IERC20 overlying;
    bool overlyingMemoized;
    bool totalSupplyMemoized;
    uint totalSupply;
  }

  constructor(address addressesProvider) AaveV3Lender(addressesProvider) {}

  ///@notice Gets the overlying for the token.
  ///@param token the token.
  ///@param memoizer the memoizer.
  function overlying(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (IERC20) {
    if (memoizer.overlyingMemoized) {
      return memoizer.overlying;
    } else {
      memoizer.overlyingMemoized = true;
      memoizer.overlying = overlying(token);
      return memoizer.overlying;
    }
  }

  ///@notice Gets the balance for the overlying of the token, or 0 if there is no overlying.
  ///@param token the token.
  ///@param memoizer the memoizer.
  function balanceOfOverlying(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (memoizer.balanceOfOverlyingMemoized) {
      return memoizer.balanceOfOverlying;
    } else {
      memoizer.balanceOfOverlyingMemoized = true;
      IERC20 aToken = overlying(token, memoizer);
      if (aToken == IERC20(address(0))) {
        memoizer.balanceOfOverlying = 0;
      } else {
        memoizer.balanceOfOverlying = aToken.balanceOf(address(this));
      }
      return memoizer.balanceOfOverlying;
    }
  }

  function totalSupply(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (!memoizer.totalSupplyMemoized) {
      IERC20 aToken = overlying(token, memoizer);
      memoizer.totalSupply = token.balanceOf(address(aToken));
      memoizer.totalSupplyMemoized = true;
    }
    return memoizer.totalSupply;
  }

  ///@notice Gets the balance of the token
  ///@param token the token.
  ///@param memoizer the memoizer.
  function balanceOf(IERC20 token, BalanceMemoizer memory memoizer) internal view returns (uint) {
    if (memoizer.balanceOfMemoized) {
      return memoizer.balanceOf;
    } else {
      memoizer.balanceOfMemoized = true;
      memoizer.balanceOf = token.balanceOf(address(this));
      return memoizer.balanceOf;
    }
  }
}
