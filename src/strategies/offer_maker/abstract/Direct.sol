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
  constructor(IMangrove mgv, AbstractRouter router_, uint gasreq) MangroveOffer(mgv, gasreq) {
    if (router_ != NO_ROUTER) {
      setRouter(router_);
    }
  }

  function __checkList__(IERC20 token) internal view virtual override {
    require(msg.sender == admin(), "Direct/onlyAdminCanOwnOffers");
    address adminReserve = reserve(admin());
    // if this contract does the routing by itself, it must be approved by the reserve to do so.
    if (router() == NO_ROUTER && adminReserve != address(this)) {
      require(token.allowance(adminReserve, address(this)) > 0, "Direct/reserveMustApproveMakerContract");
    }
    super.__checkList__(token);
  }

  function pull(IERC20 outbound_tkn, uint amount, bool strict) internal returns (uint) {
    AbstractRouter router_ = router();
    address adminReserve = reserve(admin());
    if (router_ == NO_ROUTER) {
      bool success = TransferLib.transferTokenFrom(outbound_tkn, adminReserve, address(this), amount);
      return success ? amount : 0;
    } else {
      // letting specific router pull the funds from reserve
      return router_.pull(outbound_tkn, adminReserve, amount, strict);
    }
  }

  function push(IERC20 token, uint amount) internal {
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      return; // nothing to do
    } else {
      // noop if reserve == address(this)
      require(router_.push(token, reserve(admin()), amount) == amount, "Direct/pushFailed");
    }
  }

  function flush(IERC20[] memory tokens) internal {
    AbstractRouter router_ = MOS.getStorage().router;
    address reserve_ = reserve(admin());
    if (router_ == NO_ROUTER) {
      for (uint i = 0; i < tokens.length; i++) {
        require(
          TransferLib.transferToken(tokens[i], reserve_, tokens[i].balanceOf(address(this))),
          "Direct/flush/transferFail"
        );
      }
      return;
    } else {
      router_.flush(tokens, reserve_);
    }
  }

  function _newOffer(OfferArgs memory args) internal returns (uint) {
    try MGV.newOffer{value: args.fund}(
      address(args.outbound_tkn),
      address(args.inbound_tkn),
      args.wants,
      args.gives,
      args.gasreq >= type(uint24).max ? offerGasreq() : args.gasreq,
      args.gasprice,
      args.pivotId
    ) returns (uint offerId) {
      return offerId;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      return 0;
    }
  }

  function _updateOffer(OfferArgs memory args, uint offerId) internal returns (uint) {
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
      return offerId;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      return 0;
    }
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove.
  // Function call will throw if `this` contract is not the owner of `offerId`.
  // Returned value is the amount of ethers that have been credited to `this` contract balance on Mangrove (always 0 if `deprovision=false`)
  // NB `mgvOrAdmin` modifier guarantees that this function is either called by contract admin or (indirectly) during trade execution by Mangrove
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) public override mgvOrAdmin returns (uint free_wei) {
    free_wei = MGV.retractOffer(address(outbound_tkn), address(inbound_tkn), offerId, deprovision);
    if (free_wei > 0) {
      require(MGV.withdraw(free_wei), "Direct/withdrawFail");
      // sending native tokens to `msg.sender` prevents reentrancy issues
      // (the context call of `retractOffer` could be coming from `makerExecute` and a different recipient of transfer than `msg.sender` could use this call to make offer fail)
      (bool noRevert,) = admin().call{value: free_wei}("");
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
    MgvStructs.OfferDetailPacked offerDetail = MGV.offerDetails(address(outbound_tkn), address(inbound_tkn), offerId);
    (, MgvStructs.LocalPacked local) = MGV.config(address(outbound_tkn), address(inbound_tkn));
    unchecked {
      provision = offerDetail.gasprice() * 10 ** 9 * (local.offer_gasbase() + offerDetail.gasreq());
    }
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
    uint local_balance = IERC20(order.outbound_tkn).balanceOf(address(this));
    if (local_balance >= amount) {
      return 0;
    }
    uint pulled = pull(IERC20(order.outbound_tkn), amount - local_balance, false);
    missing = pulled >= amount - local_balance ? 0 : amount - local_balance - pulled;
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
}
