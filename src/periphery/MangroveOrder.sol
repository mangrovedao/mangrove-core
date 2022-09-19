// SPDX-License-Identifier:	BSD-2-Clause

// Direct.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;
import "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import "mgv_src/strategies/interfaces/IOrderLogic.sol";
import "mgv_src/strategies/routers/SimpleRouter.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";

contract MangroveOrder is Forwarder, IOrderLogic {
  // `expiring[outbound_tkn][inbound_tkn][offerId]` gives timestamp beyond which the offer should renege on trade.
  mapping(IERC20 => mapping(IERC20 => mapping(uint => uint))) public expiring;

  constructor(IMangrove mgv, address deployer)
    Forwarder(mgv, new SimpleRouter())
  {
    setGasreq(30000); // fails < 20K
    // adding `this` contract to authorized makers of the router before setting admin rights of the router to deployer
    router().bind(address(this));
    if (deployer != msg.sender) {
      setAdmin(deployer);
      router().setAdmin(deployer);
    }
  }

  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bytes32)
  {
    uint exp = expiring[IERC20(order.outbound_tkn)][IERC20(order.inbound_tkn)][
      order.offerId
    ];
    require(exp == 0 || block.timestamp <= exp, "mgvOrder/expired");
    return "";
  }

  // revert when order was partially filled and it is not allowed
  function checkCompleteness(
    TakerOrder calldata tko,
    TakerOrderResult memory res
  ) internal pure returns (bool isPartial) {
    // revert if sell is partial and `partialFillNotAllowed` and not posting residual
    if (tko.selling) {
      return res.takerGave >= tko.gives;
    } else {
      return res.takerGot + res.fee >= tko.wants;
    }
  }

  // `this` contract MUST have approved Mangrove for inbound token transfer
  // `msg.sender` MUST have approved `this` contract for at least the same amount
  // provision for posting a resting order MAY be sent when calling this function
  // gasLimit of this `tx` MUST be at least `(retryNumber+1)*gasForMarketOrder`
  // msg.value SHOULD contain enough native token to cover for the resting order provision
  // msg.value MUST be 0 if `!restingOrder` otherwise transferred WEIs are burnt.

  function take(TakerOrder calldata tko)
    external
    payable
    returns (TakerOrderResult memory res)
  {
    (IERC20 outbound_tkn, IERC20 inbound_tkn) = tko.selling
      ? (tko.quote, tko.base)
      : (tko.base, tko.quote);
    // pulling directly from msg.sender would require caller to approve `this` in addition to the `this.router()`
    // so pulling funds from taker's reserve (note this can be the taker's wallet depending on the router)
    uint pulled = router().pull(inbound_tkn, msg.sender, tko.gives, true);
    require(pulled == tko.gives, "mgvOrder/mo/transferInFail");
    // passing an iterated market order with the transferred funds
    for (uint i = 0; i < tko.retryNumber + 1; i++) {
      if (tko.gasForMarketOrder != 0 && gasleft() < tko.gasForMarketOrder) {
        break;
      }
      (uint takerGot_, uint takerGave_, uint bounty_, uint fee_) = MGV
        .marketOrder({
          outbound_tkn: address(outbound_tkn),
          inbound_tkn: address(inbound_tkn),
          takerWants: tko.wants, // `tko.wants` includes user defined slippage
          takerGives: tko.gives,
          fillWants: tko.selling ? false : true // only buy order should try to fill takerWants
        });
      res.takerGot += takerGot_;
      res.takerGave += takerGave_;
      res.bounty += bounty_;
      res.fee += fee_;
      if (takerGot_ == 0 && bounty_ == 0) {
        break;
      }
    }
    bool isComplete = checkCompleteness(tko, res);
    // requiring `partialFillNotAllowed` => `isComplete \/ restingOrder`
    require(
      !tko.partialFillNotAllowed || isComplete || tko.restingOrder,
      "mgvOrder/mo/noPartialFill"
    );

    // sending received tokens to taker's reserve
    if (res.takerGot > 0) {
      router().push(outbound_tkn, msg.sender, res.takerGot);
    }

    // at this points the following invariants hold:
    // 1. taker received `takerGot` outbound tokens
    // 2. `this` contract inbound token balance is now equal to `tko.gives - takerGave`.
    // 3. `this` contract's WEI balance is credited of `msg.value + bounty`

    if (tko.restingOrder && !isComplete) {
      // When posting a resting order the taker becomes a maker, and `inbound_tkn` for an offer is what the maker receives,
      // so the offer for this resting order must have `inbound_tkn` set to `outbound_tkn` such that the taker
      // receives these when the offer is taken, and the offer's `outbound_tkn` becomes `inbound_tkn`.
      postRestingOrder({
        tko: tko,
        outbound_tkn: inbound_tkn,
        inbound_tkn: outbound_tkn,
        res: res
      });
    } else {
      // either fill was complete or taker does not want to post residual as a resting order
      // transferring remaining inbound tokens to msg.sender
      router().push(inbound_tkn, msg.sender, tko.gives - res.takerGave);

      // transferring potential bounty and msg.value back to the taker
      if (msg.value + res.bounty > 0) {
        // NB this calls gives reentrancy power to caller
        (bool noRevert, ) = msg.sender.call{value: msg.value + res.bounty}("");
        require(noRevert, "mgvOrder/mo/refundFail");
      }
      emit OrderSummary({
        mangrove: MGV,
        base: tko.base,
        quote: tko.quote,
        selling: tko.selling,
        taker: msg.sender,
        takerGot: res.takerGot,
        takerGave: res.takerGave,
        penalty: res.bounty,
        restingOrderId: 0
      });
      return res;
    }
  }

  function postRestingOrder(
    TakerOrder calldata tko,
    IERC20 inbound_tkn,
    IERC20 outbound_tkn,
    TakerOrderResult memory res
  ) internal {
    // resting limit order for the residual of the taker order
    // this call will credit offer owner virtual account on Mangrove with msg.value before trying to post the offer
    // `offerId_==0` if mangrove rejects the update because of low density.
    // call may not revert because of insufficient funds
    res.offerId = _newOffer(
      NewOfferData({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: tko.makerWants - (res.takerGot + res.fee), // tko.makerWants is before slippage
        gives: tko.makerGives - res.takerGave,
        gasreq: offerGasreq(),
        pivotId: 0,
        fund: msg.value,
        caller: msg.sender,
        noRevert: true // returns 0 when MGV reverts
      })
    );
    // we summarize the market order (if offerId == 0 no resting order was posted).
    emit OrderSummary({
      mangrove: MGV,
      base: tko.base,
      quote: tko.quote,
      selling: tko.selling,
      taker: msg.sender,
      takerGot: res.takerGot,
      takerGave: res.takerGave,
      penalty: res.bounty,
      restingOrderId: res.offerId
    });

    if (res.offerId == 0) {
      // unable to post resting order
      // reverting when partial fill is not an option
      require(!tko.partialFillNotAllowed, "mgvOrder/mo/noPartialFill");
      // sending remaining pulled funds back to taker --when partial fill is allowed
      require(
        TransferLib.transferToken(
          outbound_tkn,
          msg.sender,
          tko.gives - res.takerGave
        ),
        "mgvOrder/mo/transferInFail"
      );
      // msg.value is no longer needed so sending it back to msg.sender along with possible collected bounty
      if (msg.value + res.bounty > 0) {
        (bool noRevert, ) = msg.sender.call{value: msg.value + res.bounty}("");
        require(noRevert, "mgvOrder/mo/refundProvisionFail");
      }
    } else {
      // offer was successfully posted
      // if one wants to maintain an inverse mapping owner => offerIds
      __logOwnershipRelation__({
        owner: msg.sender,
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        offerId: res.offerId
      });

      // crediting caller's balance with amount of offered tokens (transferred from caller at the beginning of this function)
      // so that the offered tokens can be transferred when the offer is taken.
      router().push(outbound_tkn, msg.sender, tko.gives - res.takerGave);

      // setting a time to live for the resting order
      if (tko.timeToLiveForRestingOrder > 0) {
        expiring[outbound_tkn][inbound_tkn][res.offerId] =
          block.timestamp +
          tko.timeToLiveForRestingOrder;
      }
    }
  }

  function __posthookSuccess__(
    MgvLib.SingleOrder calldata order,
    bytes32 makerData
  ) internal virtual override returns (bytes32) {
    bytes32 repostData = super.__posthookSuccess__(order, makerData);
    if (repostData != "posthook/reposted") {
      // if offer was not to reposted, if is now off the book but provision is still locked
      // calling retract offer will recover the provision and transfer them to offer owner
      retractOffer(
        IERC20(order.outbound_tkn),
        IERC20(order.inbound_tkn),
        order.offerId,
        true
      );
    }
    return "";
  }

  /**
  @notice This is invoked for each new offer created for resting orders, e.g., to maintain an inverse mapping from owner to offers.
  @param owner the owner of the offer new offer
  @param outbound_tkn the outbound token used to identify the order book
  @param inbound_tkn the inbound token used to identify the order book
  @param offerId the id of the new offer
  */
  function __logOwnershipRelation__(
    address owner,
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId
  ) internal virtual {
    owner; //ssh
    outbound_tkn; //ssh
    inbound_tkn; //ssh
    offerId; //ssh
  }
}
