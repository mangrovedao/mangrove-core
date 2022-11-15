// SPDX-License-Identifier:	BSD-2-Clause

//AbstractRouter.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

pragma abicoder v2;

import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";
import {AbstractRouterStorage as ARSt} from "./AbstractRouterStorage.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

/// @title AbstractRouter
/// @notice Partial implementation and requirements for liquidity routers.

abstract contract AbstractRouter is AccessControlled {
  uint24 immutable ROUTER_GASREQ;

  ///@notice This modifier verifies that `msg.sender` an allowed caller of this router.
  modifier onlyMakers() {
    require(makers(msg.sender), "Router/unauthorized");
    _;
  }

  ///@notice This modifier verifies that `msg.sender` is the admin or an allowed caller of this router.
  modifier makersOrAdmin() {
    require(msg.sender == admin() || makers(msg.sender), "Router/unauthorized");
    _;
  }

  ///@notice constructor for abstract routers.
  ///@param routerGasreq_ is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  constructor(uint routerGasreq_) AccessControlled(msg.sender) {
    require(uint24(routerGasreq_) == routerGasreq_, "Router/gasreqTooHigh");
    ROUTER_GASREQ = uint24(routerGasreq_);
  }

  ///@notice getter for the `makers: addr => bool` mapping
  ///@param mkr the address of a maker
  ///@return true if `mkr` is authorized to call this router.
  function makers(address mkr) public view returns (bool) {
    return ARSt.getStorage().makers[mkr];
  }

  ///@notice view for gas overhead of this router.
  ///@return overhead the added (overapproximated) gas cost of `push` and `pull`.
  function routerGasreq() public view returns (uint overhead) {
    return ROUTER_GASREQ;
  }

  ///@notice pulls liquidity from an offer maker's reserve to `msg.sender`'s balance
  ///@param token is the ERC20 managing the pulled asset
  ///@param reserve where `amount` of `token` should be pulled from
  ///@param amount of `token` the maker contract wishes to get
  ///@param strict when the calling maker contract accepts to receive more `token` than required (this may happen for gas optimization)
  function pull(IERC20 token, address reserve, uint amount, bool strict) external onlyMakers returns (uint pulled) {
    pulled = __pull__({token: token, reserve: reserve, maker: msg.sender, amount: amount, strict: strict});
  }

  ///@notice router-dependant implementation of the `pull` function
  function __pull__(IERC20 token, address reserve, address maker, uint amount, bool strict)
    internal
    virtual
    returns (uint);

  ///@notice pushes assets from maker contract's balance to the specified reserve
  ///@param token is the asset the maker is pushing
  ///@param reserve is the address identifying where the transferred assets should be placed to
  ///@param amount is the amount of asset that should be transferred from the calling maker contract
  ///@return pushed fraction of `amount` that was successfully pushed to reserve.
  function push(IERC20 token, address reserve, uint amount) external onlyMakers returns (uint pushed) {
    return __push__({token: token, reserve: reserve, maker: msg.sender, amount: amount});
  }

  ///@notice router-dependant implementation of the `push` function
  function __push__(IERC20 token, address reserve, address maker, uint amount) internal virtual returns (uint);

  ///@notice iterative `push` in a single call
  function flush(IERC20[] calldata tokens, address reserve) external onlyMakers {
    for (uint i = 0; i < tokens.length; i++) {
      uint amount = tokens[i].balanceOf(msg.sender);
      if (amount > 0) {
        require(__push__(tokens[i], reserve, msg.sender, amount) == amount, "router/pushFailed");
      }
    }
  }

  ///@notice returns the amount of `token`s that can be made available for pulling by the maker contract
  ///@dev when this router is pulling from a lender, this must return the amount of asset that can be withdrawn from reserve
  ///@param token is the asset one wishes to know the balance of
  ///@param reserve is the address identifying the location of the assets
  function reserveBalance(IERC20 token, address reserve) external view virtual returns (uint);

  ///@notice withdraws `amount` of tokens from `reserve` and sends them to `recipient`
  ///@dev this is called by maker's contract when offer maker wishes to withdraw funds from it.
  ///@param token is the asset one wishes to withdraw
  ///@param reserve is the location of the assets
  ///@param recipient is address receiving the tokens
  ///@param amount is the amount of asset that should be withdrawn
  function withdrawToken(IERC20 token, address reserve, address recipient, uint amount)
    public
    onlyMakers
    returns (bool)
  {
    return __withdrawToken__(token, reserve, recipient, amount);
  }

  ///@notice router-dependant implementation of the `withdrawToken` function
  function __withdrawToken__(IERC20 token, address reserve, address recipient, uint amount)
    internal
    virtual
    returns (bool);

  ///@notice adds a maker contract address to the allowed makers of this router
  ///@dev this function is callable by router's admin to bootstrap, but later on an allowed maker contract can add another address
  ///@param maker the maker contract address
  function bind(address maker) public onlyAdmin {
    ARSt.getStorage().makers[maker] = true;
  }

  ///@notice removes a maker contract address from the allowed makers of this router
  ///@param maker the maker contract address
  function unbind(address maker) public onlyAdmin {
    ARSt.getStorage().makers[maker] = false;
  }

  ///@notice removes `msg.sender` from the allowed makers of this router
  function unbind() external onlyMakers {
    ARSt.getStorage().makers[msg.sender] = false;
  }

  ///@notice verifies all required approval involving `this` router (either as a spender or owner)
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param reserve the reserve that requires asset pulling/pushing
  function checkList(IERC20 token, address reserve) external view {
    // checking maker contract has approved this for token transfer (in order to push to reserve)
    require(token.allowance(msg.sender, address(this)) > 0, "Router/NotApprovedByMakerContract");
    // pulling from reserve might require a special approval if `reserve` is some account on a protocol (e.g a lender) which requires a custom redeem call.
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
