// SPDX-License-Identifier:	BSD-2-Clause

//AaveRouter.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

pragma abicoder v2;

import "./AaveDeepRouter.sol";

// gas overhead:
// - supply ~ 250K
// - borrow ~ 360K

//Using a AaveDeepRouter, it will borrow and deposit on behalf of the reserve.
//This means that yield and interest will do handle for the reserve. Is this true?
contract PooledAaveRouter is AaveDeepRouter {
  // balance of token for an owner
  mapping(IERC20 => mapping(address => uint)) internal ownerBalance;

  constructor(address _addressesProvider, uint _referralCode, uint _interestRateMode)
    AaveDeepRouter(_addressesProvider, _referralCode, _interestRateMode)
  {}

  // Increases balance of token for owner.
  // should have some accessControl
  function increaseBalance(IERC20 token, address owner, uint amount) external returns (uint) {
    uint newBalance = ownerBalance[token][owner] + amount;
    ownerBalance[token][owner] = newBalance;
    return newBalance;
  }

  // Decrease balance of token for owner.
  // should have some accessControl
  function decreaseBalance(IERC20 token, address owner, uint amount) external returns (uint) {
    uint currentBalance = ownerBalance[token][owner];
    require(currentBalance >= amount, "AavePoolRouter/decreaseBalance/amountMoreThanBalance");
    uint newBalance = ownerBalance[token][owner] - amount;
    ownerBalance[token][owner] = newBalance;
    return newBalance;
  }

  function getBalance(IERC20 token, address owner) external view returns (uint) {
    return ownerBalance[token][owner];
  }
}
