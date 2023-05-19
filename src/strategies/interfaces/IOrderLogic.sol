// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity >=0.8.10;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/MgvLib.sol";

///@title Interface for resting orders functionality.
interface IOrderLogic {
  ///@notice Information for creating a market order with a GTC or FOK semantics.
  ///@param outbound_tkn outbound token used to identify the order book
  ///@param inbound_tkn the inbound token used to identify the order book
  ///@param fillOrKill true to revert if market order cannot be filled and resting order failed or is not enabled; otherwise, false
  ///@param takerWants desired total amount of `outbound_tkn`
  ///@param takerGives available total amount of `inbound_tkn`
  ///@param fillWants if true (buying), the market order stops when `takerWants` units of `outbound_tkn` have been obtained (fee included); otherwise (selling), the market order stops when `takerGives` units of `inbound_tkn` have been sold.
  ///@param restingOrder whether the complement of the partial fill (if any) should be posted as a resting limit order.
  ///@param pivotId in case a resting order is required, the best pivot estimation of its position in the offer list (if the market order led to a non empty partial fill, then `pivotId` should be 0 unless the order book is crossed).
  ///@param expiryDate timestamp (expressed in seconds since unix epoch) beyond which the order is no longer valid, 0 means forever
  struct TakerOrder {
    IERC20 outbound_tkn;
    IERC20 inbound_tkn;
    bool fillOrKill;
    uint takerWants;
    uint takerGives;
    bool fillWants;
    bool restingOrder;
    uint pivotId;
    uint expiryDate;
  }

  ///@notice Result of an order from the takers side.
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param bounty How much bounty was givin to the taker
  ///@param fee The fee paid by the taker
  ///@param offerId The id of the offer that was taken
  struct TakerOrderResult {
    uint takerGot;
    uint takerGave;
    uint bounty;
    uint fee;
    uint offerId;
  }

  ///@notice Information about the order.
  ///@param mangrove The Mangrove contract on which the offer was posted
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param taker The address of the taker
  ///@param fillOrKill The fillOrKill that take was called with
  ///@param takerWants How much the taker wanted
  ///@param takerGives How much the taker would give
  ///@param fillWants If true, the market order stopped when `takerWants` units of `outbound_tkn` had been obtained; otherwise, the market order stopped when `takerGives` units of `inbound_tkn` had been sold.
  ///@param restingOrder The restingOrder boolean take was called with
  ///@param expiryDate The expiry date take was called with
  ///@param takerGot How much the taker got
  ///@param takerGave How much the taker gave
  ///@param bounty How much bounty was given
  ///@param fee How much fee was paid for the order
  ///@param restingOrderId If a restingOrder was posted, then this holds the offerId for the restingOrder
  event OrderSummary(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    address indexed taker,
    bool fillOrKill,
    uint takerWants,
    uint takerGives,
    bool fillWants,
    bool restingOrder,
    uint expiryDate,
    uint takerGot,
    uint takerGave,
    uint bounty,
    uint fee,
    uint restingOrderId
  );

  ///@notice Timestamp beyond which the given `offerId` should renege on trade.
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param offerId The id of the offer to query for expiry for.
  ///@return res The timestamp beyond which `offerId` on the `(outbound_tkn, inbound_tkn)` offer list should renege on trade. 0 means no expiry.
  function expiring(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) external returns (uint);

  ///@notice Updates the expiry date for a specific offer.
  ///@param outbound_tkn The outbound token of the order.
  ///@param inbound_tkn The inbound token of the order.
  ///@param offerId The offer id whose expiry date is to be set.
  ///@param date in seconds since unix epoch
  ///@dev If new date is in the past of the current block's timestamp, offer will renege on trade.
  function setExpiry(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId, uint date) external;

  ///@notice Implements "Fill or kill" or "Good till cancelled" orders on a given offer list.
  ///@param tko the arguments in memory of the taker order
  ///@return res the result of the taker order. If `offerId==0`, no resting order was posted on `msg.sender`'s behalf.
  function take(TakerOrder memory tko) external payable returns (TakerOrderResult memory res);
}
