// SPDX-License-Identifier:	BSD-2-Clause

// OfferForwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import {Forwarder} from "src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {IMakerLogic} from "src/strategies/interfaces/IMakerLogic.sol";
import {AaveRouter} from "src/strategies/routers/AaveRouter.sol";
import {IERC20, MgvLib} from "src/MgvLib.sol";
import {IMangrove} from "src/IMangrove.sol";
import {AbstractRouter} from "src/strategies/routers/AbstractRouter.sol";
import {TransferLib} from "src/strategies/utils/TransferLib.sol";

//Using a AaveDeepRouter, it will borrow and deposit on behalf of the reserve - but as a pool, and keep a contract-local balance to avoid spending gas
// gas overhead of the router for each order:
// - supply ~ 250K
// - borrow ~ 360K
//This means that yield and interest should be handled for the reserve here, somehow.
contract PooledForwarder is IMakerLogic, Forwarder {
  // balance of token for an owner - the pool has a balance in aave and on `this`.
  mapping(IERC20 => mapping(address => uint)) internal ownerBalance;

  constructor(IMangrove mgv, address deployer, address aaveAddressProvider)
    Forwarder(mgv, new AaveRouter(aaveAddressProvider, 0, 1 , 700_000), 30_000)
  {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    setAdmin(deployer);
    router_.setAdmin(deployer); // consider if admin should be this contract?
  }

  event CreditUserBalance(IERC20 indexed token, address indexed owner, uint amount);
  event DebitUserBalance(IERC20 indexed token, address indexed owner, uint amount);

  // Increases balance of token for owner.
  function increaseBalance(IERC20 token, address owner, uint amount) private returns (uint) {
    emit CreditUserBalance(token, owner, amount);
    // log balance modification to event
    uint newBalance = ownerBalance[token][owner] + amount;
    ownerBalance[token][owner] = newBalance;
    return newBalance;
  }

  // Decrease balance of token for owner.
  function decreaseBalance(IERC20 token, address owner, uint amount) private returns (uint) {
    uint currentBalance = ownerBalance[token][owner];
    require(currentBalance >= amount, "PooledForwarder/decreaseBalance/amountMoreThanBalance");
    emit DebitUserBalance(token, owner, amount);
    unchecked {
      uint newBalance = currentBalance - amount;
      ownerBalance[token][owner] = newBalance;
      return newBalance;
    }
  }

  function getBalance(IERC20 token, address owner) public view returns (uint) {
    return ownerBalance[token][owner];
  }

  // As imposed by IMakerLogic we provide an implementation of newOffer for this contract
  function newOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice, // keeping gasprice here in order to expose the same interface as `OfferMaker` contracts.
    uint pivotId
  ) public payable returns (uint offerId) {
    gasprice; // ignoring gasprice that will be derived based on msg.value.
    // we post the offer without any checks - it is up to the owner to have deposited enough.
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false, // propagates Mangrove's revert data in case of newOffer failure
        owner: msg.sender
      })
    );
  }

  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);

    // only increase balance for owner, do not transfer any tokens. This is done in posthook.
    // TODO: comment on overflow punishes maker
    increaseBalance(inTkn, owner, amount);
    return 0;
  }

  // When pulling from Aave, take everything the maker can get
  // This way, we don't have to pull from Aave every time an offer is taken
  // If posthook fails, tokens are left on the contract and not pushed to Aave
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    // Do not call super as it will route to reserve.
    // TODO consider decoupling from normal Forwarder router handling - split Forwarder in two?

    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    uint balance = getBalance(outTkn, owner);
    // First we decrease balance - will revert if owner does not have enough.
    decreaseBalance(outTkn, owner, amount);

    // check if `this` has enough to satisfy order, otherwise pull _everything_ from aave.
    if (outTkn.balanceOf(address(this)) < amount) {
      // we do not verify result - we assume there is now enough, otherwise the order will fail.
      //TODO aave could be out of funds.
      AbstractRouter router_ = router();
      uint pulled = router_.pull(outTkn, address(router_), amount, false /* pull everything */ );
      // return whether some is still missing.
      return pulled >= amount ? 0 : amount - pulled;
    }

    // we have decreased owner's balance with the exact amount, so nothing more needed.
    return 0;
  }

  function deposit(IERC20 token, uint amount) public returns (uint) {
    bool success = TransferLib.transferTokenFrom(token, reserve(msg.sender), address(this), amount);
    // funds are now in local pool
    // TODO: Should we push to Aave or wait for next order?
    if (success) {
      increaseBalance(token, msg.sender, amount);
      // push all we have - we do not care if it succeeds.
      router().push(token, address(this), token.balanceOf(address(this)));
      return amount;
    }
    return 0;
  }

  function withdraw(IERC20 token, uint amount) public returns (bool) {
    uint ownersBalance = getBalance(token, msg.sender);
    require(ownersBalance >= amount, "withdraw/notEnoughBalance");
    // update state before calling contracts
    decreaseBalance(token, msg.sender, amount);

    uint thisBalance = token.balanceOf(address(this));

    // pull missing from aave into local pool
    if (thisBalance < amount) {
      uint pulled = router().pull(token, address(this), amount - thisBalance, true);
      require(pulled + thisBalance == amount, "withdraw/aavePulledWrongAmount");
    }

    // transfer to owner
    bool success = TransferLib.transferToken(token, reserve(msg.sender), amount);
    return success;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    // reposts residual if any (conservative hook)
    bytes32 repost_status = super.__posthookSuccess__(order, makerData);

    return pushAllToAave(order);
  }

  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    return pushAllToAave(order);
  }

  function pushAllToAave(MgvLib.SingleOrder calldata order) internal returns (bytes32) {
    AbstractRouter router_ = router();
    IERC20 outTk = IERC20(order.outbound_tkn);
    IERC20 inTk = IERC20(order.inbound_tkn);
    // Could be cheaper to check balance first
    // uint outBalance = outTk.balanceOf(address(this));
    // uint inBalance = inTk.balanceOf(address(this));
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = outTk;
    tokens[1] = inTk;
    router_.flush(tokens, address(router_));

    //TODO I am not sure why we need all this reporting?
    if (outBalance == 0 && inBalance > 0) {
      if (inBalance - inPushed > 0) {
        return "posthook/inNotFullyPushed";
      } else {
        return "posthook/inPushed";
      }
    }

    if (outBalance > 0 && inBalance == 0) {
      if (outBalance - outPushed > 0) {
        return "posthook/outNotFullyPushed";
      } else {
        return "posthook/outPushed";
      }
    }
    if (outBalance == 0 && inBalance == 0) {
      return "posthook/nothingPushed";
    }

    if (outBalance - outPushed > 0 && inBalance - inPushed > 0) {
      return "posthook/outAndInNotFullyPushed";
    } else if (outBalance - outPushed > 0) {
      return "posthook/outNotFullyPushed";
    } else if (inBalance - inPushed > 0) {
      return "posthook/inNotFullyPushed";
    }
    return "posthook/bothPushed";
  }
}
