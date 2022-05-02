// SPDX-License-Identifier:	BSD-2-Clause

// Persistent.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "../OfferLogics/MultiUsers/Persistent.sol";
import "../interfaces/IOrderLogic.sol";

contract MangroveOrder is MultiUserPersistent, IOrderLogic {
  using P.Local for P.Local.t;

  // `blockToLive[token1][token2][offerId]` gives block number beyond which the offer should renege on trade.
  mapping(address => mapping(address => mapping(uint => uint))) public expiring;
  uint public GASLIMIT = 10_000_000;

  constructor(address payable _MGV) MangroveOffer(_MGV) {}

  function set_gasLimit(uint gasLimit) external onlyAdmin {
    GASLIMIT = gasLimit;
  }

  // transfer with no revert
  function transferERC(
    IEIP20 token,
    address recipient,
    uint amount
  ) internal returns (bool) {
    if (amount == 0) {
      return true;
    }
    (bool success, bytes memory data) = address(token).call(
      abi.encodeWithSelector(token.transfer.selector, recipient, amount)
    );
    return (success && (data.length == 0 || abi.decode(data, (bool))));
  }

  function __lastLook__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    uint exp = expiring[order.outbound_tkn][order.inbound_tkn][order.offerId];
    return (exp == 0 || block.number <= exp);
  }

  // revert when order was partially filled and it is not allowed
  function checkCompleteness(
    address outbound_tkn,
    address inbound_tkn,
    TakerOrder calldata tko,
    TakerOrderResult memory res
  ) internal view returns (bool isPartial) {
    // revert if sell is partial and `partialFillNotAllowed` and not posting residual
    if (tko.selling) {
      return res.takerGave >= tko.gives;
    }
    // revert if buy is partial and `partialFillNotAllowed` and not posting residual
    if (!tko.selling) {
      (, P.Local.t local) = MGV.config(outbound_tkn, inbound_tkn);
      return res.takerGot >= tko.wants - (tko.wants * local.fee()) / 10_000;
    }
  }

  // `this` contract MUST have approved Mangrove for inbound token transfer
  // `msg.sender` MUST have approved `this` contract for at least the same amount
  // provision for posting a resting order MAY be sent when calling this function
  // gasLimit of this `tx` MUST be at least `(retryNumber+1)*gasForMarketOrder`
  // msg.value SHOULD contain enough native token to cover for the resting order provision
  // msg.value MUST be 0 if `!restingOrder` otherwise tranfered WEIs are burnt.

  function take(TakerOrder calldata tko)
    external
    payable
    returns (TakerOrderResult memory res)
  {
    (address outbound_tkn, address inbound_tkn) = tko.selling
      ? (tko.quote, tko.base)
      : (tko.base, tko.quote);
    require(
      IEIP20(inbound_tkn).transferFrom(msg.sender, address(this), tko.gives),
      "mgvOrder/mo/transferInFail"
    );
    // passing an iterated market order with the transfered funds
    for (uint i = 0; i < tko.retryNumber + 1; i++) {
      if (gasleft() < tko.gasForMarketOrder) {
        break;
      }
      (uint takerGot_, uint takerGave_, uint bounty_) = MGV.marketOrder({
        outbound_tkn: outbound_tkn, // expecting quote (outbound) when selling
        inbound_tkn: inbound_tkn,
        takerWants: tko.wants,
        takerGives: tko.gives,
        fillWants: tko.selling ? false : true // only buy order should try to fill takerWants
      });
      res.takerGot += takerGot_;
      res.takerGave += takerGave_;
      res.bounty += bounty_;
      if (takerGot_ == 0 && bounty_ == 0) {
        break;
      }
    }
    bool isComplete = checkCompleteness(outbound_tkn, inbound_tkn, tko, res);
    // requiring `partialFillNotAllowed` => `isComplete \/ restingOrder`
    require(
      !tko.partialFillNotAllowed || isComplete || tko.restingOrder,
      "mgvOrder/mo/noPartialFill"
    );

    // sending received tokens to taker
    if (res.takerGot > 0) {
      require(
        IEIP20(outbound_tkn).transfer(msg.sender, res.takerGot),
        "mgvOrder/mo/transferOutFail"
      );
    }

    // at this points the following invariants hold:
    // taker received `takerGot` outbound tokens
    // `this` contract inbound token balance is credited of `tko.gives - takerGave`. NB this amount cannot be redeemed by taker yet since `creditToken` was not called
    // `this` contract's WEI balance is credited of `msg.value + bounty`

    if (tko.restingOrder && !isComplete) {
      // resting limit order for the residual of the taker order
      // this call will credit offer owner virtual account on Mangrove with msg.value before trying to post the offer
      // `offerId_==0` if mangrove rejects the update because of low density.
      // If user does not have enough funds, call will revert
      res.offerId = newOfferInternal({
        outbound_tkn: inbound_tkn,
        inbound_tkn: outbound_tkn,
        wants: tko.wants - res.takerGot,
        gives: tko.gives - res.takerGave,
        gasreq: OFR_GASREQ,
        gasprice: 0,
        pivotId: 0, // offer should be best in the book
        caller: msg.sender, // msg.sender is the owner of the resting order
        provision: msg.value
      });
      if (res.offerId == 0) {
        // unable to post resting order
        // reverting because partial fill is not an option
        require(!tko.partialFillNotAllowed, "mgvOrder/mo/noPartialFill");
        // sending partial fill to taker --when partial fill is allowed
        require(
          IEIP20(inbound_tkn).transfer(msg.sender, tko.gives - res.takerGave),
          "mgvOrder/mo/transferInFail"
        );
        // msg.value is no longer needed so sending it back to msg.sender along with possible collected bounty
        if (msg.value + res.bounty > 0) {
          (bool noRevert, ) = msg.sender.call{value: msg.value + res.bounty}(
            ""
          );
          require(noRevert, "mgvOrder/mo/refundProvisionFail");
        }
        return res;
      } else {
        // offer was successfully posted
        // crediting offer owner's balance with amount of offered tokens (transfered from caller at the begining of this function)
        // NB `inb` is the outbound token for the resting order
        creditToken(inbound_tkn, msg.sender, tko.gives - res.takerGave);

        // setting a time to live for the resting order
        if (tko.blocksToLiveForRestingOrder > 0) {
          expiring[inbound_tkn][outbound_tkn][res.offerId] =
            block.number +
            tko.blocksToLiveForRestingOrder;
        }
        return res;
      }
    } else {
      // either fill was complete or taker does not want to post residual as a resting order
      // transfering remaining inbound tokens to msg.sender
      require(
        IEIP20(inbound_tkn).transfer(msg.sender, tko.gives - res.takerGave),
        "mgvOrder/mo/transferInFail"
      );
      // transfering potential bounty and msg.value back to the taker
      if (msg.value + res.bounty > 0) {
        (bool noRevert, ) = msg.sender.call{value: msg.value + res.bounty}("");
        require(noRevert, "mgvOrder/mo/refundFail");
      }
      return res;
    }
  }

  // default __get__ method inherited from `MultiUser` is to fetch liquidity from `this` contract
  // we do not want to change this since `creditToken`, during the `take` function that created the resting order, will allow one to fulfill any incoming order
  // However, default __put__ method would deposit tokens in this contract, instead we want forward received liquidity to offer owner

  function __put__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    address owner = ownerOf(
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId
    );
    // IEIP20(order.inbound_tkn).transfer(owner, amount);
    // return 0;
    return transferERC(IEIP20(order.inbound_tkn), owner, amount) ? 0 : amount;
  }

  // we need to make sure that if offer is taken and not reposted (because of insufficient provision or density) then remaining provision and outbound tokens are sent back to owner

  function redeemAll(ML.SingleOrder calldata order, address owner)
    internal
    returns (bool)
  {
    // Resting order was not reposted, sending out/in tokens to original taker
    // balOut was increased during `take` function and is now possibly empty
    uint balOut = tokenBalanceOf[order.outbound_tkn][owner];
    if (!transferERC(IEIP20(order.outbound_tkn), owner, balOut)) {
      emit LogIncident(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        "mgvOrder/redeemAll/transferOut"
      );
      return false;
    }
    // should not move `debitToken` before the above transfer that does not revert when failing
    // offer owner might still recover tokens later using `redeemToken` external call
    debitToken(order.outbound_tkn, owner, balOut);
    // balIn contains the amount of tokens that was received during the trade that triggered this posthook
    uint balIn = tokenBalanceOf[order.inbound_tkn][owner];
    if (!transferERC(IEIP20(order.inbound_tkn), owner, balIn)) {
      emit LogIncident(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        "mgvOrder/redeemAll/transferIn"
      );
      return false;
    }
    debitToken(order.inbound_tkn, owner, balIn);
    return true;
  }

  function __posthookSuccess__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool)
  {
    // trying to repost offer remainder
    if (super.__posthookSuccess__(order)) {
      // if `success` then offer residual was reposted and nothing needs to be done
      // else we need to send the remaining outbounds tokens to owner and their remaining provision on mangrove (offer was deprovisioned in super call)
      return true;
    }
    address owner = ownerOf(
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId
    );
    // returning all inbound/outbound tokens that belong to the original taker to their balance
    if (!redeemAll(order, owner)) {
      return false;
    }
    // returning remaining WEIs
    // NB because offer was not reposted, it has already been deprovisioned during `super.__posthookSuccess__`
    // NB `_withdrawFromMangrove` performs a call and might be subject to reentrancy.
    debitOnMgv(owner, mgvBalance[owner]);
    // NB cannot revert here otherwise user will not be able to collect automatically in/out tokens (above transfers)
    // if the caller of this contract is not an EOA, funds would be lost.
    if (!_withdrawFromMangrove(payable(owner), mgvBalance[owner])) {
      // this code might be reached if `owner` is not an EOA and has no `receive` or `fallback` payable method.
      // in this case the provision is lost and one should not revert, to the risk of being unable to recover in/out tokens transfered earlier
      emit LogIncident(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        "mgvOrder/posthook/transferWei"
      );
      return false;
    }
    return true;
  }

  // in case of an offer with a blocks-to-live option enabled, resting order might renege on trade
  // in this case, __posthookFallback__ will be called.
  function __posthookFallback__(
    ML.SingleOrder calldata order,
    ML.OrderResult calldata result
  ) internal virtual override returns (bool) {
    result; //shh
    address owner = ownerOf(
      order.outbound_tkn,
      order.inbound_tkn,
      order.offerId
    );
    return redeemAll(order, owner);
  }

  // TODO:
  // * Solidity tests
  // * Decentralized way to recover the status of the resting orders that belong to a given wallet
}
