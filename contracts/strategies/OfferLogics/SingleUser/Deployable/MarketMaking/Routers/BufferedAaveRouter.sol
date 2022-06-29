// SPDX-License-Identifier:	BSD-2-Clause

//BufferedAaveRouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "./AaveRouter.sol";

// BUFFER on maker contract
// overlying on `reserve`
// underlying on AAVE
contract BufferedAaveRouter is AaveRouter {
  mapping(IEIP20 => uint) public liquidity_buffer_size;

  constructor(
    address _addressesProvider,
    uint _referralCode,
    uint _interestRateMode,
    address deployer // initial admin
  )
    AaveRouter(_addressesProvider, _referralCode, _interestRateMode, deployer)
  {}

  // Liquidity : reserve --> MAKER
  function __pull__(
    IEIP20 token,
    uint amount,
    address reserve
  ) internal virtual override returns (uint pulled) {
    // checks if maker contract has enough buffer
    if (token.balanceOf(msg.sender) < amount) {
      // transfer *all* aTokens from AAVE account
      (uint amount_, ) = maxGettableUnderlying(token, false, reserve);
      // transfer below is a noop (almost 0 gas) if reserve == address(this)
      TransferLib.transferTokenFrom(
        overlying(token),
        reserve,
        address(this),
        amount_
      );
      return _redeem(token, amount_, msg.sender);
    } else {
      // there is enough liquidity on `MAKER`, nothing to do
      return 0;
    }
  }

  // Liquidity : MAKER --> reserve
  function __flush__(IEIP20[] calldata tokens, address reserve)
    internal
    virtual
    override
  {
    for (uint i = 0; i < tokens.length; i++) {
      uint buffer = tokens[i].balanceOf(msg.sender);
      uint target = liquidity_buffer_size[tokens[i]];
      if (buffer > target) {
        unchecked {
          uint amount = buffer - target;
          // pulling whatever remains on maker contract to `this`
          require(
            TransferLib.transferTokenFrom(
              tokens[i],
              msg.sender,
              address(this),
              amount
            ),
            "BufferedAaveRouter/flush/transferFail"
          );
          // repaying potential debt of reserve and supplying the rest on its behalf
          repayThenDeposit(tokens[i], reserve, amount);
        }
      }
    }
  }

  // returns total amount of `token` available to MAKER which is the sum of available underlying to the `reserve` and the buffer
  function balance(IEIP20 token, address reserve)
    public
    view
    override
    returns (uint available)
  {
    available = super.balance(token, reserve);
    unchecked {
      available += token.balanceOf(msg.sender);
    }
  }

  function set_buffer(IEIP20 token, uint buffer_size) external onlyAdmin {
    liquidity_buffer_size[token] = buffer_size;
  }
}
