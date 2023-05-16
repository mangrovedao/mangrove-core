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
import {MgvLib} from "mgv_src/MgvLib.sol";

contract DirectTester is ITesterContract, OfferMaker {
  mapping(address => address) public reserves;
  bytes32 constant retdata = "lastlook/testdata";

  // router_ needs to bind to this contract
  // since one cannot assume `this` is admin of router, one cannot do this here in general
  constructor(IMangrove mgv, AbstractRouter router_, address deployer, uint gasreq)
    OfferMaker(mgv, router_, deployer, gasreq, deployer) // setting reserveId = deployer by default
  {}

  function tokenBalance(IERC20 token, address reserveId) external view override returns (uint) {
    AbstractRouter router_ = router();
    return router_ == NO_ROUTER ? token.balanceOf(address(this)) : router_.balanceOfReserve(token, reserveId);
  }

  function __lastLook__(MgvLib.SingleOrder calldata) internal virtual override returns (bytes32) {
    return retdata;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 maker_data)
    internal
    override
    returns (bytes32 data)
  {
    data = super.__posthookSuccess__(order, maker_data);
    require(
      data == REPOST_SUCCESS || data == COMPLETE_FILL,
      (data == "mgv/insufficientProvision")
        ? "mgv/insufficientProvision"
        : (data == "mgv/writeOffer/density/tooLow" ? "mgv/writeOffer/density/tooLow" : "posthook/failed")
    );
  }
}
