// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {IERC20} from "mgv_src/IERC20.sol";
import {IOfferLogic} from "./IOfferLogic.sol";

///@title Completes IOfferLogic to provide an ABI for LiquidityProvider class of Mangrove's SDK

interface ILiquidityProvider is IOfferLogic {
  ///@notice creates a new offer on Mangrove with an override for gas requirement
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for inserting the offer in the list
  ///@param gasreq the gas required by the offer logic
  ///@return offerId the Mangrove offer id.
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint gasreq)
    external
    payable
    returns (uint offerId);

  ///@notice updates an offer existing on Mangrove (not necessarily live) with an override for gas requirement
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the new amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the new amount of inbound tokens the offer maker gives for a complete fill
  ///@param pivotId the pivot to use for re-inserting the offer in the list (use `offerId` if updated offer is live)
  ///@param offerId the id of the offer in the offer list.
  ///@param gasreq the gas required by the offer logic
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint pivotId,
    uint offerId,
    uint gasreq
  ) external payable;

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function retractOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, bool deprovision)
    external
    returns (uint freeWei);
}
