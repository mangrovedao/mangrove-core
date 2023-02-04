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

  constructor(address _addressesProvider) AaveV3Lender(_addressesProvider) {}

  function _overlying(IERC20 token, BalanceMemoizer memory v_tkn) internal view returns (IERC20) {
    if (v_tkn.overlyingMemoized) {
      return v_tkn.overlying;
    } else {
      v_tkn.overlyingMemoized = true;
      v_tkn.overlying = overlying(token);
      return v_tkn.overlying;
    }
  }

  function _balanceOfOverlying(IERC20 token, address owner, BalanceMemoizer memory v_tkn) internal view returns (uint) {
    if (v_tkn.aaveBalanceMemoized) {
      return v_tkn.aaveBalance;
    } else {
      v_tkn.aaveBalanceMemoized = true;
      IERC20 aToken = _overlying(token, v_tkn);
      if (aToken == IERC20(address(0))) {
        v_tkn.aaveBalance = 0;
      } else {
        v_tkn.aaveBalance = aToken.balanceOf(owner);
      }
      return v_tkn.aaveBalance;
    }
  }

  function _balanceOf(IERC20 token, address owner, BalanceMemoizer memory v_tkn) internal view returns (uint) {
    if (v_tkn.localBalanceMemoized) {
      return v_tkn.localBalance;
    } else {
      v_tkn.localBalanceMemoized = true;
      v_tkn.localBalance = token.balanceOf(owner);
      return v_tkn.localBalance;
    }
  }
}
