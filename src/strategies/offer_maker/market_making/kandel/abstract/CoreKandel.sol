// SPDX-License-Identifier:	BSD-2-Clause
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
  function logPopulateStatus(uint offerId, OfferArgs memory args, bytes32 populateStatus) internal {
    if (
      populateStatus == REPOST_SUCCESS || populateStatus == NEW_OFFER_SUCCESS
        || populateStatus == "mgv/writeOffer/density/tooLow" || populateStatus == LOW_VOLUME
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
  function transportSuccessfulOrder(MgvLib.SingleOrder calldata order) internal {
    OfferType ba = offerTypeOfOutbound(IERC20(order.outbound_tkn));

    // adds any unpublished liquidity to pending[Base/Quote]
    // preparing arguments for the dual offer
    (OfferType baDual, uint offerId, uint index, OfferArgs memory args) = transportLogic(ba, order);
    bytes32 populateStatus = populateIndex(baDual, offerId, index, args);
    logPopulateStatus(offerId, args, populateStatus);
  }

  ///@notice transport logic followed by Kandel
  ///@param ba whether the offer that was executed is a bid or an ask
  ///@param order a recap of the taker order (order.offer is the executed offer)
  ///@return baDual the type of dual offer that will re-invest inbound liquidity
  ///@return offerId the offer id of the dual offer
  ///@return index the index of the dual offer
  ///@return args the argument for `populateIndex` specifying gives and wants
  function transportLogic(OfferType ba, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (OfferType baDual, uint offerId, uint index, OfferArgs memory args);

  /// @notice gets pending liquidity for base (ask) or quote (bid). Will be negative if funds are not enough to cover all offer's promises.
  /// @param ba offer type.
  /// @return the pending amount
  /// @dev Gas costly function, better suited for off chain calls.
  function pending(OfferType ba) external view override returns (int) {
    return int(reserveBalance(ba)) - int(offeredVolume(ba));
  }

  ///@notice Deposits funds to the contract's balance
  ///@param token the deposited asset
  ///@param amount to deposit
  function _deposit(IERC20 token, uint amount) internal {
    require(TransferLib.transferTokenFrom(token, msg.sender, address(this), amount), "Kandel/depositFail");
    emit Credit(token, amount);
  }

  ///@notice withdraws funds from the contract's reserve
  ///@param token the asset one wishes to withdraw
  ///@param amount to withdraw
  ///@param recipient the address to which the withdrawn funds should be sent to.
  function _withdraw(IERC20 token, uint amount, address recipient) internal {
    require(TransferLib.transferToken(token, recipient, amount), "Kandel/withdrawFail");
    emit Debit(token, amount);
  }
}
