// SPDX-License-Identifier:	BSD-2-Clause

// OfferProxy.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import "mgv_src/strategies/offer_forwarder/OfferForwarder.sol";
import "mgv_src/strategies/routers/AaveDeepRouter.sol";

contract OfferProxy is OfferForwarder {
  bytes32 public constant NAME = "OfferProxy";

  constructor(address _addressesProvider, IMangrove mgv, address deployer) OfferForwarder(mgv, msg.sender) {
    // OfferForwarder has a SimpleRouter by default
    // replacing this router with an Aave one
    AaveDeepRouter _router = new AaveDeepRouter(_addressesProvider, 0, 2);
    // adding `this` contract to the authorized makers of this router (this will work because `this` contract is the admin/deployer of `router_`)
    _router.bind(address(this));
    // setting aave router to be the router of this contract (allowed since this contract is admin of the router)
    setRouter(_router);
    // changing router admin for further modification
    _router.setAdmin(deployer);
    if (deployer != msg.sender) {
      setAdmin(deployer);
    }
  }
}
