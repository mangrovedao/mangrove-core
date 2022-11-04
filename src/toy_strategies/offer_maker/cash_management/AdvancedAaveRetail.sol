// SPDX-License-Identifier:	BSD-2-Clause

// AdvancedAaveRetail.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import "mgv_src/strategies/offer_maker/OfferMaker.sol";
import "mgv_src/strategies/routers/AaveDeepRouter.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";

contract AdvancedAaveRetail is OfferMaker {
  bytes32 public constant NAME = "AdvancedAaveRetail";

  constructor(IMangrove mgv, address _addressesProvider, address deployer)
    OfferMaker(mgv, new AaveDeepRouter(_addressesProvider, 0, 2), deployer)
  {
    // Router reserve is by default `router.address`
    // use `setReserve(addr)` to change this
    router().setAdmin(deployer);
    if (deployer != msg.sender) {
      setAdmin(deployer);
    }
  }

  // overriding put to leverage taker's liquidity on aave
  // this function will deposit incoming liquidity to increase borrow power during trade
  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal override returns (uint missingPut) {
    push(IERC20(order.inbound_tkn), amount);
    return 0;
  }
}
