// SPDX-License-Identifier:	BSD-2-Clause

//AbstractRouter.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;
pragma abicoder v2;

import "mgv_src/strategies/utils/AccessControlled.sol";
import {AbstractRouterStorage as ARSt} from "./AbstractRouterStorage.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

abstract contract AbstractRouter is AccessControlled {
  modifier onlyMakers() {
    require(makers(msg.sender), "Router/unauthorized");
    _;
  }
  modifier makersOrAdmin() {
    require(msg.sender == admin() || makers(msg.sender), "Router/unauthorized");
    _;
  }

  constructor(uint overhead) AccessControlled(msg.sender) {
    require(uint24(overhead) == overhead, "Router/overheadTooHigh");
    ARSt.get_storage().gas_overhead = overhead;
  }

  ///@notice getter for the `makers: addr => bool` mapping
  ///@param mkr the address of a maker
  ///@return true is `mkr` is bound to this router
  function makers(address mkr) public view returns (bool) {
    return ARSt.get_storage().makers[mkr];
  }

  ///@notice the amount of gas that will be added to `gasreq` of any maker contract using this router
  function gas_overhead() public view returns (uint) {
    return ARSt.get_storage().gas_overhead;
  }

  ///@notice pulls `amount` of `token`s from reserve to calling maker contract's balance
  ///@param token is the ERC20 managing the pulled asset
  ///@param reserve is the address identifying where `amount` of `token` should be pulled from
  ///@param amount of token the maker contract wishes to get
  ///@param strict when the calling maker contract accepts to receive more `token` than required (this may happen for gas optimization)
  function pull(
    IERC20 token,
    address reserve,
    uint amount,
    bool strict
  ) external onlyMakers returns (uint pulled) {
    uint buffer = token.balanceOf(msg.sender);
    if (buffer >= amount) {
      return 0;
    } else {
      pulled = __pull__({
        token: token,
        reserve: reserve,
        maker: msg.sender,
        amount: amount,
        strict: strict
      });
    }
  }

  ///@notice router-dependant implementation of the `pull` function
  function __pull__(
    IERC20 token,
    address reserve,
    address maker,
    uint amount,
    bool strict
  ) internal virtual returns (uint);

  ///@notice pushes assets from maker contract's balance to the specified reserve
  ///@param token is the asset the maker is pushing
  ///@param reserve is the address identifying where the transfered assets should be placed to
  ///@param amount is the amount of asset that should be transfered from the calling maker contract
  function push(
    IERC20 token,
    address reserve,
    uint amount
  ) external onlyMakers {
    __push__({
      token: token,
      reserve: reserve,
      maker: msg.sender,
      amount: amount
    });
  }

  ///@notice router-dependant implementation of the `push` function
  function __push__(
    IERC20 token,
    address reserve,
    address maker,
    uint amount
  ) internal virtual;

  ///@notice gas saving implementation of an iterative `push`
  function flush(IERC20[] calldata tokens, address reserve)
    external
    onlyMakers
  {
    for (uint i = 0; i < tokens.length; i++) {
      uint amount = tokens[i].balanceOf(msg.sender);
      if (amount > 0) {
        __push__(tokens[i], reserve, msg.sender, amount);
      }
    }
  }

  ///@notice returns the amount of `token`s that can be made available for pulling by the maker contract
  ///@dev when this router is pulling from a lender, this must return the amount of asset that can be withdrawn from reserve
  ///@param token is the asset one wishes to know the balance of
  ///@param reserve is the address identifying the location of the assets
  function reserveBalance(IERC20 token, address reserve)
    external
    view
    virtual
    returns (uint);

  ///@notice withdraws `amount` of reserve tokens and sends them to `recipient`
  ///@dev this is called by maker's contract when originator wishes to withdraw funds from it.
  /// this function is necessary because the maker contract is agnostic w.r.t reserve management
  function withdrawToken(
    IERC20 token,
    address reserve,
    address recipient,
    uint amount
  ) public onlyMakers returns (bool) {
    return __withdrawToken__(token, reserve, recipient, amount);
  }

  ///@notice router-dependant implementation of the `withdrawToken` function
  function __withdrawToken__(
    IERC20 token,
    address reserve,
    address to,
    uint amount
  ) internal virtual returns (bool);

  ///@notice adds a maker contract address to the allowed callers of this router
  ///@dev this function is callable by router's admin to bootstrap, but later on an allowed maker contract can add another address
  function bind(address maker) public makersOrAdmin {
    ARSt.get_storage().makers[maker] = true;
  }

  ///@notice removes a maker contract address from the allowed callers of this router
  function unbind(address maker) public makersOrAdmin {
    ARSt.get_storage().makers[maker] = false;
  }

  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param reserve the reserve that requires asset pulling/pushing
  function checkList(IERC20 token, address reserve) external view {
    // checking basic requirement
    require(
      token.allowance(msg.sender, address(this)) > 0,
      "Router/NotApprovedByMakerContract"
    );
    __checkList__(token, reserve);
  }

  ///@notice router-dependent implementation of the `checkList` function
  function __checkList__(IERC20 token, address reserve) internal view virtual;

  ///@notice performs necessary approval to activate router function on a particular asset
  ///@param token the asset one wishes to use the router for
  function activate(IERC20 token) external makersOrAdmin {
    __activate__(token);
  }

  ///@notice router-dependent implementation of the `activate` function
  function __activate__(IERC20 token) internal virtual {
    token; //ssh
  }
}
