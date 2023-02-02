// SPDX-License-Identifier:	BSD-2-Clause

// AaveKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {
  MangroveOffer, CoreKandel, IMangrove, IERC20, AbstractKandel, MgvLib, MgvStructs
} from "./abstract/CoreKandel.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {OfferType} from "./abstract/Trade.sol";

contract AaveKandel is CoreKandel {
  bytes32 constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address owner)
    CoreKandel(mgv, base, quote, gasreq, gasprice, owner)
  {}

  ///@dev returns the router as an Aave router
  function pooledRouter() private view returns (AavePooledRouter) {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "AaveKandel/uninitialized");
    return AavePooledRouter(address(router_));
  }

  function initialize(AavePooledRouter router_) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`.
    __activate__(BASE);
    __activate__(QUOTE);
  }

  ///@dev external wrapper for `_depositFunds`
  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) external override {
    // transfer funds from caller to this
    _depositFunds(tokens, amounts);
    // push funds on the router (and supply on AAVE)
    pooledRouter().pushAndSupply(tokens, amounts, admin());
  }

  ///@dev external wrapper for `_withdrawFunds`
  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient)
    external
    override
    onlyAdmin
  {
    for (uint i; i < tokens.length; i++) {
      pooledRouter().pull(tokens[i], admin(), amounts[i], true);
    }
    _withdrawFunds(tokens, amounts, recipient);
  }

  ///@notice returns the amount of tokens of the router's balance that belong to this contract
  function reserveBalance(IERC20 token) public view override returns (uint) {
    return pooledRouter().ownerBalance(token, admin());
  }

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return pending_ the pending amount
  /// @dev Gas costly function, better suited for off chain calls.
  function pending(OfferType ba) external view override returns (int pending_) {
    IERC20 token = outboundOfOfferType(ba);
    pending_ = int(reserveBalance(token)) - int(offeredVolume(ba));
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return (IERC20(order.outbound_tkn).balanceOf(address(router())) > order.wants) ? IS_FIRST_PULLER : makerData;
  }

  ///@notice overrides and replaces Direct's posthook in order to push and supply on AAVE with a single call when offer logic is the first to pull funds from AAVE
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    if (makerData == IS_FIRST_PULLER) {
      IERC20[] memory tokens = new IERC20[](2);
      tokens[0] = IERC20(order.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
      tokens[1] = IERC20(order.inbound_tkn); // flushing liquidity brought by taker
      uint[] memory amounts = new uint[](2);
      amounts[0] = IERC20(order.outbound_tkn).balanceOf(address(this));
      amounts[1] = IERC20(order.inbound_tkn).balanceOf(address(this));

      pooledRouter().pushAndSupply(tokens, amounts, admin());
      // reposting offer residual if any
      return MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      return super.__posthookSuccess__(order, makerData);
    }
  }
}
