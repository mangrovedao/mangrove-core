// SPDX-License-Identifier:	BSD-2-Clause

//BufferedAaveSourcer.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "./AaveSourcer.sol";

// Underlying on AAVE and a buffer on maker contract
// Overlying on sourcer contract
// `this` must approve Lender for outbound token transfer (pull)
// `this` must approve Lender for inbound token transfer (flush)
// `this` must be approved by maker contract for outbound token transfer (flush/pull buffer)
// `this` must be approved by maker contract for inbound token transfer (flush)

contract BufferedAaveSourcer is AaveSourcer {
  mapping(IEIP20 => uint) public liquidity_buffer_size;

  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode,
    address deployer // initial admin
  )
    AaveSourcer(_addressesProvider, _referralCode, _interestRateMode, deployer)
  {}

  // Liquidity : SOURCE --> MAKER
  function __pull__(IEIP20 token, uint amount)
    internal
    virtual
    override
    returns (uint pulled)
  {
    if (token.balanceOf(msg.sender) < amount) {
      // transfer *all* aTokens from AAVE account
      (uint amount_, ) = maxGettableUnderlying(token, false, address(this));
      if (amount_ == 0) {
        return 0;
      } else {
        return _redeem(token, amount_, msg.sender);
      }
    } else {
      // there is enough liquidity on `MAKER`, nothing to do
      return 0;
    }
  }

  // Liquidity : MAKER --> SOURCE
  function __flush__(IEIP20[] calldata tokens) internal virtual override {
    for (uint i = 0; i < tokens.length; i++) {
      uint buffer = tokens[i].balanceOf(msg.sender);
      uint target = liquidity_buffer_size[tokens[i]];
      if (buffer > target) {
        unchecked {
          uint amount = buffer - target;
          require(
            TransferLib.transferTokenFrom(
              tokens[i],
              msg.sender,
              address(this),
              amount
            ),
            "AaveSourcer/flush/transferFail"
          );
          repayThenDeposit(tokens[i], address(this), amount);
        }
      }
    }
  }

  // returns total amount of `token` owned by MAKER
  // if sourcer has a borrowing position, then this total amount may not be entirely redeemable
  function balance(IEIP20 token) public view override returns (uint available) {
    unchecked {
      available = overlying(token).balanceOf(address(this));
      available += token.balanceOf(msg.sender);
    }
  }

  function set_buffer(IEIP20 token, uint buffer_size) external onlyAdmin {
    liquidity_buffer_size[token] = buffer_size;
  }
}
