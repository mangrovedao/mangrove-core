// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOffer.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;

import "./MangroveOffer.sol";

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
abstract contract SingleUser is MangroveOffer {
  /// transfers token stored in `this` contract to some recipient address
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external virtual onlyAdmin returns (bool success) {
    success = _transferToken(token, recipient, amount);
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  function approveMangrove(address outbound_tkn, uint amount)
    external
    virtual
    onlyAdmin
  {
    _approveMangrove(outbound_tkn, amount);
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  function withdrawFromMangrove(address receiver, uint amount)
    external
    virtual
    onlyAdmin
    returns (bool noRevert)
  {
    _withdrawFromMangrove(receiver, amount);
  }

  // Posting a new offer on the (`outbound_tkn,inbound_tkn`) Offer List of Mangrove.
  // NB #1: Offer maker MUST:
  // * Approve Mangrove for at least `gives` amount of `outbound_tkn`.
  // * Make sure that offer maker has enough WEI provision on Mangrove to cover for the new offer bounty
  // * Make sure that `gasreq` and `gives` yield a sufficient offer density
  // NB #2: This function may revert when the above points are not met, it is thus made external only so that it can be encapsulated when called during `makerExecute`.
  function newOffer(
    address outbound_tkn, // address of the ERC20 contract managing outbound tokens
    address inbound_tkn, // address of the ERC20 contract managing outbound tokens
    uint wants, // amount of `inbound_tkn` required for full delivery
    uint gives, // max amount of `outbound_tkn` promised by the offer
    uint gasreq, // max gas required by the offer when called. If maxUint256 is used here, default `OFR_GASREQ` will be considered instead
    uint gasprice, // gasprice that should be consider to compute the bounty (Mangrove's gasprice will be used if this value is lower)
    uint pivotId // identifier of an offer in the (`outbound_tkn,inbound_tkn`) Offer List after which the new offer should be inserted (gas cost of insertion will increase if the `pivotId` is far from the actual position of the new offer)
  ) external virtual internalOrAdmin returns (uint offerId) {
    uint missing = __autoRefill__(
      outbound_tkn,
      inbound_tkn,
      gasreq,
      gasprice,
      0
    );
    if (missing > 0) {
      consolerr.errorUint("SingleUser/new/outOfFunds: ", missing);
    }
    return
      _newOffer(
        outbound_tkn,
        inbound_tkn,
        wants,
        gives,
        gasreq,
        gasprice,
        pivotId
      );
  }

  //  Updates an existing `offerId` on the Mangrove. `updateOffer` rely on the same offer requirements as `newOffer` and may throw if they are not met.
  //  Additionally `updateOffer` will thow if `this` contract is not the owner of `offerId`.
  //  The `__autoRefill__` hook may be overridden to provide a method to refill offer provision automatically.
  function updateOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external virtual internalOrAdmin {
    uint missing = __autoRefill__(
      outbound_tkn,
      inbound_tkn,
      gasreq,
      gasprice,
      offerId
    );
    if (missing > 0) {
      consolerr.errorUint("SingleUser/update/outOfFunds: ", missing);
    }
    _updateOffer(
      outbound_tkn,
      inbound_tkn,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId,
      offerId
    );
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external virtual internalOrAdmin returns (uint) {
    _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
  }

  // Override this hook to let the offer refill its provision on Mangrove (provided `this` contract has enough ETH).
  // Use this hook to increase outbound token approval for Mangrove when the Offer Maker wishes to keep it tight.
  // return value `missingETH` should be 0 if `offerId` doesn't lack provision.
  function __autoRefill__(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq, // gas required by the offer to be reposted
    uint gasprice, // gas price for the computation of the bounty
    uint offerId // ID of the offer to be updated.
  ) internal virtual returns (uint missingETH) {
    outbound_tkn; //shh
    inbound_tkn;
    gasreq;
    gasprice;
    offerId;
  }

  function __put__(uint amount, MgvLib.SingleOrder calldata)
    internal
    virtual
    override
    returns (uint)
  {
    return 0;
  }

  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    uint balance = IERC20(order.outbound_tkn).balanceOf(address(this));
    if (balance >= amount) {
      return 0;
    } else {
      return (amount - balance);
    }
  }

  // Override this hook to implement a last look check during Taker Order's execution.
  // Return value should be `true` if Taker Order is acceptable.
  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (bool proceed)
  {
    order; //shh
    proceed = true;
  }
}
