// SPDX-License-Identifier:	BSD-2-Clause

// Direct.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib, IERC20, MgvStructs} from "mgv_src/MgvLib.sol";
import {MangroveOfferStorage as MOS} from "mgv_src/strategies/MangroveOfferStorage.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";
import {IOfferLogic} from "mgv_src/strategies/interfaces/IOfferLogic.sol";

/// `Direct` strats is an extension of MangroveOffer that allows contract's admin to manage offers on Mangrove.
abstract contract Direct is MangroveOffer {
  ///@notice source of strat funds
  address immutable RESERVE;

  constructor(IMangrove mgv, AbstractRouter router_, uint gasreq, address reserve) MangroveOffer(mgv, gasreq) {
    if (router_ != NO_ROUTER) {
      setRouter(router_);
    }
    RESERVE = reserve;
  }

  function pull(IERC20 token, uint amount, bool strict) internal virtual returns (uint) {
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      uint reserveBalance = token.balanceOf(RESERVE);
      amount = strict ? (reserveBalance > amount ? amount : reserveBalance) : reserveBalance;
      require(
        TransferLib.transferTokenFrom({token: token, spender: RESERVE, recipient: address(this), amount: amount}),
        "Direct/pullFailed"
      );
      return amount;
    } else {
      // letting specific router pull the funds from RESERVE
      return router_.pull(token, RESERVE, amount, strict);
    }
  }

  function push(IERC20 token, uint amount) internal virtual returns (uint) {
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      require(TransferLib.transferToken(token, RESERVE, amount), "Direct/pushFailed");
      return amount; // nothing to do
    } else {
      // noop if reserve == address(this)
      return router_.push(token, RESERVE, amount);
    }
  }

  function flush(IERC20[] memory tokens) internal virtual {
    AbstractRouter router_ = MOS.getStorage().router;
    if (router_ != NO_ROUTER) {
      router_.flush(tokens, RESERVE);
    } else {
      for (uint i; i < tokens.length; i++) {
        require(TransferLib.transferToken(tokens[i], RESERVE, tokens[i].balanceOf(address(this))), "Direct/flushFailed");
      }
    }
  }

  function _newOffer(OfferArgs memory args) internal returns (uint, bytes32) {
    try MGV.newOffer{value: args.fund}(
      address(args.outbound_tkn),
      address(args.inbound_tkn),
      args.wants,
      args.gives,
      args.gasreq >= type(uint24).max ? offerGasreq() : args.gasreq,
      args.gasprice,
      args.pivotId
    ) returns (uint offerId) {
      return (offerId, "");
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      return (0, bytes32(bytes(reason)));
    }
  }

  function _updateOffer(OfferArgs memory args, uint offerId) internal override returns (bytes32) {
    if (args.gasreq >= type(uint24).max) {
      MgvStructs.OfferDetailPacked detail =
        MGV.offerDetails(address(args.outbound_tkn), address(args.inbound_tkn), offerId);
      args.gasreq = detail.gasreq();
    }
    try MGV.updateOffer{value: args.fund}(
      address(args.outbound_tkn),
      address(args.inbound_tkn),
      args.wants,
      args.gives,
      args.gasreq,
      args.gasprice,
      args.pivotId,
      offerId
    ) {
      return REPOST_SUCCESS;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      return bytes32(bytes(reason));
    }
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision if set to `true` if offer owner wishes to redeem the offer's provision.
  ///@return freeWei the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev An offer that is retracted without `deprovision` is retracted from the offer list, but still has its provisions locked by Mangrove.
  ///@dev Calling this function, with the `deprovision` flag, on an offer that is already retracted must be used to retrieve the locked provisions.
  function _retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) internal returns (uint freeWei) {
    freeWei = MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerId, deprovision);
    if (freeWei > 0) {
      require(MGV.withdraw(freeWei), "Direct/withdrawFail");
      // sending native tokens to `msg.sender` prevents reentrancy issues
      // (the context call of `retractOffer` could be coming from `makerExecute` and a different recipient of transfer than `msg.sender` could use this call to make offer fail)
      (bool noRevert,) = admin().call{value: freeWei}("");
      require(noRevert, "mgvOffer/weiTransferFail");
    }
  }

  ///@inheritdoc IOfferLogic
  function provisionOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId)
    external
    view
    override
    returns (uint provision)
  {
    provision = _provisionOf(outbound_tkn, inbound_tkn, offerId);
  }

  function __put__(uint, /*amount*/ MgvLib.SingleOrder calldata) internal virtual override returns (uint missing) {
    // direct contract do not need to do anything specific with incoming funds during trade
    // one should override this function if one wishes to leverage taker's fund during trade execution
    // be aware that the incoming funds will be transferred back to the reserve in posthookSuccess using flush.
    // this is done in posthook, to accumulate all taken offers and transfer everything in one transfer.
    return 0;
  }

  // default `__get__` hook for `Direct` is to pull liquidity from `reserve(admin())`
  // letting router handle the specifics if any
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint missing) {
    // pulling liquidity from reserve
    // depending on the router, this may result in pulling more/less liquidity than required
    // so one should check local balance to compute missing liquidity
    uint amount_ = IERC20(order.outbound_tkn).balanceOf(address(this));
    if (amount_ >= amount) {
      return 0;
    }
    amount_ = amount - amount_;
    uint pulled = pull(IERC20(order.outbound_tkn), amount_, false);
    missing = pulled >= amount_ ? 0 : amount_ - pulled;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32)
  {
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = IERC20(order.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
    tokens[1] = IERC20(order.inbound_tkn); // flushing liquidity brought by taker
    // sends all tokens to the reserve (noop if reserve(admin()) == address(this))
    flush(tokens);
    // reposting offer residual if any
    return super.__posthookSuccess__(order, makerData);
  }

  function __checkList__(IERC20 token, address source) internal view virtual override {
    // liquidity source is an immutable of Direct strats
    require(source == RESERVE, "Direct/LiquiditySourceMismatch");
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      // if not using a router, contract will transfer liquidity from reserve during pull
      require(
        RESERVE == address(this) || token.allowance({owner: RESERVE, spender: address(this)}) > 0,
        "Direct/reserveMustApproveMakerContract"
      );
    }
    // if using a router, we let the router verifies whether reserve must approve the router
    // this may not be the case for instance if the router does not transfer funds from reserve but maintains shares attributes to the reserve
    super.__checkList__(token, source);
  }
}
