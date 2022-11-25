// SPDX-License-Identifier:	BSD-2-Clause

// ForwarderTester.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {OfferForwarder, IMangrove, IERC20, AbstractRouter} from "./OfferForwarder.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {ITesterContract} from "mgv_src/strategies/interfaces/ITesterContract.sol";

contract ForwarderTester is OfferForwarder, ITesterContract {
  mapping(address => address) public reserves;

  constructor(IMangrove mgv, address deployer) OfferForwarder(mgv, deployer) {}

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
    return router_.reserveBalance(token, makerReserve);
  }

  function internal_addOwner(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, address owner, uint leftover)
    external
  {
    addOwner(outbound_tkn, inbound_tkn, offerId, owner, leftover);
  }

  function internal__put__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __put__(amount, order);
  }

  function internal__get__(uint amount, MgvLib.SingleOrder calldata order) external returns (uint) {
    return __get__(amount, order);
  }

  function internal__posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    external
    returns (bytes32)
  {
    return __posthookFallback__(order, result);
  }
}
