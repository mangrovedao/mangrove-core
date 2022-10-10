// SPDX-License-Identifier:	BSD-2-Clause

// SumToken.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.12;

pragma abicoder v2;

// TODO: Seems a bit heavy to rely on MgvLib to get IERC20..
import {IERC20} from "mgv_src/MgvLib.sol";

// Objective:
// Enable a market (A+B)/C where sellers can deliver A's or B's for C without ever wrapping the A's or B's.
//
// Example #1: Maker is EOA
// maker ask offer: gives: 1 (A+B), wants: 10 C
//   maker holds 1 A
// taker buy: wants: 1 (A+B), gives: 10 C
//   1/ Mangrove calls C.transferFrom(taker, Mangrove, 10)
//   2/ Mangrove calls C.transfer(Mangrove, maker, 10)
//   3/ maker execute - noop as maker is EOA    <--- NB: We may not need to support this for carbon markets?
//   4/ Mangrove calls (A+B).transferFrom(maker, Mangrove, 1)
//      4a/ (A+B) calls A.transferFrom(maker, Mangrove, 1)
//   5/ Mangrove calls (A+B).transfer(taker, 1)
//      5a/ (A+B) calls A.transferFrom(Mangrove, taker, 1)

// Invariants:
//   1/ decimals for the underlying tokens must be the same

// Approvals:
//   Maker:
//     - approve Mangrove for (A+B)
//     - approve (A+B) for A or B    <-- could be used to control what token maker wants to use
//   Taker:
//     - approve Mangrove for C
//   Mangrove:
//     - approve (A+B) for A and B

// TODO:
// - add unchecked in the places where overflow/underflow is guaranteed not to happen
contract SumToken is IERC20 {
  // REQUIRED in ERC20 std:
  // Functions:
  //   totalSupply()
  //     A.totalSupply() + B.totalSupply()
  //     NB: Overflow?
  //   balanceOf(account)
  //     A.balanceOf(account) + B.balanceOf(account)
  //   transfer(to, amount)
  //     Which underlying should be transferred - alternative:
  //       1/ A's then B's if needed
  //       2/ sender could register which token they want to use
  //       3/ keep track of last received token and transfer those next <-- I think the model Vincent and I made did this
  //   allowance(owner, spender)
  //   approve(spender, amount)
  //   transferFrom(from, to, amount)
  //
  // Events:
  //   Transfer(from, to, value)
  //   Approval(owner, spender, value)
  //
  //
  // OPTIONAL:
  // Functions:
  //   name()
  //   symbol()
  //   decimals()

  IERC20 public immutable TOKEN_A;
  IERC20 public immutable TOKEN_B;

  mapping(address => mapping(address => uint)) private _allowances;

  uint8 private immutable _decimals;
  string private _symbol;

  constructor(IERC20 tokenA, IERC20 tokenB) {
    _decimals = tokenA.decimals();
    if (_decimals != tokenB.decimals()) {
      revert("tokens do not have same decimals");
    }
    TOKEN_A = tokenA;
    TOKEN_B = tokenB;
    _symbol = string.concat(tokenA.symbol(), "+", tokenB.symbol());
  }

  function symbol() external view returns (string memory) {
    return _symbol;
  }

  function decimals() external view returns (uint8) {
    return _decimals;
  }

  // Returns type(uint).max if the total supply is greater than type(uint).max
  function totalSupply() external view returns (uint) {
    unchecked {
      uint totalSupplyA = TOKEN_A.totalSupply();
      uint result = totalSupplyA + TOKEN_B.totalSupply();
      if (result < totalSupplyA) return type(uint).max;
      return result;
    }
  }

  // Returns type(uint).max if the total supply is greater than type(uint).max
  function balanceOf(address account) external view returns (uint) {
    unchecked {
      uint balanceOfA = TOKEN_A.balanceOf(account);
      uint result = balanceOfA + TOKEN_B.balanceOf(account);
      if (result < balanceOfA) return type(uint).max;
      return result;
    }
  }

  function transfer(address recipient, uint amount) external returns (bool) {
    return _transfer(msg.sender, recipient, amount);
  }

  function allowance(address owner, address spender) external view returns (uint) {
    return _allowances[owner][spender];
  }

  // TODO: This is unsafe since attackers may use previous and new allowance. We should provide in-/decreaseAllowance as well
  // TODO: type(uint256).max is interpreted as infinite approval
  function approve(address spender, uint amount) external returns (bool) {
    _allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function transferFrom(address owner, address recipient, uint amount) external returns (bool) {
    uint currentAllowance = _allowances[owner][msg.sender];
    if (currentAllowance != type(uint).max) {
      require(currentAllowance >= amount, "insufficient allowance");
      _allowances[owner][msg.sender] = currentAllowance - amount;
    }

    return _transfer(owner, recipient, amount);
  }

  // Transfer function which selects the transfer strategy to use
  function _transfer(address owner, address recipient, uint amount) internal returns (bool) {
    // TODO: Select transfer logic - for now, we just select a naive implementation
    return _transferAOverB(owner, recipient, amount);
  }

  // Transfer logic #1: Prefer A's over B's
  function _transferAOverB(address owner, address recipient, uint amount) internal returns (bool) {
    uint balanceA = TOKEN_A.balanceOf(owner);
    uint balanceB = TOKEN_B.balanceOf(owner);
    // FIXME: handle overflow - since amount is capped, overflow should just result in MAX
    require((balanceA + balanceB) >= amount, "insufficient balance");

    uint amountA = amount > balanceA ? balanceA : amount;
    uint amountB = amount - amountA;

    TOKEN_A.transferFrom(owner, recipient, amountA);
    TOKEN_B.transferFrom(owner, recipient, amountB);

    return true;
  }
}
