// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOrder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import {IMangrove} from "src/IMangrove.sol";
import {Forwarder, MangroveOffer} from "src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {IOrderLogic} from "src/strategies/interfaces/IOrderLogic.sol";
import {SimpleRouter} from "src/strategies/routers/SimpleRouter.sol";
import {TransferLib} from "src/strategies/utils/TransferLib.sol";
import {MgvLib, IERC20} from "src/MgvLib.sol";

///@title MangroveOrder. A periphery contract to Mangrove protocol that implements "Good till cancelled" (GTC) orders as well as "fill or kill" (FOK) orders.
///@notice A GTC order is a market buy (sell) order complemented by a bid (ask) order, called a resting order, that occurs when the buy (sell) order was partially filled.
/// * If the GTC is at a price $p$ and the market order was partially filled at a price $p_synch$, the resting order should be posted at a price $p_async$ such that $(p_synch+p_async)/2 = p$.
/// * If the taker tolerates some slippage, i.e., $p=p_0+slippage$, the price of the resting order is computed considering $p_0$ only ($p_synch+p_async/2=p_0$).
/// * The resting order comes with a "time to leave" after which the corresponding offer is no longer valid.
/// * The resting order can be cancelled or updated by its owner at any time.
/// E.g., `msg.sender` wishes to buy 1 ETH at a limit average price of 1500 USD/ETH + 1% slippage tolerance. After a market buy order:
/// 1. `msg.sender` gets a partial fill of 0.582 ETH (0.6 ETH - 3% fee) for 850 USD (thus at a price of ~1417 USD/ETH).
/// 2. This contract will then post a resting bid of 0.4 ETH for 650 USD (thus at a price of 1625 USD)
/// 3. If the resting order is fully taken, the global average price for `msg.sender` will indeed be 1500 USD/ETH.
/// A FOK order is simply a buy or sell order that is either completely filled or cancelled. No resting order is posted.
///@dev requiring no partial fill *and* a resting order is interpreted here as an instruction to revert if the resting order fails to be posted (e.g., if below density).

contract MangroveOrder is Forwarder, IOrderLogic {
  ///@notice `expiring[outbound_tkn][inbound_tkn][offerId]` gives timestamp beyond which `offerId` on the `(outbound_tkn, inbound_tkn)` offer list should renege on trade.
  mapping(IERC20 => mapping(IERC20 => mapping(uint => uint))) public expiring;

  ///@notice MangroveOrder constructor extends Forwarder with a simple router.
  constructor(IMangrove mgv, address deployer, uint gasreq) Forwarder(mgv, new SimpleRouter()) {
    // we start by setting gasreq for this logic to execute a trade in the worst case scenario.
    // gas requirements implied by router are taken into account separately.
    setGasreq(gasreq); // for fixed simple router overhead, this logic fails when `offer_gasreq` < 20K in prod.
    // adding `this` contract to authorized makers of the router before setting admin rights of the router to deployer
    router().bind(address(this));
    router().setAdmin(deployer);
    // if `msg.sender` is not `deployer`, setting admin of `this` to `deployer`.
    // `deployer` will thus be able to call `activate` on `this` to enable trading on particular assets.
    if (msg.sender != deployer) {
      setAdmin(deployer);
    }
  }

  ///Checks the current timestamps are reneges on trade (by reverting) if the offer has expired.
  ///@inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal virtual override returns (bytes32) {
    uint exp = expiring[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)][order.offerId];
    require(exp == 0 || block.timestamp <= exp, "mgvOrder/expired");
    return super.__lastLook__(order);
  }

  ///@notice compares a taker order with a market order results and checks whether the order was entirely filled
  ///@param tko the taker order
  ///@param res the market order result
  function checkCompleteness(TakerOrder calldata tko, TakerOrderResult memory res) internal pure returns (bool) {
    // The order can be incomplete if the price becomes too high or the end of the book is reached.
    if (tko.fillWants) {
      // when fillWants is true, the market order stops when `takerWants` units of `outbound_tkn` have been obtained;
      return res.takerGot + res.fee >= tko.takerWants;
    } else {
      // otherwise, the market order stops when `takerGives` units of `inbound_tkn` have been sold.
      return res.takerGave >= tko.takerGives;
    }
  }

  ///@inheritdoc IOrderLogic
  function take(TakerOrder calldata tko) external payable returns (TakerOrderResult memory res) {
    // Notations:
    // NAT_USER: initial value of `msg.sender.balance` (native balance of user)
    // OUT/IN_USER: initial value of `tko.[out|in]bound_tkn.balanceOf(reserve())` (user's reserve balance of tokens)
    // NAT_THIS: initial value of `address(this).balance` (native balance of `this`)
    // OUT/IN_THIS: initial value of `tko.[out|in]bound_tkn.balanceOf(address(this))` (`this` balance of tokens)

    // PRE:
    // * User balances: (NAT_USER -`msg.value`, OUT_USER, IN_USER)
    // * `this` balances: (NAT_THIS +`msg.value`, OUT_THIS, IN_THIS)

    // Pulling funds from `msg.sender`'s reserve
    uint pulled = router().pull(tko.inbound_tkn, reserve(), tko.takerGives, true);
    require(pulled == tko.takerGives, "mgvOrder/mo/transferInFail");

    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // * (NAT_THIS+`msg.value`, OUT_THIS, IN_THIS+`tko.takerGives`)

    (res.takerGot, res.takerGave, res.bounty, res.fee) = MGV.marketOrder({
      outbound_tkn: address(tko.outbound_tkn),
      inbound_tkn: address(tko.inbound_tkn),
      takerWants: tko.takerWants, // `tko.takerWants` includes user defined slippage
      takerGives: tko.takerGives,
      fillWants: tko.fillWants
    });

    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS+`res.takerGot`, IN_THIS+`tko.takerGives`-`res.takerGave`)

    bool isComplete = checkCompleteness(tko, res);
    // when `!restingOrder` this implements FOK. When `restingOrder` is positioned this reverts only if resting order fails to be posted.
    // therefore we require `partialFillNotAllowed => (isComplete \/ restingOrder)`
    require(!tko.partialFillNotAllowed || isComplete || tko.restingOrder, "mgvOrder/mo/noPartialFill");

    // sending inbound tokens to `msg.sender`'s reserve and sending back remaining outbound tokens
    if (res.takerGot > 0) {
      router().push(tko.outbound_tkn, reserve(), res.takerGot);
    }
    if (!isComplete) {
      router().push(tko.inbound_tkn, reserve(), tko.takerGives - res.takerGave);
    }
    // POST:
    // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)

    ///@dev collected bounty compensates gas consumption for the failed offer but could be lower than the cost of an additional native token transfer
    /// instead of sending the bounty back to `msg.sender` we recycle it into the resting order's provision (so `msg.sender` can retrieve it when deprovisioning).
    /// corner case: if the bounty is large enough, this will make posting of the resting order fail because of `gasprice` overflow. The funds will then be sent back to `msg.sender` (see below).
    uint fund = msg.value + res.bounty;

    if (tko.restingOrder && !isComplete) {
      // When posting a resting order `msg.sender` becomes a maker.
      // For maker orders, outbound tokens are what makers send. Here `msg.sender` sends `tko.inbound`.
      // The offer list on which this contract must post `msg.sender`'s resting order is thus `(tko.inbound_tkn, tko.outbound_tkn)`
      // the call below will fill the memory data `res`.
      fund =
        postRestingOrder({tko: tko, outbound_tkn: tko.inbound_tkn, inbound_tkn: tko.outbound_tkn, res: res, fund: fund});
      // POST (case `postRestingOrder` succeeded):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS, OUT_THIS, IN_THIS)
      // * `fund == 0`
      // * `ownerData[tko.inbound_tkn][tko.outbound_tkn][res.offerId].owner == msg.sender`.
      // * Mangrove emitted an `OfferWrite` log whose `maker` field is `address(this)` and `offerId` is `res.offerId`.

      // POST (case `postRestingOrder` failed):
      // * (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)
      // * `fund == msg.value + res.bounty`.
      // * `res.offerId == 0`
    }

    if (fund > 0) {
      // NB this calls gives reentrancy power to callee, but OK since:
      // 1. callee is `msg.sender` so no griefing risk of making this call fail for out of gas
      // 2. no function allows fund retrieval from `this` balance by `msg.sender`
      (bool noRevert,) = msg.sender.call{value: fund}("");
      require(noRevert, "mgvOrder/mo/refundFail");
      // POST (`postRestingOrder` failed)
      // * (NAT_USER+`res.bounty`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // * (NAT_THIS, OUT_THIS, IN_THIS)
    }
    emit OrderSummary({
      mangrove: MGV,
      outbound_tkn: tko.outbound_tkn,
      inbound_tkn: tko.inbound_tkn,
      fillWants: tko.fillWants,
      taker: msg.sender,
      takerGot: res.takerGot,
      takerGave: res.takerGave,
      penalty: res.bounty
    });
    return res;
  }

  ///@notice posts a maker order on the (`outbound_tkn`, `inbound_tkn`) offer list.
  ///@param fund amount of WEIs used to cover for the offer bounty (covered gasprice is derived from `fund`).
  function postRestingOrder(
    TakerOrder calldata tko,
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    TakerOrderResult memory res,
    uint fund
  ) internal returns (uint refund) {
    res.offerId = _newOffer(
      NewOfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: tko.makerWants - (res.takerGot + res.fee), // tko.makerWants is before slippage
        gives: tko.makerGives - res.takerGave,
        gasreq: offerGasreq(),
        pivotId: tko.pivotId,
        fund: fund,
        caller: msg.sender,
        noRevert: true // returns 0 when MGV reverts
      })
    );

    if (res.offerId == 0) {
      // either:
      // - residual gives is below current density
      // - `fund` is too low and would yield a gasprice that is lower than Mangrove's
      // - `fund` is too high and would yield a gasprice overflow
      // - offer list is not active (Mangrove is not dead otherwise market order would have reverted)
      // reverting when partial fill is not an option
      require(!tko.partialFillNotAllowed, "mgvOrder/mo/noPartialFill");
      // `fund` is no longer needed so sending it back to `msg.sender`
      refund = fund;
    } else {
      // offer was successfully posted
      // if one wants to maintain an inverse mapping owner => offerIds
      __logOwnershipRelation__({
        owner: msg.sender,
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        offerId: res.offerId
      });
      // setting a time to live for the resting order
      if (tko.timeToLiveForRestingOrder > 0) {
        expiring[outbound_tkn][inbound_tkn][res.offerId] = block.timestamp + tko.timeToLiveForRestingOrder;
      }
    }
  }

  /**
   * @notice This is invoked for each new offer created for resting orders, e.g., to maintain an inverse mapping from owner to offers.
   * @param owner the owner of the offer new offer
   * @param outbound_tkn the outbound token used to identify the order book
   * @param inbound_tkn the inbound token used to identify the order book
   * @param offerId the id of the new offer
   */
  function __logOwnershipRelation__(address owner, IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    internal
    virtual
  {
    owner; //ssh
    outbound_tkn; //ssh
    inbound_tkn; //ssh
    offerId; //ssh
  }
}
