// SPDX-License-Identifier:	BSD-2-Clause

// AaveKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

contract AaveKandel is GeometricKandel {
  bytes32 constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    GeometricKandel(mgv, base, quote, gasreq, gasprice, reserveId)
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
    setGasreq(offerGasreq());
  }

  ///@inheritdoc AbstractKandel
  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) public override {
    // transfer funds from caller to this
    super.depositFunds(tokens, amounts);
    // push funds on the router (and supply on AAVE)
    pooledRouter().pushAndSupply(tokens, amounts, RESERVE_ID);
  }

  ///@inheritdoc AbstractKandel
  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient)
    public
    override
    onlyAdmin
  {
    for (uint i; i < tokens.length; i++) {
      if (amounts[i] != 0) {
        pooledRouter().pull(tokens[i], RESERVE_ID, amounts[i], true);
      }
    }
    super.withdrawFunds(tokens, amounts, recipient);
  }

  ///@notice returns the amount of tokens of the router's balance that belong to this contract
  ///@inheritdoc AbstractKandel
  function reserveBalance(IERC20 token) public view override returns (uint) {
    return pooledRouter().balanceOfId(token, RESERVE_ID);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return (IERC20(order.outbound_tkn).balanceOf(address(router())) < order.wants) ? IS_FIRST_PULLER : makerData;
  }

  ///@notice overrides and replaces Direct's posthook in order to push and supply on AAVE with a single call when offer logic is the first to pull funds from AAVE
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repostStatus)
  {
    // handle dual offer posting
    bool isOutOfRange = transportSuccessfulOrder(order);

    // handles pushing back liquidity to the router
    if (makerData == IS_FIRST_PULLER) {
      // if first puller, then router should deposit liquidity on AAVE
      IERC20[] memory tokens = new IERC20[](2);
      tokens[0] = BASE; // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
      tokens[1] = QUOTE; // flushing liquidity brought by taker
      uint[] memory amounts = new uint[](2);
      amounts[0] = BASE.balanceOf(address(this));
      amounts[1] = QUOTE.balanceOf(address(this));

      pooledRouter().pushAndSupply(tokens, amounts, RESERVE_ID);
      // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // reposting offer residual if any - call super to let flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
    if (isOutOfRange) {
      logOutOfRange(order, repostStatus);
    }
  }
}
