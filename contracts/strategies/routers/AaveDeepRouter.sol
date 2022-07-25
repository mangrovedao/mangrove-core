// SPDX-License-Identifier:	BSD-2-Clause

//AaveDeepRouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "./AaveRouter.sol";

// Underlying on AAVE
// Overlying on reserve
// `this` must approve Lender for outbound token transfer (pull)
// `this` must approve Lender for inbound token transfer (flush)
// `this` must be approved by reserve for *overlying* of inbound token transfer
// `this` must be approved by maker contract for outbound token transfer

contract AaveDeepRouter is AaveRouter {
  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode
  ) AaveRouter(_addressesProvider, _referralCode, _interestRateMode) {
    ARSt.get_storage().gas_overhead += 350_000; // additional borrow
  }

  // 1. pulls aTokens from aToken reserve. Borrows if necessary
  // 2. redeems underlying on AAVE and forwards received tokens to maker contract
  function __pull__(
    IERC20 token,
    address reserve,
    address maker,
    uint amount,
    bool strict
  ) internal virtual override returns (uint pulled) {
    return redeemThenBorrow(token, reserve, amount, strict, maker);
  }

  function __checkList__(IERC20 token, address reserve)
    internal
    view
    virtual
    override
  {
    // additional allowance for `pull` in case of `borrow`
    ICreditDelegationToken dTkn = debtToken(token);
    require(
      reserve == address(this) ||
        dTkn.borrowAllowance(reserve, address(this)) > 0,
      "AaveDeepRouter/NotDelegatedByReserve"
    );
    super.__checkList__(token, reserve);
  }
}
