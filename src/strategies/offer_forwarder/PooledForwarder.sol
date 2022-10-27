// SPDX-License-Identifier:	BSD-2-Clause

// OfferForwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

import "src/strategies/offer_forwarder/abstract/Forwarder.sol";
import "src/strategies/interfaces/IMakerLogic.sol";
import "src/strategies/routers/AavePoolRouter.sol";

contract PooledForwarder is IMakerLogic, Forwarder {
  constructor(IMangrove mgv, address deployer, address aaveAddresProvider)
    Forwarder(mgv, new AavePoolRouter( aaveAddresProvider, 0, 1 ), 30_000)
  {
    AbstractRouter router_ = router();
    router_.bind(address(this));
    setAdmin(deployer);
    router_.setAdmin(deployer);
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

  // only increase balance for owner, do not transfer any tokens. This is done in posthook.
  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    AavePoolRouter aRouter = AavePoolRouter(address(router()));
    aRouter.increaseBalance(inTkn, owner, amount);
    // uint pushed = aRouter.push(inTkn, reserve(owner), amount); // wait until posthook to push everything
    return 0;
  }

  // When pulling from Aave, take everything the maker can get
  // This way, we dont have to pull from Aave everytime an offer is taken
  // If posthook fails, tokens are left on the contract and not pushed to Aave
  // Is this okay, since the router keeps track of balances?
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    IERC20 outTkn = IERC20(order.outbound_tkn);
    IERC20 inTkn = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    AavePoolRouter aRouter = AavePoolRouter(address(router()));
    uint balance = aRouter.getBalance(outTkn, owner);
    // Someone elses offer could have been taken and their posthook fails, then the contract holds funds, these funds are not owned by the owner of this offer.
    // Should we have bookkeeping on the contracts funds and the funds on Aave?
    if (balance >= amount && outTkn.balanceOf(address(this)) >= amount) {
      aRouter.decreaseBalance(outTkn, owner, amount);
      return 0;
    }

    if (balance >= amount) {
      uint pulled = router().pull(outTkn, reserve(owner), balance, true);
      aRouter.decreaseBalance(outTkn, owner, amount); // decrease with pulled amount
      return balance - pulled;
    } else {
      uint pulled = router().pull(outTkn, reserve(owner), amount, true);
      aRouter.decreaseBalance(outTkn, owner, amount);
      return amount - pulled;
    }
  }

  function deposit(IERC20 token, uint amount) public returns (uint) {
    AavePoolRouter aRouter = AavePoolRouter(address(router()));
    aRouter.increaseBalance(token, msg.sender, amount);
    bool succes = TransferLib.transferTokenFrom(token, reserve(msg.sender), address(this), amount);
    // Should we push to Aave?
    if (succes) {
      uint pushed = aRouter.push(token, reserve(msg.sender), amount);
      return pushed;
    }
    return 0;
  }

  function withdraw(IERC20 token, uint amount) public returns (bool) {
    AavePoolRouter aRouter = AavePoolRouter(address(router()));
    uint balance = aRouter.getBalance(token, msg.sender);
    require(balance >= amount, "withdraw/notEnoughBalance");

    if (token.balanceOf(address(this)) >= amount) {
      bool succes = TransferLib.transferToken(token, reserve(msg.sender), amount);
      if (succes) {
        aRouter.decreaseBalance(token, msg.sender, amount);
      }
      return succes;
    }

    uint pulled = aRouter.pull(token, reserve(msg.sender), amount, true);
    require(pulled == amount, "withdraw/aavePulledWrongAmount");
    bool succes = TransferLib.transferToken(token, reserve(msg.sender), pulled);
    if (succes) {
      aRouter.decreaseBalance(token, msg.sender, pulled);
    }
    return succes;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    // reposts residual if any (conservative hook)
    bytes32 repost_status = super.__posthookSuccess__(order, makerData);

    return pushRemainderToAave(order);
  }

  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata)
    internal
    override
    returns (bytes32)
  {
    return pushRemainderToAave(order);
  }

  function pushRemainderToAave(MgvLib.SingleOrder calldata order) internal returns (bytes32) {
    AavePoolRouter aRouter = AavePoolRouter(address(router()));
    IERC20 outTk = IERC20(order.outbound_tkn);
    IERC20 inTk = IERC20(order.inbound_tkn);
    address owner = ownerOf(outTk, inTk, order.offerId);
    uint outBalance = outTk.balanceOf(address(this));
    uint outPushed = outBalance > 0 ? aRouter.push(outTk, address(this), outBalance) : 0; // should this be reserve(owner)?
    uint inBalance = inTk.balanceOf(address(this));
    uint inPushed = inBalance > 0 ? aRouter.push(inTk, address(this), inBalance) : 0;

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
