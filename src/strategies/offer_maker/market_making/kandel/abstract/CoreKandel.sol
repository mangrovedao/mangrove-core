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
  MgvStructs,
  AbstractRouter,
  TransferLib
} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {OfferType} from "./Trade.sol";
import {HasKandelSlotViewMemoizer} from "./HasKandelSlotViewMemoizer.sol";
import {HasIndexedOffers} from "./HasIndexedOffers.sol";
import {TradesBaseQuote} from "./TradesBaseQuote.sol";

abstract contract CoreKandel is HasIndexedOffers, Direct, HasKandelSlotViewMemoizer, AbstractKandel, TradesBaseQuote {
  ///@param indices the indices to populate, in ascending order
  ///@param baseDist base distribution for the indices
  ///@param quoteDist the distribution of quote for the indices
  struct Distribution {
    uint[] baseDist;
    uint[] quoteDist;
    uint[] indices;
  }

  Params public params;

  constructor(
    HasIndexedOffers.MangroveWithBaseQuote memory mangroveWithBaseQuote,
    uint gasreq,
    uint gasprice,
    address owner
  )
    Direct(mangroveWithBaseQuote.mgv, NO_ROUTER, gasreq, owner)
    HasIndexedOffers(mangroveWithBaseQuote.mgv)
    HasKandelSlotViewMemoizer(mangroveWithBaseQuote.mgv)
    TradesBaseQuote(mangroveWithBaseQuote.base, mangroveWithBaseQuote.quote)
  {
    emit NewKandel(msg.sender, mangroveWithBaseQuote.mgv, mangroveWithBaseQuote.base, mangroveWithBaseQuote.quote);
    setGas(gasprice);
  }

  /// @notice sets the gasprice and updates gasreq
  function setGas(uint gasprice) public onlyAdmin {
    uint16 gasprice_ = uint16(gasprice);
    // includes router gasreq
    uint gasreq = offerGasreq();
    uint24 gasreq_ = uint24(offerGasreq());
    require(gasreq_ == gasreq, "Kandel/gasreqTooHigh");
    require(gasprice_ == gasprice, "Kandel/gaspriceTooHigh");
    params.gasprice = gasprice_;
    params.gasreq = gasreq_;
    emit SetGas(gasprice_, gasreq_);
  }

  /// @notice deposits funds on Kandel
  /// @param amounts to withdraw.
  /// @param tokens addresses of tokens to withdraw.
  function _depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) internal {
    for (uint i; i < tokens.length; i++) {
      require(TransferLib.transferTokenFrom(tokens[i], msg.sender, address(this), amounts[i]), "Kandel/depositFailed");
    }
  }

  /// @notice withdraw `amount` of funds to `recipient`.
  /// @param amounts to withdraw.
  /// @param tokens addresses of tokens to withdraw.
  /// @param recipient who receives the tokens.
  /// @dev it is up to the caller to make sure there are still enough funds for live offers.
  function _withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient) internal {
    for (uint i; i < tokens.length; i++) {
      require(TransferLib.transferToken(tokens[i], recipient, amounts[i]), "Kandel/NotEnoughFunds");
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

  ///@notice returns a better (for Kandel) price index than the one given in argument
  ///@param ba whether Kandel is bidding or asking
  ///@param index the price index one is willing to improve
  ///@param step the number of price steps improvements
  function better(OfferType ba, uint index, uint step, uint length_) public pure returns (uint) {
    return ba == OfferType.Ask ? index + step >= length_ ? length_ - 1 : index + step : index < step ? 0 : index - step;
  }

  ///@notice publishes (by either creating or updating) a bid/ask at a given price index
  ///@param ba whether the offer is a bid or an ask
  ///@param v the view Memoizer for the offer to be published
  ///@param args the argument of the offer.
  ///@return result from Mangrove on error and `args.noRevert` is `true`.
  ///@dev args.wants/gives must match the distribution at index
  function populateIndex(OfferType ba, SlotViewMemoizer memory v, OfferArgs memory args)
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
        // so we retract the offer. This does not happen when gives comes from dualWantsGivesOfOffer,
        // but may happen from populate in case of re-population where the offers in the spread
        // are then retracted by setting gives to 0.
        _retractOffer(args.outbound_tkn, args.inbound_tkn, offerId, false);
      } else {
        // so the offer exists and it should, we simply update it with potentially new volume
        result = _updateOffer(args, offerId);
      }
    }
  }

  ///@notice Publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@notice This function is used publicly after `populate` to reinitialize some indices or if multiple calls are needed for initialization.
  ///@notice This function is not payable, use `populate` to fund along with populate.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param lastBidIndex the index after which offer should be an ask. First index will never be an ask, either a bid or not published.
  function populateChunk(Distribution calldata distribution, uint[] calldata pivotIds, uint lastBidIndex)
    public
    onlyAdmin
  {
    uint[] calldata indices = distribution.indices;
    uint[] calldata quoteDist = distribution.quoteDist;
    uint[] calldata baseDist = distribution.baseDist;

    require(
      indices.length == baseDist.length && indices.length == quoteDist.length && indices.length == pivotIds.length,
      "Kandel/ArraysMustBeSameSize"
    );

    uint i = 0;
    uint gasreq = params.gasreq;
    uint gasprice = params.gasprice;

    OfferArgs memory args;
    // args.fund = 0; offers are already funded
    // args.noRevert = false; we want revert in case of failure

    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(OfferType.Bid);
    for (i = 0; i < indices.length; i++) {
      uint index = indices[i];
      if (index > lastBidIndex) {
        break;
      }
      args.wants = baseDist[i];
      args.gives = quoteDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(OfferType.Bid, _fresh(index), args);
    }
    if (i > 0) {
      // At least one bid has been populated, emit it to make price derivable
      emit BidNearMidPopulated(indices[i - 1], uint96(args.gives), uint96(args.wants));
    }
    (args.outbound_tkn, args.inbound_tkn) = tokenPairOfOfferType(OfferType.Ask);

    for (; i < indices.length; i++) {
      uint index = indices[i];
      args.wants = quoteDist[i];
      args.gives = baseDist[i];
      args.gasreq = gasreq;
      args.gasprice = gasprice;
      args.pivotId = pivotIds[i];

      populateIndex(OfferType.Ask, _fresh(index), args);
    }
  }

  function setParams(uint8 kandelSize, uint16 ratio, uint8 spread) private {
    // Initializing arrays and parameters if needed
    Params memory memoryParams = params;

    if (memoryParams.length != kandelSize) {
      setLength(kandelSize);
      params.length = kandelSize;
    }
    if (memoryParams.ratio != ratio) {
      require(ratio >= 10 ** PRECISION, "Kandel/invalidRatio");
      params.ratio = ratio;
    }
    if (memoryParams.spread != spread) {
      require(spread > 0 && spread <= 8, "Kandel/invalidSpread");
      params.spread = spread;
    }
    emit SetParams(kandelSize, spread, ratio);
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param lastBidIndex the index after which offer should be an ask. First index will never be an ask, either a bid or not published.
  ///@param kandelSize the number of price points
  ///@param ratio the rate of the geometric distribution with PRECISION decimals.
  ///@param spread the distance between a ask in the distribution and its corresponding bid.
  ///@param depositTokens tokens to deposit.
  ///@param depositAmounts amounts to deposit for the tokens.
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different ratio, kandelSize, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint lastBidIndex,
    uint8 kandelSize,
    uint16 ratio,
    uint8 spread,
    IERC20[] calldata depositTokens,
    uint[] calldata depositAmounts
  ) external payable onlyAdmin {
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    setParams(kandelSize, ratio, spread);

    depositFunds(depositTokens, depositAmounts);

    populateChunk(distribution, pivotIds, lastBidIndex);
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
        _retractOffer(outbound_tknAsk, inbound_tknAsk, offerId, true);
      }
      offerId = offerIdOfIndex(OfferType.Bid, index);
      if (offerId != 0) {
        _retractOffer(outbound_tknBid, inbound_tknBid, offerId, true);
      }
    }
  }

  ///@inheritdoc AbstractKandel
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (OfferType baDual, SlotViewMemoizer memory viewDual, OfferArgs memory args)
  {
    uint index = indexOfOfferId(ba, order.offerId);
    Params memory memoryParams = params;

    if (index == 0) {
      emit AllAsks();
    }
    if (index == memoryParams.length - 1) {
      emit AllBids();
    }
    baDual = dual(ba);

    viewDual = _fresh(better(baDual, index, memoryParams.spread, memoryParams.length));

    args.outbound_tkn = IERC20(order.inbound_tkn);
    args.inbound_tkn = IERC20(order.outbound_tkn);

    MgvStructs.OfferPacked offer = _offer(baDual, viewDual);
    // computing gives/wants for dual offer
    // At least: gives = order.gives/ratio and wants is then order.wants
    // At most: gives = order.gives and wants is adapted to match the price
    (args.wants, args.gives) = dualWantsGivesOfOffer(baDual, offer.gives(), order, memoryParams);
    // args.fund = 0; the offers are already provisioned
    // posthook should not fail if unable to post offers, we capture the error as incidents
    args.noRevert = true;
    args.gasprice = params.gasprice;
    args.gasreq = params.gasreq;
    args.pivotId = offer.gives() > 0 ? offer.next() : 0;
    return (baDual, viewDual, args);
  }

  ///@notice takes care of status for reposting residual offer in case of a partial fill and logging of potential issues.
  ///@param order a recap of the taker order
  ///@param makerData generated during `makerExecute` so as to log it if necessary
  ///@param repostStatus from the super posthook
  function handleResidual(MgvLib.SingleOrder calldata order, bytes32 makerData, bytes32 repostStatus) internal {
    if (
      repostStatus == "posthook/filled" || repostStatus == REPOST_SUCCESS
        || repostStatus == "mgv/writeOffer/density/tooLow"
    ) {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    } else {
      // Offer failed to repost for bad reason, logging the incident
      emit LogIncident(
        MGV, IERC20(order.outbound_tkn), IERC20(order.inbound_tkn), order.offerId, makerData, repostStatus
        );
    }
  }

  ///@notice takes care of status for populating dual and logging of potential issues.
  ///@param dualBa whether the offer is a bid or an ask
  ///@param viewDual the view Memoizer for the offer.
  ///@param args the argument of the offer.
  function handlePopulate(
    OfferType dualBa,
    SlotViewMemoizer memory viewDual,
    OfferArgs memory args,
    bytes32 populateStatus
  ) internal {
    if (populateStatus == REPOST_SUCCESS || populateStatus == "" || populateStatus == "mgv/writeOffer/density/tooLow") {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    }
    uint offerId = _offerId(dualBa, viewDual);
    if (offerId != 0) {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, offerId, "Kandel/updateOfferFailed", populateStatus);
    } else {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", populateStatus);
    }
  }

  ///@notice repost residual offer and dual offer according to transport logic
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32 populateStatus)
  {
    bytes32 repostStatus = super.__posthookSuccess__(order, makerData);
    OfferType ba = OfferTypeOfOutbound(IERC20(order.outbound_tkn));
    handleResidual(order, makerData, repostStatus);

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (OfferType dualBa, SlotViewMemoizer memory viewDual, OfferArgs memory args) = transportLogic(ba, order);
    populateStatus = populateIndex(dualBa, viewDual, args);

    handlePopulate(dualBa, viewDual, args, populateStatus);
  }
}
