// SPDX-License-Identifier:	BSD-2-Clause

// DirectTester.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {IMangrove, AbstractRouter, OfferMaker, IERC20} from "./OfferMaker.sol";
import {ITesterContract} from "mgv_src/strategies/interfaces/ITesterContract.sol";

contract DirectTester is ITesterContract, OfferMaker {
  mapping(address => address) public reserves;

  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, AbstractRouter router_, address deployer) OfferMaker(mgv, router_, deployer) {}

  // giving mutable reserve power to test contract with different kinds of reserve
  function setReserve(address maker, address reserve) external onlyAdmin {
    reserves[maker] = reserve;
  }

  function __reserve__(address maker) internal view virtual override returns (address) {
    return reserves[maker] == address(0) ? maker : reserves[maker];
  }

  function tokenBalance(IERC20 token, address maker) external view override returns (uint) {
    AbstractRouter router_ = router();
    address makerReserve = reserve(maker);
    return router_ == NO_ROUTER ? token.balanceOf(makerReserve) : router_.reserveBalance(token, makerReserve);
  }
}
