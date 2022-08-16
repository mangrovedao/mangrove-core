// SPDX-License-Identifier:	BSD-2-Clause

// SingleUser.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "../../MangroveOffer.sol";
import "mgv_src/strategies/utils/TransferLib.sol";
import {SingleUserStorage as SUS} from "./SingleUserStorage.sol";

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
abstract contract SingleUser is MangroveOffer {
  constructor(
    IMangrove _mgv,
    uint strat_gasreq,
    AbstractRouter _router
  ) MangroveOffer(_mgv, strat_gasreq) {
    // default reserve is router's address if router is defined
    // if not then default reserve is `this` contract
    if (address(_router) == address(0)) {
      set_reserve(address(this));
    } else {
      set_reserve(address(_router));
      set_router(_router);
    }
  }

  function reserve() public view returns (address) {
    return SUS.get_storage().reserve;
  }

  function set_reserve(address _reserve) public mgvOrAdmin {
    require(_reserve != address(0), "SingleUser/0xReserve");
    SUS.get_storage().reserve = _reserve;
  }

  function withdrawToken(
    IERC20 token,
    address receiver,
    uint amount
  ) external override onlyAdmin returns (bool success) {
    require(receiver != address(0), "SingleUser/withdrawToken/0xReceiver");
    if (!has_router()) {
      return TransferLib.transferToken(IERC20(token), receiver, amount);
    } else {
      return router().withdrawToken(token, reserve(), receiver, amount);
    }
  }

  function pull(
    IERC20 outbound_tkn,
    uint amount,
    bool strict
  ) internal returns (uint) {
    AbstractRouter _router = MOS.get_storage().router;
    if (address(_router) == address(0)) {
      return 0; // nothing to do
    } else {
      // letting specific router pull the funds from reserve
      return _router.pull(outbound_tkn, reserve(), amount, strict);
    }
  }

  function push(IERC20 token, uint amount) internal {
    AbstractRouter _router = MOS.get_storage().router;
    if (address(_router) == address(0)) {
      return; // nothing to do
    } else {
      // noop if reserve == address(this)
      _router.push(token, reserve(), amount);
    }
  }

  function tokenBalance(IERC20 token) external view override returns (uint) {
    AbstractRouter _router = MOS.get_storage().router;
    return
      address(_router) == address(0)
        ? token.balanceOf(reserve())
        : _router.reserveBalance(token, reserve());
  }

  function flush(IERC20[] memory tokens) internal {
    AbstractRouter _router = MOS.get_storage().router;
    if (address(_router) == address(0)) {
      return; // nothing to do
    } else {
      _router.flush(tokens, reserve());
    }
  }

  // Posting a new offer on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker maker MUST:
  // * Approve Mangrove for at least `gives` amount of `outbound_tkn`.
  // * Make sure that `this` contract has enough WEI provision on Mangrove to cover for the new offer bounty (function is payable so that caller can increase provision prior to posting the new offer)
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function will revert when the above points are not met
  function newOffer(MakerOrder memory mko)
    external
    payable
    override
    onlyAdmin
    returns (uint)
  {
    mko.offerId = MGV.newOffer{value: msg.value}(
      address(mko.outbound_tkn),
      address(mko.inbound_tkn),
      mko.wants,
      mko.gives,
      mko.gasreq >= type(uint24).max ? ofr_gasreq() : mko.gasreq,
      mko.gasprice,
      mko.pivotId
    );
    return mko.offerId;
  }

  // Updates offer `offerId` on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker MUST:
  // * Make sure that offer maker has enough WEI provision on Mangrove to cover for the new offer bounty in case Mangrove gasprice has increased (function is payable so that caller can increase provision prior to updating the offer)
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function will revert when the above points are not met
  function updateOffer(MakerOrder memory mko)
    external
    payable
    override
    onlyAdmin
  {
    return
      MGV.updateOffer{value: msg.value}(
        address(mko.outbound_tkn),
        address(mko.inbound_tkn),
        mko.wants,
        mko.gives,
        mko.gasreq > type(uint24).max ? ofr_gasreq() : mko.gasreq,
        mko.gasprice,
        mko.pivotId,
        mko.offerId
      );
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove.
  // Function call will throw if `this` contract is not the owner of `offerId`.
  // Returned value is the amount of ethers that have been credited to `this` contract balance on Mangrove (always 0 if `deprovision=false`)
  // NB `mgvOrAdmin` modifier guarantees that this function is either called by contract admin or during trade execution by Mangrove
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) public override mgvOrAdmin returns (uint free_wei) {
    free_wei = MGV.retractOffer(
      address(outbound_tkn),
      address(inbound_tkn),
      offerId,
      deprovision
    );
    if (free_wei > 0) {
      require(
        MGV.withdraw(free_wei),
        "SingleUser/withdrawFromMgv/withdrawFail"
      );
      (bool noRevert, ) = msg.sender.call{value: free_wei}("");
      require(noRevert, "SingleUser/weiTransferFail");
    }
  }

  function __put__(
    uint, /*amount*/
    ML.SingleOrder calldata
  ) internal virtual override returns (uint missing) {
    // singleUser contract do not need to do anything specific with incoming funds during trade
    // one should overrides this function if one wishes to leverage taker's fund during trade execution
    return 0;
  }

  // default `__get__` hook for `SingleUser` is to pull liquidity from immutable `reserve()`
  // letting router handle the specifics if any
  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint missing)
  {
    // pulling liquidity from reserve
    // depending on the router, this may result in pulling more/less liquidity than required
    // so one should check local balance to compute missing liquidity
    uint pulled = pull(IERC20(order.outbound_tkn), amount, false);
    if (pulled >= amount) {
      return 0;
    } else {
      uint local_balance = IERC20(order.outbound_tkn).balanceOf(address(this));
      return local_balance >= amount ? 0 : amount - local_balance;
    }
  }

  ////// Customizable post-hooks.

  // Override this post-hook to implement what `this` contract should do when called back after a successfully executed order.
  // In this posthook, contract will flush its liquidity towards the reserve (noop if reserve is this contract)
  function __posthookSuccess__(ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool success)
  {
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = IERC20(order.outbound_tkn); // flushing outbound tokens if this contract pulled more liquidity than required during `makerExecute`
    tokens[1] = IERC20(order.inbound_tkn); // flushing liquidity brought by taker
    // sends all tokens to the reserve (noop if reserve() == address(this))
    flush(tokens);
    success = true;
  }

  function __checkList__(IERC20 token) internal view virtual override {
    if (has_router()) {
      router().checkList(token, reserve());
    }
    super.__checkList__(token);
  }
}
