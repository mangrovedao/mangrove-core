// SPDX-License-Identifier:	BSD-2-Clause

//AbstractRouter.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity ^0.8.10;

import {AccessControlled} from "mgv_src/strategies/utils/AccessControlled.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

/// @title AbstractRouter
/// @notice Partial implementation and requirements for liquidity routers.

abstract contract AbstractRouter is AccessControlled {
  uint24 internal immutable ROUTER_GASREQ;
  mapping(address => bool) internal boundMakerContracts;

  ///@notice This modifier verifies that `msg.sender` an allowed caller of this router.
  modifier onlyBound() {
    require(isBound(msg.sender), "AccessControlled/Invalid");
    _;
  }

  ///@notice This modifier verifies that `msg.sender` is the admin or an allowed caller of this router.
  modifier boundOrAdmin() {
    require(msg.sender == admin() || isBound(msg.sender), "AccessControlled/Invalid");
    _;
  }

  ///@notice logging bound maker contracts
  event MakerBind(address indexed maker);
  event MakerUnbind(address indexed maker);

  ///@notice constructor for abstract routers.
  ///@param routerGasreq_ is the amount of gas that is required for this router to be able to perform a `pull` and a `push`.
  constructor(uint routerGasreq_) AccessControlled(msg.sender) {
    require(uint24(routerGasreq_) == routerGasreq_, "Router/gasreqTooHigh");
    ROUTER_GASREQ = uint24(routerGasreq_);
  }

  ///@notice getter for the `makers: addr => bool` mapping
  ///@param mkr the address of a maker contract
  ///@return true if `mkr` is authorized to call this router.
  function isBound(address mkr) public view returns (bool) {
    return boundMakerContracts[mkr];
  }

  ///@notice view for gas overhead of this router.
  ///@return overhead the added (overapproximated) gas cost of `push` and `pull`.
  function routerGasreq() public view returns (uint overhead) {
    return ROUTER_GASREQ;
  }

  ///@notice pulls liquidity from the reserve and sends it to the calling maker contract.
  ///@param token is the ERC20 managing the pulled asset
  ///@param reserveId identifies the fund owner (router implementation dependant).
  ///@param amount of `token` the maker contract wishes to pull from its reserve
  ///@param strict when the calling maker contract accepts to receive more funds from reserve than required (this may happen for gas optimization)
  function pull(IERC20 token, address reserveId, uint amount, bool strict) external onlyBound returns (uint pulled) {
    if (strict && amount == 0) {
      return 0;
    }
    pulled = __pull__({token: token, reserveId: reserveId, amount: amount, strict: strict});
  }

  ///@notice router-dependant implementation of the `pull` function
  function __pull__(IERC20 token, address reserveId, uint amount, bool strict) internal virtual returns (uint);

  ///@notice pushes assets from calling's maker contract to a reserve
  ///@param token is the asset the maker is pushing
  ///@param reserveId determines the location of the reserve (router implementation dependant).
  ///@param amount is the amount of asset that should be transferred from the calling maker contract
  ///@return pushed fraction of `amount` that was successfully pushed to reserve.
  function push(IERC20 token, address reserveId, uint amount) external onlyBound returns (uint pushed) {
    if (amount == 0) {
      return 0;
    }
    pushed = __push__({token: token, reserveId: reserveId, amount: amount});
  }

  ///@notice router-dependant implementation of the `push` function
  function __push__(IERC20 token, address reserveId, uint amount) internal virtual returns (uint);

  ///@notice iterative `push` for the whole balance in a single call
  function flush(IERC20[] calldata tokens, address reserveId) external onlyBound {
    for (uint i = 0; i < tokens.length; ++i) {
      uint amount = tokens[i].balanceOf(msg.sender);
      if (amount > 0) {
        require(__push__(tokens[i], reserveId, amount) == amount, "router/pushFailed");
      }
    }
  }

  ///@notice adds a maker contract address to the allowed makers of this router
  ///@dev this function is callable by router's admin to bootstrap, but later on an allowed maker contract can add another address
  ///@param makerContract the maker contract address
  function bind(address makerContract) public onlyAdmin {
    boundMakerContracts[makerContract] = true;
    emit MakerBind(makerContract);
  }

  ///@notice removes a maker contract address from the allowed makers of this router
  ///@param makerContract the maker contract address
  function _unbind(address makerContract) internal {
    boundMakerContracts[makerContract] = false;
    emit MakerUnbind(makerContract);
  }

  ///@notice removes `msg.sender` from the allowed makers of this router
  function unbind() external onlyBound {
    _unbind(msg.sender);
  }

  ///@notice removes a makerContract from the allowed makers of this router
  function unbind(address maker) external onlyAdmin {
    _unbind(maker);
  }

  ///@notice allows a makerContract to verify it is ready to use `this` router for a particular reserve
  ///@dev `checkList` returns normally if all needed approval are strictly positive. It reverts otherwise with a reason.
  ///@param token is the asset (and possibly its overlyings) whose approval must be checked
  ///@param reserveId of the tokens that are being pulled
  function checkList(IERC20 token, address reserveId) external view {
    require(isBound(msg.sender), "Router/callerIsNotBoundToRouter");
    // checking maker contract has approved this for token transfer (in order to push to reserve)
    require(token.allowance(msg.sender, address(this)) > 0, "Router/NotApprovedByMakerContract");
    // pulling on behalf of `reserveId` might require a special approval (e.g if `reserveId` is some account on a protocol).
    __checkList__(token, reserveId);
  }

  ///@notice router-dependent additional checks
  function __checkList__(IERC20 token, address reserveId) internal view virtual;

  ///@notice performs necessary approval to activate router function on a particular asset
  ///@param token the asset one wishes to use the router for
  function activate(IERC20 token) external boundOrAdmin {
    __activate__(token);
  }

  ///@notice router-dependent implementation of the `activate` function
  function __activate__(IERC20 token) internal virtual {
    token; //ssh
  }

  ///@notice Balance of a reserve
  ///@param token the asset one wishes to know the balance of
  ///@param reserveId the identifier of the reserve
  function balanceOfReserve(IERC20 token, address reserveId) public view virtual returns (uint);
}
