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
import {AbstractKandel} from "./AbstractKandel.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";

///@title the core of Kandel strategies which creates or updates a dual offer whenever an offer is taken.
///@notice `CoreKandel` is agnostic to the chosen price distribution.
abstract contract CoreKandel is DirectWithBidsAndAsksDistribution, AbstractKandel {
  constructor(IMangrove mgv, uint gasreq, address reserveId) DirectWithBidsAndAsksDistribution(mgv, gasreq, reserveId) {}

  ///@notice takes care of status for populating dual and logging of potential issues.
  ///@param offerId the Mangrove offer id (or 0 if newOffer failed).
  ///@param args the arguments of the offer.
  ///@param populateStatus the status returned from the populateIndex function.
  function logPopulateStatus(uint offerId, OfferArgs memory args, bytes32 populateStatus) internal {
    if (
      populateStatus == REPOST_SUCCESS || populateStatus == NEW_OFFER_SUCCESS
        || populateStatus == "mgv/writeOffer/density/tooLow"
    ) {
      // Low density will mean some amount is not posted and will be available for withdrawal or later posting via populate.
      return;
    }
    if (offerId != 0) {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, offerId, "Kandel/updateOfferFailed", populateStatus);
    } else {
      emit LogIncident(MGV, args.outbound_tkn, args.inbound_tkn, 0, "Kandel/newOfferFailed", populateStatus);
    }
  }

  ///@notice update or create dual offer according to transport logic
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  ///@return isOutOfRange whether the taken offer was at the edge of the Kandel price range.
  function transportSuccessfulOrder(MgvLib.SingleOrder calldata order) internal returns (bool) {
    OfferType ba = offerTypeOfOutbound(IERC20(order.outbound_tkn));

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (OfferType baDual, bool isOutOfRange, uint offerId, uint index, OfferArgs memory args) = transportLogic(ba, order);
    bytes32 populateStatus = populateIndex(baDual, offerId, index, args);
    logPopulateStatus(offerId, args, populateStatus);
    return isOutOfRange;
  }

  ///@notice logs AllAsks or AllBids in case the last bid or ask is fully taken (or reposting fails)
  ///@param order is a recall of the taker order that is at the origin of the current trade.
  ///@param repostStatus the repostStatus from trying to repost the residual of the offer.
  function logOutOfRange(MgvLib.SingleOrder calldata order, bytes32 repostStatus) internal {
    if (repostStatus != REPOST_SUCCESS) {
      if (offerTypeOfOutbound(IERC20(order.outbound_tkn)) == OfferType.Bid) {
        emit AllAsks();
      } else {
        emit AllBids();
      }
    }
  }

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return baDual the type of dual offer that will re-invest inbound liquidity
  ///@return isOutOfRange whether the offer is either the last bid or ask
  ///@return offerId the offer id of the dual offer
  ///@return index the index of the dual offer
  ///@return args the argument for `populateIndex` specifying gives and wants
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OfferType baDual, bool isOutOfRange, uint offerId, uint index, OfferArgs memory args);

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return pending_ the pending amount
  /// @dev Gas costly function, better suited for off chain calls.
  function pending(OfferType ba) external view override returns (int pending_) {
    IERC20 token = outboundOfOfferType(ba);
    pending_ = int(reserveBalance(token)) - int(offeredVolume(ba));
  }

  function depositFunds(IERC20[] calldata tokens, uint[] calldata amounts) public virtual override {
    TransferLib.transferTokensFrom(tokens, msg.sender, address(this), amounts);
    for (uint i; i < tokens.length; i++) {
      emit Credit(tokens[i], amounts[i]);
    }
  }

  function withdrawFunds(IERC20[] calldata tokens, uint[] calldata amounts, address recipient)
    public
    virtual
    override
    onlyAdmin
  {
    TransferLib.transferTokens(tokens, amounts, recipient);
    for (uint i; i < tokens.length; i++) {
      emit Debit(tokens[i], amounts[i]);
    }
  }

  ///@notice Retracts offers, withdraws funds, and withdraws free wei from Mangrove.
  ///@param from retract offers starting from this index.
  ///@param to retract offers until this index.
  ///@param tokens the tokens to withdraw.
  ///@param tokenAmounts the amounts of the tokens to withdraw.
  ///@param freeWei the amount of wei to withdraw from Mangrove. Use type(uint).max to withdraw entire available balance.
  ///@param recipient the recipient of the funds.
  function retractAndWithdraw(
    uint from,
    uint to,
    IERC20[] calldata tokens,
    uint[] calldata tokenAmounts,
    uint freeWei,
    address payable recipient
  ) external onlyAdmin {
    retractOffers(from, to);
    withdrawFunds(tokens, tokenAmounts, recipient);
    withdrawFromMangrove(freeWei, recipient);
  }
}
