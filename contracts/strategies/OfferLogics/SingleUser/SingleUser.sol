// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOffer.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "../MangroveOffer.sol";
import "../../utils/TransferLib.sol";

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
abstract contract SingleUser is MangroveOffer {
  /// transfers token stored in `this` contract to some recipient address

  function withdrawToken(
    IEIP20 token,
    address receiver,
    uint amount
  ) external override onlyAdmin returns (bool success) {
    require(receiver != address(0), "SingleUser/withdrawToken/0xReceiver");
    return TransferLib.transferToken(IEIP20(token), receiver, amount);
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// ETH are sent to `receiver`
  function withdrawFromMangrove(address payable receiver, uint amount)
    external
    override
    onlyAdmin
    returns (bool)
  {
    require(receiver != address(0), "SingleUser/withdrawMGV/0xReceiver");
    return _withdrawFromMangrove(receiver, amount);
  }

  // Posting a new offer on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker maker MUST:
  // * Approve Mangrove for at least `gives` amount of `outbound_tkn`.
  // * Make sure that `this` contract has enough WEI provision on Mangrove to cover for the new offer bounty (function is payable so that caller can increase provision prior to posting the new offer)
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function will revert when the above points are not met
  function newOffer(MakerOrder calldata mko)
    external
    payable
    override
    onlyAdmin
    returns (uint offerId)
  {
    return
      MGV.newOffer{value: msg.value}(
        address(mko.outbound_tkn),
        address(mko.inbound_tkn),
        mko.wants,
        mko.gives,
        mko.gasreq,
        mko.gasprice,
        mko.pivotId
      );
  }

  // Updates offer `offerId` on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker MUST:
  // * Make sure that offer maker has enough WEI provision on Mangrove to cover for the new offer bounty in case Mangrove gasprice has increased (function is payable so that caller can increase provision prior to updating the offer)
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function will revert when the above points are not met
  function updateOffer(MakerOrder calldata mko, uint offerId)
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
        mko.gasreq,
        mko.gasprice,
        mko.pivotId,
        offerId
      );
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove.
  // Function call will throw if `this` contract is not the owner of `offerId`.
  // Returned value is the amount of ethers that have been credited to `this` contract balance on Mangrove (always 0 if `deprovision=false`)
  // NB `mgvOrAdmin` modifier guarantees that this function is either called by contract admin or during trade execution by Mangrove
  function retractOffer(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) public override mgvOrAdmin returns (uint) {
    return
      MGV.retractOffer(
        address(outbound_tkn),
        address(inbound_tkn),
        offerId,
        deprovision
      );
  }

  function getMissingProvision(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) public view override returns (uint) {
    return
      _getMissingProvision(
        MGV.balanceOf(address(this)), // current provision of offer maker is simply the current provision of `this` contract on Mangrove
        outbound_tkn,
        inbound_tkn,
        gasreq,
        gasprice,
        offerId
      );
  }

  // default `__put__` hook for `SingleUser` strats: received tokens are juste stored in `this` contract balance of `inbound` tokens.
  function __put__(
    uint, /*amount*/
    ML.SingleOrder calldata
  ) internal virtual override returns (uint) {
    return 0;
  }

  // default `__get__` hook for `SingleUser` strats: promised liquidity is obtained from `this` contract balance of `outbound` tokens
  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    uint balance = IEIP20(order.outbound_tkn).balanceOf(address(this));
    if (balance >= amount) {
      return 0;
    } else {
      return (amount - balance);
    }
  }
}
