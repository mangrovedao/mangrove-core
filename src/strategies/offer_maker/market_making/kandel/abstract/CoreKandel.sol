// SPDX-License-Identifier:	BSD-2-Clause

// CoreKandel.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MgvLib} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {OfferType} from "./TradesBaseQuotePair.sol";
import {DirectWithBidsAndAsksDistribution} from "./DirectWithBidsAndAsksDistribution.sol";
import {TradesBaseQuotePair} from "./TradesBaseQuotePair.sol";
import {AbstractKandel} from "./AbstractKandel.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

///@title the core of Kandel strategies which creates or updates a dual offer whenever an offer is taken.
///@notice `CoreKandel` is agnostic to the chosen price distribution.
abstract contract CoreKandel is DirectWithBidsAndAsksDistribution, TradesBaseQuotePair, AbstractKandel {
  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param base Address of the base token of the market Kandel will act on
  ///@param quote Address of the quote token of the market Kandel will act on
  ///@param gasreq the gasreq to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, address reserveId)
    TradesBaseQuotePair(base, quote)
    DirectWithBidsAndAsksDistribution(mgv, gasreq, reserveId)
  {}

  ///@inheritdoc AbstractKandel
  function reserveBalance(OfferType ba) public view virtual override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return token.balanceOf(address(this));
  }

  ///@notice takes care of status for populating dual and logging of potential issues.
  ///@param offerId the Mangrove offer id (or 0 if newOffer failed).
  ///@param args the arguments of the offer.
  ///@param populateStatus the status returned from the populateIndex function.
  function logPopulateStatus(uint offerId, OfferArgs memory args, bytes32 populateStatus)
    internal
    returns (bool offerUpdated)
  {
    //TODO update pending
    //TODO also for primary offer
    if (populateStatus == REPOST_SUCCESS || populateStatus == NEW_OFFER_SUCCESS) {
      offerUpdated = true;
    } else if (populateStatus == "mgv/writeOffer/density/tooLow" || populateStatus == LOW_VOLUME) {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
    } else {
      if (offerId != 0) {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, offerId, "Kandel/updateOfferFailed", populateStatus);
      } else {
        emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", populateStatus);
      }
    }
  }

  ///@notice update or create dual offer according to transport logic
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  function transportSuccessfulOrder(MgvLib.SingleOrder calldata order) internal {
    OfferType ba = offerTypeOfOutbound(IERC20(order.outbound_tkn));

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (
      OfferType baDual,
      uint dualOfferId,
      uint dualIndex,
      OfferArgs memory args,
      uint oldGives,
      uint oldPending,
      uint index
    ) = transportLogic(ba, order);
    (uint newDualOfferId, bytes32 populateStatus) = populateIndex(dualOfferId, args);
    bool offerUpdated = logPopulateStatus(dualOfferId, args, populateStatus);
    if (newDualOfferId != dualOfferId) {
      uint dualPrice = priceOfIndex[index];
      require(dualPrice > 0, "Kandel/zeroPriceDual");

      setIndexAndPriceFromDual(baDual, newDualOfferId, dualIndex, dualPrice);

      OfferIdPending memory offerIdPending =
        OfferIdPending(uint32(newDualOfferId), 0 /*pending is 0 since we posted new offer with it*/ );
      setIndexMapping(baDual, dualIndex, offerIdPending);
    } else {
      setPendingInMapping(baDual, dualIndex, args.gives, offerUpdated, oldGives, oldPending);
    }
  }

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return baDual the type of dual offer that will re-invest inbound liquidity
  ///@return dualOfferId the offer id of the dual offer
  ///@return dualIndex the index of the dual offer
  ///@return args the argument for `populateIndex` specifying gives and wants
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (
      OfferType baDual,
      uint dualOfferId,
      uint dualIndex,
      OfferArgs memory args,
      uint dualGives,
      uint oldPending,
      uint index
    );

  //TODO pending is not the same as unpublished anymore.
  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return the pending amount
  /// @dev Gas costly function, better suited for off chain calls.
  function pending(OfferType ba) external view override returns (int) {
    return int(reserveBalance(ba)) - int(offeredVolume(ba));
  }

  //TODO: update pending?
  ///@notice Deposits funds to the contract's reserve
  ///@param baseAmount the amount of base tokens to deposit.
  ///@param quoteAmount the amount of quote tokens to deposit.
  function depositFunds(uint baseAmount, uint quoteAmount) public virtual override {
    require(TransferLib.transferTokenFrom(BASE, msg.sender, address(this), baseAmount), "Kandel/baseTransferFail");
    emit Credit(BASE, baseAmount);
    require(TransferLib.transferTokenFrom(QUOTE, msg.sender, address(this), quoteAmount), "Kandel/quoteTransferFail");
    emit Credit(QUOTE, quoteAmount);
  }

  ///@notice withdraws funds from the contract's reserve
  ///@param baseAmount the amount of base tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param quoteAmount the amount of quote tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param recipient the address to which the withdrawn funds should be sent to.
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) public virtual override onlyAdmin {
    if (baseAmount == type(uint).max) {
      baseAmount = BASE.balanceOf(address(this));
    }
    if (quoteAmount == type(uint).max) {
      quoteAmount = QUOTE.balanceOf(address(this));
    }
    require(TransferLib.transferToken(BASE, recipient, baseAmount), "Kandel/baseTransferFail");
    emit Debit(BASE, baseAmount);
    require(TransferLib.transferToken(QUOTE, recipient, quoteAmount), "Kandel/quoteTransferFail");
    emit Debit(QUOTE, quoteAmount);
  }

  ///@notice Retracts offers, withdraws funds, and withdraws free wei from Mangrove.
  ///@param from retract offers starting from this index.
  ///@param to retract offers until this index.
  ///@param baseAmount the amount of base tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param quoteAmount the amount of quote tokens to withdraw. Use type(uint).max to denote the entire reserve balance.
  ///@param freeWei the amount of wei to withdraw from Mangrove. Use type(uint).max to withdraw entire available balance.
  ///@param recipient the recipient of the funds.
  function retractAndWithdraw(
    uint from,
    uint to,
    uint baseAmount,
    uint quoteAmount,
    uint freeWei,
    address payable recipient
  ) external onlyAdmin {
    retractOffers(from, to);
    withdrawFunds(baseAmount, quoteAmount, recipient);
    withdrawFromMangrove(freeWei, recipient);
  }
}
