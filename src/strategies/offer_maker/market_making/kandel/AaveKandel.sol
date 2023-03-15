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
import {IATokenIsh} from "mgv_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract AaveKandel is GeometricKandel {
  bytes32 internal constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  event SetPoolTarget(OfferType ba, uint target);

  constructor(
    IMangrove mgv,
    IERC20 base,
    IERC20 quote,
    uint gasreq,
    uint gasprice,
    address reserveId,
    uint poolTargetBase,
    uint poolTargetQuote
  ) GeometricKandel(mgv, base, quote, gasreq, gasprice, reserveId) {
    require(uint24(poolTargetBase) == poolTargetBase, "AaveKandel/targetBaseOverflow");
    require(uint24(poolTargetQuote) == poolTargetQuote, "AaveKandel/targetQuoteOverflow");
    params.poolTargetBase = uint24(poolTargetBase);
    params.poolTargetQuote = uint24(poolTargetQuote);
    // one makes sure it is not possible to deploy an AAVE kandel on aTokens
    // allowing Kandel to deposit aUSDC for instance would conflict with other Kandel instances bound to the same router
    // and trading on USDC.
    // The code below verifies that neither base nor quote are official AAVE overlyings.
    bool isOverlying;
    try IATokenIsh(address(base)).UNDERLYING_ASSET_ADDRESS() returns (address) {
      isOverlying = true;
    } catch {}
    try IATokenIsh(address(quote)).UNDERLYING_ASSET_ADDRESS() returns (address) {
      isOverlying = true;
    } catch {}
    require(!isOverlying, "AaveKandel/cannotTradeAToken");
  }

  function setPoolTarget(OfferType ba, uint24 target) external onlyAdmin {
    if (ba == OfferType.Ask) {
      params.poolTargetBase = target;
    } else {
      params.poolTargetQuote = target;
    }
    emit SetPoolTarget(ba, target);
  }

  ///@dev returns the router as an Aave router
  function pooledRouter() private view returns (AavePooledRouter) {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "AaveKandel/uninitialized");
    return AavePooledRouter(address(router_));
  }

  function initialize(AavePooledRouter router_) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`. We call __activate__ instead of activate just to save gas.
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(offerGasreq());
  }

  ///@inheritdoc AbstractKandel
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds on the router (and supply on AAVE)
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = BASE;
    tokens[1] = QUOTE;
    uint[] memory amounts = new uint[](2);
    amounts[0] = baseAmount;
    amounts[1] = quoteAmount;
    pooledRouter().pushAndSupply(tokens, amounts, RESERVE_ID);
  }

  ///@inheritdoc AbstractKandel
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) public override onlyAdmin {
    if (baseAmount != 0) {
      pooledRouter().withdraw(BASE, RESERVE_ID, baseAmount);
    }
    if (quoteAmount != 0) {
      pooledRouter().withdraw(QUOTE, RESERVE_ID, quoteAmount);
    }
    super.withdrawFunds(baseAmount, quoteAmount, recipient);
  }

  ///@inheritdoc AbstractKandel
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    balance = super.reserveBalance(ba) + pooledRouter().balanceOfReserve(token, RESERVE_ID);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    uint localBuffer = IERC20(order.outbound_tkn).balanceOf(address(this));
    return (
      localBuffer < order.wants && IERC20(order.outbound_tkn).balanceOf(address(router())) + localBuffer < order.wants
    ) ? IS_FIRST_PULLER : makerData;
  }

  function maintainBuffer(IERC20 token, uint poolTarget) internal view returns (uint toPush) {
    uint bufferBalance = token.balanceOf(address(this));
    toPush = (bufferBalance * poolTarget) / 10 ** PRECISION;
  }

  ///@notice overrides and replaces Direct's posthook in order to push and supply on AAVE with a single call when offer logic is the first to pull funds from AAVE
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repostStatus)
  {
    // handles dual offer posting
    transportSuccessfulOrder(order);
    Params memory memoryParams = params;

    // handles pushing back liquidity to the router
    if (makerData == IS_FIRST_PULLER) {
      uint baseToPush = maintainBuffer(BASE, memoryParams.poolTargetBase);
      uint quoteToPush = maintainBuffer(QUOTE, memoryParams.poolTargetQuote);
      IERC20[] memory tokens = new IERC20[](2);
      uint[] memory amounts = new uint[](2);

      tokens[0] = BASE;
      tokens[1] = QUOTE;
      amounts[0] = baseToPush;
      amounts[1] = quoteToPush;
      pooledRouter().pushAndSupply(tokens, amounts, RESERVE_ID);

      // handles residual reposting - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // handles residual reposting - call super to let flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
  }
}
