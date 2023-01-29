// SPDX-License-Identifier:	BSD-2-Clause

// CoreKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {
  MangroveOffer,
  Direct,
  IMangrove,
  IERC20,
  MgvLib,
  MgvStructs
} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {OfferType} from "./Trade.sol";

abstract contract CoreKandel is Direct, AbstractKandel {
  ///@notice base of the market Kandel is making
  IERC20 public immutable BASE;
  ///@notice quote of the market Kandel is making
  IERC20 public immutable QUOTE;

  Params public params;

  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice)
    Direct(mgv, NO_ROUTER, gasreq)
    AbstractKandel(mgv, base, quote)
  {
    BASE = base;
    QUOTE = quote;
    require(uint16(gasprice) == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = uint16(gasprice);

    // approves Mangrove to pull base and quote token from this contract
    __activate__(base);
    __activate__(quote);
  }

  ///@notice set the compound rates. It will take effect for future compounding.
  ///@param compoundRateBase the compound rate for base.
  ///@param compoundRateQuote the compound rate for quote.
  ///@dev For low compound rates Kandel can end up with everything as pending and nothing offered.
  ///@dev To avoid this, then for equal compound rates `C` then $C >= 1/(sqrt(ratio^spread)+1)$.
  ///@dev With one rate being 0 and the other 1 the amount earned from the spread will accumulate as pending
  ///@dev for the token at 0 compounding and the offered volume will stay roughly static (modulo rounding).
  function setCompoundRates(uint16 compoundRateBase, uint16 compoundRateQuote) public mgvOrAdmin {
    require(compoundRateBase <= 10 ** PRECISION, "Kandel/invalidCompoundRateBase");
    require(compoundRateQuote <= 10 ** PRECISION, "Kandel/invalidCompoundRateQuote");
    emit SetCompoundRates(compoundRateBase, compoundRateQuote);
    params.compoundRateBase = compoundRateBase;
    params.compoundRateQuote = compoundRateQuote;
  }

  function length() public view returns (uint) {
    return params.length;
  }

  ///@notice turns an offer type into an (outbound, inbound) pair identifying an offer list
  ///@param ba whether one wishes to access the offer lists where asks or bids are posted
  function tokenPairOfOfferType(OfferType ba) internal view override returns (IERC20, IERC20) {
    return ba == OfferType.Bid ? (QUOTE, BASE) : (BASE, QUOTE);
  }

  ///@notice returns the Kandel offer type of the offer list whose outbound token is given in the argument
  ///@param outbound_tkn the outbound token of the offer list
  function OfferTypeOfOutbound(IERC20 outbound_tkn) internal view returns (OfferType) {
    return outbound_tkn == BASE ? OfferType.Ask : OfferType.Bid;
  }

  ///@notice returns the outbound token for the offer type
  ///@param ba the offer type
  function outboundOfOfferType(OfferType ba) internal view returns (IERC20 token) {
    token = ba == OfferType.Ask ? BASE : QUOTE;
  }

  function wantsGivesOfBaseQuote(OfferType ba, uint baseAmount, uint quoteAmount)
    internal
    pure
    returns (uint wants, uint gives)
  {
    if (ba == OfferType.Ask) {
      wants = quoteAmount;
      gives = baseAmount;
    } else {
      wants = baseAmount;
      gives = quoteAmount;
    }
  }

  ///@notice returns the dual offer type
  ///@param ba whether the offer is an ask or a bid
  ///@return dualBa is the dual offer type (ask for bid and conversely)
  function dual(OfferType ba) public pure returns (OfferType dualBa) {
    return OfferType((uint(ba) + 1) % 2);
  }

  /// @param baDual the dual offer type.
  /// @param memoryParams the Kandel params.
  /// @return compoundRate to use for the gives of the offer type. Asks give base so this would be the `compoundRateBase`, and vice versa.
  function compoundRateForDual(OfferType baDual, Params memory memoryParams) private pure returns (uint compoundRate) {
    compoundRate = uint(baDual == OfferType.Ask ? memoryParams.compoundRateBase : memoryParams.compoundRateQuote);
  }

  function dualWantsGivesOfOffer(
    OfferType baDual,
    SlotViewMonad memory viewDual,
    MgvLib.SingleOrder calldata order,
    Params memory memoryParams
  ) internal view returns (uint wants, uint gives) {
    // computing gives/wants for dual offer
    // we verify we cannot overflow if PRECISION = 4
    // spread:8
    uint spread = uint(memoryParams.spread);
    // compoundRate:16
    uint compoundRate = compoundRateForDual(baDual, memoryParams);
    // params.ratio:16, spread:8 ==> r:128
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
    gives += _offer(baDual, viewDual).gives();
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

  ///@notice returns a better (for Kandel) price index than the one given in argument
  ///@param ba whether Kandel is bidding or asking
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  function better(OfferType ba, uint index, uint step, uint length_) public pure returns (uint) {
    return ba == OfferType.Ask ? index + step >= length_ ? length_ - 1 : index + step : index < step ? 0 : index - step;
  }

  function getOffer(OfferType ba, uint index)
    public
    view
    returns (MgvStructs.OfferPacked offer, MgvStructs.OfferDetailPacked offerDetail)
  {
    uint offerId = offerIdOfIndex(ba, index);
    (IERC20 outbound, IERC20 inbound) = tokenPairOfOfferType(ba);
    offer = MGV.offers(address(outbound), address(inbound), offerId);
    offerDetail = MGV.offerDetails(address(outbound), address(inbound), offerId);
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Monad for the offer to be published
  ///@param args the argument of the offer.
  ///@return result from Mangrove on error and `args.noRevert` is `true`.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndexCore(OfferType ba, SlotViewMonad memory v, OfferArgs memory args)
    internal
    returns (bytes32 result)
  {
    uint offerId = _offerId(ba, v);
    // if offer does not exist on mangrove yet
    if (offerId == 0) {
      // and offer should exist
      if (args.gives > 0) {
        // create it
        (offerId, result) = _newOffer(args);
        if (offerId != 0) {
          setIndexMapping(ba, _index(ba, v), offerId);
        }
      }
      // else offerId && gives are 0 and the offer is left not posted
    }
    // else offer exists
    else {
      // but the offer should be dead since gives is 0
      if (args.gives == 0) {
        // so we retract the offer
        // note if gives is 0 then all gives in the range are 0, we may not want to allow for this.
        _retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume
        result = _updateOffer(args, offerId);
      }
    }
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index and emits incidents on errors
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Monad for the offer to be published
  ///@param args the argument of the offer.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndex(OfferType ba, SlotViewMonad memory v, OfferArgs memory args) internal returns (bytes32 result) {
    result = populateIndexCore(ba, v, args);
    if (result != REPOST_SUCCESS && result != "") {
      if (_offerId(ba, v) != 0) {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/updateOfferFailed", result);
      } else {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", result);
      }
    }
  }

  struct HeapVarsPopulate {
    uint lastBidIndex;
    uint gasprice;
    uint ratio;
  }

  function iterPopulate(
    HeapVarsPopulate memory vars,
    uint[] calldata indices,
    uint[] calldata baseDist,
    uint[] calldata quoteDist,
    uint[] calldata pivotIds
  ) internal {
    for (uint i = 0; i < indices.length; i++) {
      OfferArgs memory args;
      uint index = indices[i];

      OfferType ba = index <= vars.lastBidIndex ? OfferType.Bid : OfferType.Ask;
      (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(ba);
      (args.wants, args.gives) = wantsGivesOfBaseQuote(ba, baseDist[i], quoteDist[i]);
      args.fund = 0;
      args.noRevert = false;
      args.gasreq = offerGasreq();
      args.gasprice = vars.gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(ba, _fresh(index), args);
    }
  }

  function setParams(uint kandelSize, uint16 ratio, uint8 spread) private {
    // Initializing arrays and parameters if needed
    Params memory memoryParams = params;

    if (memoryParams.length != kandelSize) {
      require(kandelSize <= type(uint8).max, "Kandel/TooManyPricePoints");
      askOfferIdOfIndex = new uint[](kandelSize);
      bidOfferIdOfIndex = new uint[](kandelSize);
      params.length = uint8(kandelSize);
    }
    if (memoryParams.ratio != ratio) {
      require(ratio >= 10 ** PRECISION, "Kandel/invalidRatio");
      params.ratio = ratio;
    }
    if (memoryParams.spread != spread) {
      require(spread > 0, "Kandel/invalidSpread");
      params.spread = spread;
    }
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param indices the indices to populate
  ///@param baseDist base distribution for the indices
  ///@param quoteDist the distribution of quote for the indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param lastBidIndex the index after which offer should be an Ask. First index will never be an ask, either a bid or not published.
  ///@param kandelSize the number of price points
  ///@param ratio the rate of the geometric distribution with PRECISION decimals.
  ///@param spread the distance between a ask in the distribution and its corresponding bid.
  ///@dev This function must be called w/o changing ratio, kandelSize, spread. To change them, first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    uint[] calldata indices,
    uint[] calldata baseDist,
    uint[] calldata quoteDist,
    uint[] calldata pivotIds,
    uint lastBidIndex,
    uint kandelSize,
    uint16 ratio,
    uint8 spread
  ) external payable onlyAdmin {
    require(
      indices.length == baseDist.length && indices.length == quoteDist.length && indices.length == pivotIds.length,
      "Kandel/ArraysMustBeSameSize"
    );
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(kandelSize, ratio, spread);

    HeapVarsPopulate memory vars =
      HeapVarsPopulate({lastBidIndex: lastBidIndex, ratio: params.ratio, gasprice: params.gasprice});

    iterPopulate(vars, indices, baseDist, quoteDist, pivotIds);
  }

  ///@notice retracts and deprovisions offers of the distribution interval `[from, to[`
  ///@param from the start index
  ///@param to the end index
  ///@dev use in conjunction of `withdrawFromMangrove` if the user wishes to redeem the available WEIs
  function retractOffers(uint from, uint to) external onlyAdmin {
    (IERC20 outbound_tknAsk, IERC20 inbound_tknAsk) = tokenPairOfOfferType(OfferType.Ask);
    (IERC20 outbound_tknBid, IERC20 inbound_tknBid) = tokenPairOfOfferType(OfferType.Bid);
    for (uint index = from; index < to; index++) {
      // These offerIds could be recycled in a new populate
      uint offerId = offerIdOfIndex(OfferType.Ask, index);
      if (offerId != 0) {
        MGV.retractOffer(address(outbound_tknAsk), address(inbound_tknAsk), offerId, true);
        //_retractOffer(outbound_tknAsk, inbound_tknAsk, offerId, true);
      }
      offerId = offerIdOfIndex(OfferType.Bid, index);
      if (offerId != 0) {
        MGV.retractOffer(address(outbound_tknBid), address(inbound_tknBid), offerId, true);
        //_retractOffer(outbound_tknBid, inbound_tknBid, offerId, true);
      }
    }
  }

  ///@notice takes care of reposting residual offer in case of a partial fill and logging potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  ///@param repostStatus from the posthook
  function handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData, bytes32 repostStatus) internal {
    if (repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS) {
      return;
    }
    if (repostStatus == "mgv/writeOffer/density/tooLow") {
      emit DensityTooLow(order.offerId, __residualGives__(order), __residualWants__(order));
    } else {
      // Offer failed to repost for bad reason, logging the incident
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
    }
  }

  ///@notice repost residual offer and dual offer according to transport logic
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    handleResidual(order, makerData, repostStatus);

    OfferType ba = OfferTypeOfOutbound(IERC20(order.outbound_tkn));
    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (OfferType dualBa, SlotViewMonad memory viewDual, OfferArgs memory args) = transportLogic(ba, order);
    return populateIndex(dualBa, viewDual, args);
  }
}