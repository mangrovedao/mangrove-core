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
import {CoreKandel} from "./CoreKandel.sol";
import {AbstractKandel} from "./AbstractKandel.sol";

///@title Adds a geometric price progression to a `CoreKandel` strat without storing prices for individual price points.
abstract contract GeometricKandel is CoreKandel {
  ///@notice `compoundRateBase`, and `compoundRateQuote` have PRECISION decimals, and ditto for GeometricKandel's `ratio`.
  ///@notice setting PRECISION higher than 5 will produce overflow in limit cases for GeometricKandel.
  uint public constant PRECISION = 5;

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
    uint24 ratio; // max ratio is 2*10**5
    uint24 compoundRateBase; // max compoundRate is 10**5
    uint24 compoundRateQuote;
    uint8 spread;
    uint8 pricePoints;
  }

  /// Storage of the parameters for the strat.
  Params public params;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    CoreKandel(mgv, base, quote, gasreq, reserveId)
  {
    setGasprice(gasprice);
  }

  /// @inheritdoc AbstractKandel
  function setGasprice(uint gasprice) public override onlyAdmin {
    uint16 gasprice_ = uint16(gasprice);
    require(gasprice_ == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = gasprice_;
    emit SetGasprice(gasprice_);
  }

  /// @inheritdoc AbstractKandel
  function setGasreq(uint gasreq) public override onlyAdmin {
    uint24 gasreq_ = uint24(gasreq);
    require(gasreq_ == gasreq, "Kandel/gasreqTooHigh");
    params.gasreq = gasreq_;
    emit SetGasreq(gasreq_);
  }

  /// @notice Updates the params to new values.
  function setParams(Params calldata newParams) internal {
    Params memory oldParams = params;

    if (oldParams.pricePoints != newParams.pricePoints) {
      setLength(newParams.pricePoints);
      params.pricePoints = newParams.pricePoints;
    }

    bool geometricChanged = false;
    if (oldParams.ratio != newParams.ratio) {
      require(newParams.ratio >= 10 ** PRECISION && newParams.ratio <= 2 * 10 ** PRECISION, "Kandel/invalidRatio");
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

  /// @inheritdoc AbstractKandel
  function setCompoundRates(uint compoundRateBase, uint compoundRateQuote) public override onlyAdmin {
    require(compoundRateBase <= 10 ** PRECISION, "Kandel/invalidCompoundRateBase");
    require(compoundRateQuote <= 10 ** PRECISION, "Kandel/invalidCompoundRateQuote");
    emit SetCompoundRates(compoundRateBase, compoundRateQuote);
    params.compoundRateBase = uint24(compoundRateBase);
    params.compoundRateQuote = uint24(compoundRateQuote);
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
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param baseAmount base amount to deposit
  ///@param quoteAmount quote amount to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different ratio, pricePoints, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint firstAskIndex,
    Params calldata parameters,
    uint baseAmount,
    uint quoteAmount
  ) external payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(parameters);

    depositFunds(baseAmount, quoteAmount);

    populateChunkInternal(distribution, pivotIds, firstAskIndex);
  }

  ///@notice internal version does not check onlyAdmin
  function populateChunkInternal(Distribution calldata distribution, uint[] calldata pivotIds, uint firstAskIndex)
    internal
  {
    populateChunk(distribution, pivotIds, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple transactions are needed to split initialization due to gas cost.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices.
  ///@param pivotIds the pivot to be used for the offer.
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  function populateChunk(Distribution calldata distribution, uint[] calldata pivotIds, uint firstAskIndex)
    external
    onlyAdmin
  {
    populateChunk(distribution, pivotIds, firstAskIndex, params.gasreq, params.gasprice);
  }

  ///@notice calculates the wants and gives for the dual offer according to the geometric price distribution.
  ///@dev Define the (maker) price of the order as `p_order := order.gives / order.wants` (what the taker gave divided by what the taker got).
  /// the (maker) price of the dual order must be `p_dual := p_order / ratio^spread` at which one should buy back at least what was sold.
  /// thus `min_offer_wants := order.wants` at price `p_dual`
  /// with `min_offer_gives / min_offer_wants = p_dual` we derive `min_offer_gives = order.gives/ratio^spread`.
  /// Now at maximal compounding, maker wants to give all what taker gave. That is `max_offer_gives := order.gives`
  /// So with compound rate we have:
  /// `offer_gives := min_offer_gives + (max_offer_gives - min_offer_gives) * compoundRate`.
  /// and we derive the formula:
  /// `offer_gives = order.gives * ( 1/ratio^spread + (1 - 1/ratio^spread) * compoundRate)`
  /// which we use in the code below
  function dualWantsGivesOfOffer(
    OfferType baDual,
    uint offerGives,
    MgvLib.SingleOrder calldata order,
    Params memory memoryParams
  ) internal pure returns (uint wants, uint gives) {
    // computing gives/wants for dual offer
    // we verify we cannot overflow if PRECISION = 5
    // spread:8
    uint spread = uint(memoryParams.spread);
    // compoundRate <= 10**PRECISION hence compoundRate:PRECISION*log2(10)
    uint compoundRate = compoundRateForDual(baDual, memoryParams);
    // params.ratio <= 2*10**PRECISION, spread:8, r: 8 * (PRECISION*log2(10) + 1)
    uint r = uint(memoryParams.ratio) ** spread;
    uint p = 10 ** PRECISION;
    // order.gives:96
    // p ~ compoundRate : log2(10) * PRECISION
    // p ** spread : 8 * log2(10) * PRECISION
    // (p - compoundRate) * p ** spread : 9 * log2(10) * PRECISION (=150 for PRECISION = 5)
    // compoundRate * r : PRECISION*log2(10) + 8 * (PRECISION*log2(10) + 1) (=157 for PRECISION = 5)
    // 157 + 96 < 256
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
    // gives * r : 237 so order.wants must be < 2**18 to completely avoid overflow.
    // Since order.wants is high when gives * r is, we check whether the full precision can be used and only if not then we use less precision.
    uint givesR = gives * r;
    if (uint160(givesR) == givesR || order.wants < 2 ** 18) {
      // using max precision
      wants = (order.wants * givesR) / (order.gives * (p ** spread));
    } else {
      // we divide `gives*r` by `order.gives` with max precision so that the resulting `givesR:160` in order to make sure it can be multiplied by `order.wants`
      givesR = (givesR * 2 ** 19) / order.gives;
      wants = (order.wants * givesR) / (p ** spread);
      // we correct for the added precision above
      wants /= 2 ** 19;
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
    returns (OfferType baDual, bool isOutOfRange, uint dualOfferId, uint dualIndex, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;

    isOutOfRange = index == 0 || index == memoryParams.pricePoints - 1;

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
  }
}
