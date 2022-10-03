// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOrder.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {Forwarder, MangroveOffer} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {IOrderLogic} from "mgv_src/strategies/interfaces/IOrderLogic.sol";
import {SimpleRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {MgvLib, IERC20} from "mgv_src/MgvLib.sol";

///@title MangroveOrder. A periphery contract to Mangrove protocol that implements resting limit orders.
///@notice A resting limit order is a taker order (offer taking) followed by a maker order (offer posting) when the taker order was partially filled.
/// E.g `msg.sender` wishes to buy 1 ETH at a limit average price of 1500 USD/ETH. After a market order:
/// 1. `msg.sender` gets a partial fill of 0.582 ETH (0.6 ETH - 3% fee) for 850 USD (thus at a price of ~1417 USD/ETH).
/// 2. This contract will then post a resting order to complement the market order as a bid for 0.4 ETH for 650 USD (thus at a price of 1625 USD)
/// 3. If the resting order is fully taken, the global average price for `msg.sender` will indeed be 1500 USD/ETH.
/// Note that if `msg.sender` allows for some slippage in its market order, the price of the resting order is computed taking the original price only (i.e without slippage).
/// Resting order may be posted with a time to leave, implemented in the form of a `__lastLook__` override that reneges on trade passed a certain timestamp.

contract MangroveOrder is Forwarder, IOrderLogic {
  ///@notice `expiring[outbound_tkn][inbound_tkn][offerId]` gives timestamp beyond which `offerId` on the (outbound_tkn, inbound_tkn)` offer list should renege on trade.
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
    // ASSUME 
    // `msg.sender` and `msg.sender`'s reserve added balances are (NAT_USER-`msg.value`, OUT_USER, IN_USER) for native, `tko.outbound_tkn` and `tko.inbound_tkn` balances.
    // `this` balances are (NAT_THIS+`msg.value`, OUT_THIS, IN_THIS)
    
    // Pulling funds from `msg.sender`'s reserve
    uint pulled = router().pull(tko.inbound_tkn, msg.sender, tko.takerGives, true);    
    require(pulled == tko.takerGives, "mgvOrder/mo/transferInFail");
    // STATE
    // [`msg.sender'] (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // [`this`] (NAT_THIS+`msg.value`, OUT_THIS, IN_THIS+`tko.takerGives`)
   
    (res.takerGot, res.takerGave, res.bounty, res.fee) = MGV.marketOrder({
      outbound_tkn: address(tko.outbound_tkn),
      inbound_tkn: address(tko.inbound_tkn),
      takerWants: tko.takerWants, // `tko.takerWants` includes user defined slippage
      takerGives: tko.takerGives,
      fillWants: tko.fillWants
    });

    // STATE
    // [`msg.sender'] (NAT_USER-`msg.value`, OUT_USER, IN_USER-`tko.takerGives`)
    // [`this`] (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS+`res.takerGot`, IN_THIS+`tko.takerGives`-`res.takerGave`)
    
    bool isComplete = checkCompleteness(tko, res);
    // requiring `partialFillNotAllowed => (isComplete \/ restingOrder)`
    require(!tko.partialFillNotAllowed || isComplete || tko.restingOrder, "mgvOrder/mo/noPartialFill");

    // sending inbound tokens to `msg.sender`'s reserve and sending back remaining outbound tokens
    if (res.takerGot > 0) {
      router().push(tko.outbound_tkn, msg.sender, res.takerGot);
    }
    if (!isComplete) {
      router().push(tko.inbound_tkn, msg.sender, tko.takerGives - res.takerGave);
    }
    // STATE
    // [`msg.sender'] (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
    // [`this`] (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)
    
    uint fund = msg.value + res.bounty; // using bounty as additional funds to provision the resting order
    if (tko.restingOrder && !isComplete) {
      // When posting a resting order `msg.sender` becomes a maker. 
      // For maker orders outbound tokens are what makers send. Here `msg.sender` wants to send `tko.inbound`.
      // The offer list on which this contract must post `msg.sender`'s resting order is thus `(tko.inbound_tkn, tko.outbound_tkn)` 
      // the call below will fill the memory data `res`.
      fund = postRestingOrder({
        tko: tko, 
        outbound_tkn: tko.inbound_tkn, 
        inbound_tkn: tko.outbound_tkn, 
        res: res, 
        fund: fund  
      }); 
      // STATE (`postRestingOrder` succeeded)
      // [`msg.sender'] (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // [`this`] (NAT_THIS, OUT_THIS, IN_THIS)
      // `fund == 0`
      // `ownerData[tko.inbound_tkn][tko.outbound_tkn][res.offerId]=={owner:msg.sender, wei_balance:rounding_error(fund,offerGasReq())}`
      // Mangrove emitted a unique `OfferWrite` log whose `maker` field is `address(this)` and `offerId` is `res.offerId`.

      // STATE (`postRestingOrder` failed)
      // [`msg.sender'] (NAT_USER-`msg.value`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // [`this`] (NAT_THIS+`msg.value`+`res.bounty`, OUT_THIS, IN_THIS)
      // `fund == msg.value + res.bounty`.
      // `res.offerId == 0`
    }
    
    if (fund > 0) {
      // NB this calls gives reentrancy power to callee, but OK since:
      // 1. callee is `msg.sender` so no grieffing risk of making this call fail for out of gas
      // 2. no function allows fund retrieval from `this` balance by `msg.sender`
      (bool noRevert,) = msg.sender.call{value: fund}("");
      require(noRevert, "mgvOrder/mo/refundFail");
      // STATE (`postRestingOrder` failed)
      // [`msg.sender'] (NAT_USER+`res.bounty`, OUT_USER+`res.takerGot`, IN_USER-`res.takerGave`)
      // [`this`] (NAT_THIS, OUT_THIS, IN_THIS)
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
  )
    internal returns (uint refund)
  {
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
