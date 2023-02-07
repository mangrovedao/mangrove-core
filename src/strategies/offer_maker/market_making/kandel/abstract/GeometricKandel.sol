// SPDX-License-Identifier:	BSD-2-Clause

// GeometricKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvLib, MgvStructs} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {TradesBaseQuotePair} from "./TradesBaseQuotePair.sol";
import {CoreKandel} from "./CoreKandel.sol";

abstract contract GeometricKandel is CoreKandel, TradesBaseQuotePair {
  ///@notice the parameters for Geometric Kandel have been set.
  event SetGeometricParams(uint spread, uint ratio);

  ///@notice Geometric Kandel parameters
  ///@param gasprice the gasprice to use for offers
  ///@param gasreq the gasreq to use for offers
  ///@param ratio of price progression (`2**16 > ratio >= 10**PRECISION`) expressed with `PRECISION` decimals, so geometric ratio is `ratio/10**PRECISION`
  ///@param compoundRateBase percentage of the spread that is to be compounded for base, expressed with `PRECISION` decimals (`compoundRateBase <= 10**PRECISION`). Real compound rate for base is `compoundRateBase/10**PRECISION`
  ///@param compoundRateQuote percentage of the spread that is to be compounded for quote, expressed with `PRECISION` decimals (`compoundRateQuote <= 10**PRECISION`). Real compound rate for quote is `compoundRateQuote/10**PRECISION`
  ///@param spread in amount of price slots to jump for posting dual offer. Must be less than or equal to 8.
  ///@param pricePoints the number of price points for the Kandel instance.
  struct Params {
    uint16 gasprice;
    uint24 gasreq;
    uint16 ratio;
    uint16 compoundRateBase;
    uint16 compoundRateQuote;
    uint8 spread;
    uint8 pricePoints;
  }

  Params public params;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    CoreKandel(mgv, gasreq, reserveId)
    TradesBaseQuotePair(base, quote)
  {
    setGasprice(gasprice);
  }

  /// @notice records gasprice in params
  function setGasprice(uint gasprice) public onlyAdmin {
    uint16 gasprice_ = uint16(gasprice);
    require(gasprice_ == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = gasprice_;
    // params.gasreq = gasreq_;
    emit SetGasprice(gasprice_);
  }

  /// @notice records gasreq (including router's gasreq) in params
  function setGasreq(uint gasreq) public onlyAdmin {
    uint24 gasreq_ = uint24(gasreq);
    require(gasreq_ == gasreq, "Kandel/gasreqTooHigh");
    params.gasreq = gasreq_;
    emit SetGasreq(gasreq_);
  }

  function setParams(Params calldata newParams) private {
    Params memory oldParams = params;

    if (oldParams.pricePoints != newParams.pricePoints) {
      setLength(newParams.pricePoints);
      params.pricePoints = newParams.pricePoints;
    }

    bool geometricChanged = false;
    if (oldParams.ratio != newParams.ratio) {
      require(newParams.ratio >= 10 ** PRECISION, "Kandel/invalidRatio");
      params.ratio = newParams.ratio;
      geometricChanged = true;
    }
    if (oldParams.spread != newParams.spread) {
      require(newParams.spread > 0 && newParams.spread <= 8, "Kandel/invalidSpread");
      params.spread = newParams.spread;
      geometricChanged = true;
    }

    if (geometricChanged) {
      emit SetGeometricParams(newParams.spread, newParams.ratio);
    }

    if (newParams.gasprice != 0 && newParams.gasprice != oldParams.gasprice) {
      setGasprice(newParams.gasprice);
    }

    if (newParams.gasreq != 0 && newParams.gasreq != oldParams.gasreq) {
      setGasreq(newParams.gasreq);
    }

    if (
      oldParams.compoundRateBase != newParams.compoundRateBase
        || oldParams.compoundRateQuote != newParams.compoundRateQuote
    ) {
      setCompoundRates(newParams.compoundRateBase, newParams.compoundRateQuote);
    }
  }

  ///@notice set the compound rates. It will take effect for future compounding.
  ///@param compoundRateBase the compound rate for base.
  ///@param compoundRateQuote the compound rate for quote.
  ///@dev For low compound rates Kandel can end up with everything as pending and nothing offered.
  ///@dev To avoid this, then for equal compound rates `C` then $C >= 1/(sqrt(ratio^spread)+1)$.
  ///@dev With one rate being 0 and the other 1 the amount earned from the spread will accumulate as pending
  ///@dev for the token at 0 compounding and the offered volume will stay roughly static (modulo rounding).
  function setCompoundRates(uint compoundRateBase, uint compoundRateQuote) public mgvOrAdmin {
    require(compoundRateBase <= 10 ** PRECISION, "Kandel/invalidCompoundRateBase");
    require(compoundRateQuote <= 10 ** PRECISION, "Kandel/invalidCompoundRateQuote");
    emit SetCompoundRates(compoundRateBase, compoundRateQuote);
    params.compoundRateBase = uint16(compoundRateBase);
    params.compoundRateQuote = uint16(compoundRateQuote);
  }

  /// @param baDual the dual offer type.
  /// @param memoryParams the Kandel params.
  /// @return compoundRate to use for the gives of the offer type. Asks give base so this would be the `compoundRateBase`, and vice versa.
  function compoundRateForDual(OfferType baDual, Params memory memoryParams) private pure returns (uint compoundRate) {
    compoundRate = uint(baDual == OfferType.Ask ? memoryParams.compoundRateBase : memoryParams.compoundRateQuote);
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param lastBidIndex the index after which offer should be an ask. First index will never be an ask, either a bid or not published.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param depositTokens tokens to deposit.
  ///@param depositAmounts amounts to deposit for the tokens.
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different ratio, pricePoints, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint lastBidIndex,
    Params calldata parameters,
    IERC20[] calldata depositTokens,
    uint[] calldata depositAmounts
  ) external payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(depositTokens, depositAmounts);

    populateChunkInternal(distribution, pivotIds, lastBidIndex);
  }

  ///@notice internal version does not check onlyAdmin
  function populateChunkInternal(Distribution calldata distribution, uint[] calldata pivotIds, uint lastBidIndex)
    internal
  {
    populateChunk(distribution, pivotIds, lastBidIndex, params.gasreq, params.gasprice);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple transactions are needed to split initialization due to gas cost.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices.
  ///@param pivotIds the pivot to be used for the offer.
  ///@param lastBidIndex the index after which offer should be an ask. First index will never be an ask, either a bid or not published.
  function populateChunk(Distribution calldata distribution, uint[] calldata pivotIds, uint lastBidIndex)
    external
    onlyAdmin
  {
    populateChunk(distribution, pivotIds, lastBidIndex, params.gasreq, params.gasprice);
  }

  function dualWantsGivesOfOffer(
    OfferType baDual,
    uint offerGives,
    MgvLib.SingleOrder calldata order,
    Params memory memoryParams
  ) internal pure returns (uint wants, uint gives) {
    // computing gives/wants for dual offer
    // we verify we cannot overflow if PRECISION = 4
    // spread:8
    uint spread = uint(memoryParams.spread);
    // compoundRate:16
    uint compoundRate = compoundRateForDual(baDual, memoryParams);
    // params.ratio:16, and we want r:128, so spread<=8. r:16*8:128
    uint r = uint(memoryParams.ratio) ** spread;
    // log2(10) = 3.32 => p:PRECISION*3.32
    uint p = 10 ** PRECISION;
    // (a) max (p - compoundRate): 4*log2(10) (for compoundRate = 0)
    // (b) p**spread: 8*4*log2(10) < 107
    // (a) * (b) : 32*log2(10) + 4*log2(10) = 36*log2(10) < 120
    // max (compoundRate * r) : 4*log2(10)+128 < 142 (for compoundRate = 10**4)
    // max(numerator) : 96 + 142 = 238 (for compoundRate = 10**4)
    // r:128*p:4*log2(10) : 128 + 4*log2(10) = 142 and gives:96 as it should
    gives = (order.gives * ((p - compoundRate) * p ** spread + compoundRate * r)) / (r * p);

    // adding to gives what the offer was already giving so gives could be greater than 2**96
    // gives:97
    gives += offerGives;
    if (uint96(gives) != gives) {
      // this should not be reached under normal circumstances unless strat is posting on top of an existing offer with an abnormal volume
      // to prevent gives to be too high, we let the surplus be pending
      gives = type(uint96).max;
    }
    // adjusting wants to price:
    // gives * r : 96 + 128 = 224 so order.wants must be < 2**32 to completely avoid overflow.
    // However, order.wants is often larger, but gives * r often does not use that many bits.
    // So we check whether the full precision can be used and only if not then we use less precision.
    uint givesR = gives * r;
    if (uint160(givesR) == givesR) {
      // using max precision
      wants = (order.wants * givesR) / (order.gives * (p ** spread));
    } else {
      wants = order.wants * (givesR / (order.gives * (p ** spread)));
    }
    // wants is higher than order.wants
    // this may cause wants to be higher than 2**96 allowed by Mangrove (for instance if one needs many quotes to buy sell base tokens)
    // so we adjust the price so as to want an amount of tokens that mangrove will accept.
    if (uint96(wants) != wants) {
      gives = (type(uint96).max * gives) / wants;
      wants = type(uint96).max;
    }
  }

  ///@notice returns the destination index to transport received liquidity to - a better (for Kandel) price index for the offer type.
  ///@param ba the offer type to transport to
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  function transportDestination(OfferType ba, uint index, uint step, uint pricePoints)
    internal
    pure
    returns (uint better)
  {
    if (ba == OfferType.Ask) {
      better = index + step;
      if (better >= pricePoints) {
        better = pricePoints - 1;
      }
    } else {
      if (index >= step) {
        better = index - step;
      }
      // else better is 0
    }
  }

  ///@inheritdoc CoreKandel
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OfferType baDual, uint dualOfferId, uint dualIndex, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;

    if (index == 0) {
      emit AllAsks();
    }
    if (index == memoryParams.pricePoints - 1) {
      emit AllBids();
    }
    baDual = dual(ba);

    dualIndex = transportDestination(baDual, index, memoryParams.spread, memoryParams.pricePoints);

    dualOfferId = offerIdOfIndex(baDual, dualIndex);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(baDual);
    args.outbound_tkn = outbound;
    args.inbound_tkn = inbound;
    MgvStructs.OfferPacked offer = MGV.offers(address(outbound), address(inbound), dualOfferId);

    // computing gives/wants for dual offer
    // At least: gives = order.gives/ratio and wants is then order.wants
    // At most: gives = order.gives and wants is adapted to match the price
    (args.wants, args.gives) = dualWantsGivesOfOffer(baDual, offer.gives(), order, memoryParams);
    // args.fund = 0; the offers are already provisioned
    // posthook should not fail if unable to post offers, we capture the error as incidents
    args.noRevert = true;
    args.gasprice = memoryParams.gasprice;
    args.gasreq = memoryParams.gasreq;
    args.pivotId = offer.gives() > 0 ? offer.next() : 0;
    return (baDual, dualOfferId, dualIndex, args);
  }
}
