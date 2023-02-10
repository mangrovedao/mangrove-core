// SPDX-License-Identifier:	BSD-2-Clause

// Direct.sol

// Copyright (c) 2022 ADDMA. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;

import {MangroveOffer, IMangrove, AbstractRouter} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib, IERC20, MgvStructs} from "mgv_src/MgvLib.sol";
import {TransferLib} from "mgv_src/strategies/utils/TransferLib.sol";
import {IOfferLogic} from "mgv_src/strategies/interfaces/IOfferLogic.sol";

///@title `Direct` strats is an extension of MangroveOffer that allows contract's admin to manage offers on Mangrove.
abstract contract Direct is MangroveOffer {
  ///@notice identifier of this contract's reserve when using a router
  ///@dev RESERVE_ID==address(0) will pass address(this) to the router for the id field.
  ///@dev two contracts using the same RESERVE_ID will share funds, therefore strat builder must make sure this contract is allowed to pull into the given reserve Id.
  ///@dev a safe value for `RESERVE_ID` is `address(this)` in which case the funds will never be shared with another maker contract.
  address public immutable RESERVE_ID;

  ///@notice `Direct`'s constructor.
  ///@param mgv The Mangrove deployment that is allowed to call `this` for trade execution and posthook.
  ///@param router_ the router that this contract will use to pull/push liquidity from offer maker's reserve. This can be `NO_ROUTER`.
  ///@param gasreq Gas requirement when posting offers via this strategy, excluding router requirement.
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, AbstractRouter router_, uint gasreq, address reserveId) MangroveOffer(mgv, gasreq) {
    if (router_ != NO_ROUTER) {
      setRouter(router_);
    }
    RESERVE_ID = reserveId == address(0) ? address(this) : reserveId;
  }

  /// @notice Inserts a new offer in Mangrove Offer List.
  /// @param args Function arguments stored in memory.
  /// @return offerId Identifier of the newly created offer. Returns 0 if offer creation was rejected by Mangrove and `args.noRevert` is set to `true`.
  /// @return status NEW_OFFER_SUCCESS if the offer was successfully posted on Mangrove. Returns Mangrove's revert reason otherwise.
  function _newOffer(OfferArgs memory args) internal returns (uint offerId, bytes32 status) {
    try MGV.newOffer{value: args.fund}(
      address(args.outbound_tkn),
      address(args.inbound_tkn),
      args.wants,
      args.gives,
      args.gasreq,
      args.gasprice,
      args.pivotId
    ) returns (uint offerId_) {
      offerId = offerId_;
      status = NEW_OFFER_SUCCESS;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      status = bytes32(bytes(reason));
    }
  }

  ///@inheritdoc MangroveOffer
  function _updateOffer(OfferArgs memory args, uint offerId) internal override returns (bytes32 status) {
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
      status = REPOST_SUCCESS;
    } catch Error(string memory reason) {
      require(args.noRevert, reason);
      status = bytes32(bytes(reason));
    }
  }

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision if set to `true` if offer admin wishes to redeem the offer's provision.
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

  ///@notice direct contract do not need to do anything specific with incoming funds during trade
  ///@dev one should override this function if one wishes to leverage taker's fund during trade execution
  ///@inheritdoc MangroveOffer
  function __put__(uint, MgvLib.SingleOrder calldata) internal virtual override returns (uint) {
    return 0;
  }

  ///@notice `__get__` hook for `Direct` is to ask the router to pull liquidity from `reserveId` if strat is using a router
  /// otherwise the function simply returns what's missing in the local balance
  ///@inheritdoc MangroveOffer
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    uint amount_ = IERC20(order.outbound_tkn).balanceOf(address(this));
    if (amount_ >= amount) {
      return 0;
    }
    amount_ = amount - amount_;
    AbstractRouter router_ = router();
    if (router_ == NO_ROUTER) {
      return amount_;
    } else {
      uint pulled = router_.pull(IERC20(order.outbound_tkn), RESERVE_ID, amount_, false);
      return pulled >= amount_ ? 0 : amount_ - pulled;
    }
  }

  ///@notice Direct posthook flushes outbound and inbound token back to the router (if any)
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    virtual
    override
    returns (bytes32)
  {
    AbstractRouter router_ = router();
    if (router_ != NO_ROUTER) {
      IERC20[] memory tokens = new IERC20[](2);
      tokens[0] = IERC20(order.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
      tokens[1] = IERC20(order.inbound_tkn); // flushing liquidity brought by taker
      router_.flush(tokens, RESERVE_ID);
    }
    // reposting offer residual if any
    return super.__posthookSuccess__(order, makerData);
  }

  ///@notice if strat has a router, verfies that the router is ready to pull/push on behalf of reserve id
  ///@inheritdoc MangroveOffer
  function __checkList__(IERC20 token) internal view virtual override {
    super.__checkList__(token);
    if (router() != NO_ROUTER) {
      router().checkList(token, RESERVE_ID);
    }
  }
}
