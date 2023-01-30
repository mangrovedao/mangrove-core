// SPDX-License-Identifier:	BSD-2-Clause

// AaveKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs} from "./abstract/CoreKandel.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {OfferType} from "./abstract/Trade.sol";

contract AaveKandel is CoreKandel {
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, AavePooledRouter router_)
    CoreKandel(mgv, base, quote, gasreq, gasprice, router_)
  {}

  function pooledRouter() private view returns (AavePooledRouter) {
    return AavePooledRouter(address(router()));
  }

  ///@notice external wrapper for `_depositFunds`
  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) external {
    // transfer funds from caller to this
    _depositFunds(tokens, amounts);
    // push funds on the router (and supply on AAVE)
    pooledRouter().pushAndSupply(tokens, amounts, admin());
  }

  ///@notice external wrapper for `_withdrawFunds`
  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient) external onlyAdmin {
    for (uint i; i < tokens.length; i++) {
      pooledRouter().pull(tokens[i], admin(), amounts[i], true);
    }
    _withdrawFunds(tokens, amounts, recipient);
  }

  function reserveBalance(IERC20 token) private view returns (uint) {
    return pooledRouter().ownerBalance(token, admin());
  }

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return pending_ the pending amount
  function pending(OfferType ba) external view returns (int pending_) {
    IERC20 token = outboundOfOfferType(ba);
    pending_ = int(reserveBalance(token)) - int(offeredVolume(ba));
  }
}
