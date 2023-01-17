// SPDX-License-Identifier:	BSD-2-Clause

// OfferForwarder.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

pragma abicoder v2;

/*

// THE BIG TODO: Manage yield.

taker->mangrove: marketOrder(...)
mangrove->pooledForwarder: makerExecute(order)
pooledForwarder->pooledForwarder: __put__(amount: order.gives, order)
pooledForwarder->pooledForwarder: increaseBalance(DAI, owner[order], amount)
note over pooledForwarder,WETH:makerBalance: +1 DAI, 10 WETH<br>maker: -1 WETH

pooledForwarder->pooledForwarder: __get__(amount: order.gives, order)
pooledForwarder->pooledForwarder: decreaseBalance(WETH, owner[order], amount)
pooledForwarder->WETH: balanceOf(pooledForwarder)
pooledForwarder->aaveRouter: pull(WETH, ???, amount)



https://mermaid.live/



title WETH/DAI

sequenceDiagram


maker->>pooledForwarder: deposit(WETH, 1)
pooledForwarder->>WETH: transferFrom(maker, pooledForwarder, 1)
note over pooledForwarder,WETH:pooledForwarder: +1 WETH<br>maker: -1 WETH

pooledForwarder->>pooledForwarder: increaseBalance(WETH, maker, 1)

pooledForwarder->>aaveRouter: push(WETH, aaveRouter, 1)
aaveRouter->>WETH: transferFrom(pooledforwarder, aaveRouter, 1)
note over aaveRouter,WETH:pooledForwarder: +1-1 WETH<br>maker: -1 WETH<br>aaveRouter: +1 WETH

aaveRouter->>aaveRouter: repayThenDeposit(WETH, pooledForwarder, 1)

aaveRouter->>aavePool: supply(WETH, 1, aaveRouter)

aavePool->>WETH: transferFrom(aaveRouter?, aavePool, 1)
note over aavePool,WETH:pooledForwarder: +1-1 WETH<br>maker: -1 WETH<br>aaveRouter: +1-1 WETH<br>aavePool: +1 WETH

aavePool->>aWETH: mint(aaveRouter, 1)

note over aavePool,aWETH:pooledForwarder: +1-1 WETH<br>maker: -1 WETH<br>aaveRouter: +1-1 WETH<br>aavePool: +1 WETH<br>aaveRouter: +1 aWETH



{
  "theme": "dark",
  "noteAlign": "left"
}*/

import {Forwarder, IMangrove, IERC20, MgvLib} from "src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {AbstractRouter, AaveReserve} from "src/strategies/routers/AaveReserve.sol";
import {TransferLib} from "src/strategies/utils/TransferLib.sol";
import {ILiquidityProvider} from "src/strategies/interfaces/ILiquidityProvider.sol";

//Using a AaveDeepRouter, it will borrow and deposit on behalf of the reserve - but as a pool, and keep a contract-local balance to avoid spending gas
// gas overhead of the router for each order:
// - supply ~ 250K
// - borrow ~ 360K
//This means that yield and interest should be handled for the reserve here, somehow.
contract PooledForwarder is Forwarder, ILiquidityProvider {
  // balance of token for an owner - the pool has a balance in aave and on `this`.
  mapping(IERC20 => mapping(address => uint)) internal ownerBalance;

  // token => totalIous
  mapping(address => uint) public ious;
  // iou user balance
  mapping(address => mapping(address => uint)) public iousBalanceOf;

  constructor(IMangrove mgv, address deployer, address aaveAddressProvider)
    Forwarder(mgv, new AaveReserve(aaveAddressProvider, 0, 1 , 700_000), 30_000)
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
    require(currentBalance >= amount, "PooledForwarder/NotEnoughFunds");
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

  // We expose a newOffer and updateOffer for this contract
  function newOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId)
    external
    payable
    returns (uint offerId)
  {
    // we post the offer without any checks - it is up to the owner to have deposited enough.
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false // propagates Mangrove's revert data in case of newOffer failure
      }),
      msg.sender
    );
  }

  function updateOffer(IERC20 outbound_tkn, IERC20 inbound_tkn, uint wants, uint gives, uint pivotId, uint offerId)
    external
    payable
    onlyOwner
  {
    _updateOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false // propagates Mangrove's revert data in case of newOffer failure
      }),
      offerId
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

    // First we decrease balance - will revert if owner does not have enough.
    decreaseBalance(outTkn, owner, amount);

    // check if `this` has enough to satisfy order, otherwise pull _everything_ from aave.
    if (outTkn.balanceOf(address(this)) < amount) {
      // we do not verify result - we assume there is now enough, otherwise the order will fail.
      //TODO aave could be out of funds.
      AbstractRouter router_ = router();
      uint pulled =
      //reserve should be router because aave does not allow redeeming on behalf of
       router_.pull({token: outTkn, reserve: address(router_), amount: amount, strict: false /* pull everything */});
      // return whether some is still missing.
      return pulled >= amount ? 0 : amount - pulled;
    }

    // we have decreased owner's balance with the exact amount, so nothing more needed.
    return 0;
  }

  // mapping (address /*token*/ => uint /* ious */) ious;
  // mapping (address /*user*/ => address /* token */ => uint /* ious */) userIous;
  function deposit(IERC20 token, uint amount) external {
    // IOU-based method
    //   uint totalDepositedTokens = router.totalBalance(token);
    //   uint userIous = amount * ious[token] / totalDepositedTokens;
    //   totalDepositedTokens += amount;
    //   ious[token] += userIous;
    //   userIous[msg.sender][token] += userIous;
    // }

    // index-based method, I don't think it's needed
    // currentIndex // total accumulated interest since beginning of time
    // userIndex = currentIndex
    // userDeposit = amount

    // amount * (1 + (currentIndex / userIndex))

    require(
      TransferLib.transferTokenFrom({
        token: token,
        spender: msg.sender, // TODO revisit reserve vs msg.sender - also on Forwarder...
        recipient: address(this), // TODO consider changing to a direct transfer to router, but would require a deposit function on router, and thus not AbstractRouter
        amount: amount
      }),
      "pooledForwarder/makerTransferFail"
    );
    // if someone sends tokens directly to the router, it is possible that totalIous is 0 and totalDepositedTokens != 0
    // ious[token] == 0 => totalDepositedTokens == 0
    uint totalDepositedTokens = router.totalBalance(token);

    uint userIous = ious[token] == 0 ? amount : amount * ious[token] / totalDepositedTokens;

    // tokens are now on _this_ and can be pushed to router.
    // TODO: Should we push to Aave or wait for next order?
    increaseBalance(token, msg.sender, amount);
    AbstractRouter router_ = router();
    //TODO: repayThenDeposit is invoked and can pay back debt - consider having the strat be the admin
    uint pushed = router_.push(token, address(router_), amount);
    require(pushed == amount, "pooledForwarder/pushedWrongAmount");
  }

  function withdrawToken(IERC20 token, address receiver, uint amount) external returns (bool success) {
    // update state before calling contracts
    // if user doesn't have the funds, decreaseBalance will throw
    decreaseBalance(token, msg.sender, amount);

    // Check local pool first before calling aave
    // FIXME since funds should not be on this contract (unless posthoook failed), we may want to get rid of this
    uint thisBalance = token.balanceOf(address(this));

    // pull missing from aave into local pool - but only enough - the rest should still generate yield on aave
    if (thisBalance < amount) {
      AbstractRouter router_ = router();
      uint pulled = router_.pull(token, reserve(msg.sender), amount - thisBalance, true);
      // this should only happen if Aave is out of liquidity
      require(pulled + thisBalance == amount, "withdraw/aavePulledWrongAmount");
    }
    // Here token.balanceOf(address(this)) >= amount

    // transfer to owner
    require(TransferLib.transferToken({token: token, recipient: receiver, amount: amount}), "withdraw/transferFailed");
    return true;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repost_status)
  {
    // reposts residual if any (conservative hook)
    repost_status = super.__posthookSuccess__(order, makerData);
    pushAllToAave(order);
  }

  function __posthookFallback__(MgvLib.SingleOrder calldata order, MgvLib.OrderResult calldata result)
    internal
    override
    returns (bytes32 retdata)
  {
    pushAllToAave(order);
  }

  function __reserve__(address maker) internal view override returns (address) {
    maker;
    return address(router());
  }

  function pushAllToAave(MgvLib.SingleOrder calldata order) internal {
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
  }
}
