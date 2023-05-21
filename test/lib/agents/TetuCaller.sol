// SPDX-License-Identifier:	BSD-2-Clause

// TetuCaller.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {IERC20, TetuLender} from "mgv_src/strategies/integrations/TetuLender.sol";
import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";

contract TetuCaller is TetuLender, AccessControlled {
  constructor(address vault) TetuLender(vault) AccessControlled(msg.sender) {}

  function supply(uint amount, address onbehalf) public onlyAdmin {
    _supply(amount, onbehalf, false);
  }

  function supplyAndInvest(uint amount) public onlyAdmin {
    _supplyAndInvest(amount, false);
  }

  function redeem(uint amount, address to) public onlyAdmin {
    _redeem(amount, to);
  }

  function approveLender(uint amount) public onlyAdmin {
    _approveLender(amount);
  }

  // full_share --> getPricePerFullSHares
  // 1 share --> getPricePerFullShares/full_shares
  // overlying.balance  --> overlying.balance * getPricePerFullShares / full_shares

  function tokenBalance(IERC20 token, address reserveId) public view returns (uint balance) {
    if (token == UNDERLYING) {
      balance = (OVERLYING.balanceOf(reserveId) * VAULT.getPricePerFullShare()) / OVERLYING.totalSupply();
    }
    balance += token.balanceOf(reserveId);
  }
}
