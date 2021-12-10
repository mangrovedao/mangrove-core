// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOffer.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.7.0;
pragma abicoder v2;
import "../MangroveOffer.sol";
import "../../../periphery/MgvReader.sol";

abstract contract MultiUser is MangroveOffer {
  mapping(address => mapping(address => mapping(uint => address)))
    internal _offerOwners; // outbound_tkn => inbound_tkn => offerId => ownerAddress

  mapping(address => uint) public mgvBalanceOf; // owner => WEI balance on mangrove
  mapping(address => mapping(address => uint)) public tokenBalanceOf; // erc20 => owner => balance on `this`

  MgvReader immutable reader;

  constructor(address _reader) {
    reader = MgvReader(_reader);
  }

  // Offer management
  event NewOffer(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    address owner
  );

  function offerOwners(
    address outbound_tkn,
    address inbound_tkn,
    uint fromId,
    uint maxOffers
  )
    public
    view
    returns (
      uint nextId,
      uint[] memory offerIds,
      address[] memory owners
    )
  {
    (
      nextId,
      offerIds, /*offers*/ /*offerDetails*/
      ,

    ) = reader.offerList(outbound_tkn, inbound_tkn, fromId, maxOffers);
    owners = new address[](offerIds.length);
    for (uint i = 0; i < offerIds.length; i++) {
      owners[i] = ownerOf(outbound_tkn, inbound_tkn, offerIds[i]);
    }
  }

  function creditOnMgv(address owner, uint balance) internal {
    mgvBalanceOf[owner] += balance;
  }

  function debitOnMgv(address owner, uint amount) internal {
    require(
      mgvBalanceOf[owner] >= amount,
      "MultiOwner/debitOnMgv/insufficient"
    );
    mgvBalanceOf[owner] -= amount;
  }

  function creditToken(
    address token,
    address owner,
    uint balance
  ) internal {
    tokenBalanceOf[token][owner] += balance;
  }

  function debitToken(
    address token,
    address owner,
    uint amount
  ) internal {
    require(
      tokenBalanceOf[token][owner] >= amount,
      "MultiOwner/debitToken/insufficient"
    );
    tokenBalanceOf[token][owner] -= amount;
  }

  function redeemToken(address token, uint amount)
    external
    override
    returns (bool success)
  {
    require(msg.sender != address(this), "MutliUser/noReentrancy");
    debitToken(token, msg.sender, amount);
    success = _transferToken(token, msg.sender, amount);
  }

  function transferToken(
    address token,
    address owner,
    uint amount
  ) internal returns (bool success) {
    debitToken(token, owner, amount);
    success = _transferToken(token, owner, amount);
  }

  function addOwner(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    address owner
  ) internal {
    _offerOwners[outbound_tkn][inbound_tkn][offerId] = owner;
    emit NewOffer(outbound_tkn, inbound_tkn, offerId, owner);
  }

  function ownerOf(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId
  ) public view returns (address owner) {
    owner = _offerOwners[outbound_tkn][inbound_tkn][offerId];
    require(owner != address(0), "multiUser/unkownOffer");
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  /// Warning: anyone can approve here.
  function approveMangrove(address outbound_tkn, uint amount)
    external
    override
  {
    _approveMangrove(outbound_tkn, amount);
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  /// Warning: this function should not be called internally for msg.sender provision is being checked
  function withdrawFromMangrove(address receiver, uint amount)
    external
    override
    returns (bool noRevert)
  {
    debitOnMgv(msg.sender, amount);
    return _withdrawFromMangrove(receiver, amount);
  }

  function fundMangrove(address owner) external payable {
    // increasing the provision of `this` contract
    MGV.fund{value: msg.value}();
    // increasing the virtual provision of owner
    creditOnMgv(owner, msg.value);
  }

  function updateUserBalanceOnMgv(address user, uint mgvBalanceBefore)
    internal
  {
    uint mgvBalanceAfter = MGV.balanceOf(address(this));
    if (mgvBalanceAfter == mgvBalanceBefore) {
      return;
    }
    if (mgvBalanceAfter > mgvBalanceBefore) {
      creditOnMgv(user, mgvBalanceAfter - mgvBalanceBefore);
    } else {
      debitOnMgv(user, mgvBalanceBefore - mgvBalanceAfter);
    }
  }

  function newOffer(
    address outbound_tkn, // address of the ERC20 contract managing outbound tokens
    address inbound_tkn, // address of the ERC20 contract managing outbound tokens
    uint wants, // amount of `inbound_tkn` required for full delivery
    uint gives, // max amount of `outbound_tkn` promised by the offer
    uint gasreq, // max gas required by the offer when called. If maxUint256 is used here, default `OFR_GASREQ` will be considered instead
    uint gasprice, // gasprice that should be consider to compute the bounty (Mangrove's gasprice will be used if this value is lower)
    uint pivotId // identifier of an offer in the (`outbound_tkn,inbound_tkn`) Offer List after which the new offer should be inserted (gas cost of insertion will increase if the `pivotId` is far from the actual position of the new offer)
  ) external payable override returns (uint offerId) {
    uint weiBalanceBefore = MGV.balanceOf(address(this));
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    // this call could revert if this contract does not have the provision to cover the bounty
    offerId = MGV.newOffer(
      outbound_tkn,
      inbound_tkn,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId
    );
    //setting owner of offerId
    addOwner(outbound_tkn, inbound_tkn, offerId, msg.sender);
    //updating wei balance of owner will revert if msg.sender does not have the funds
    updateUserBalanceOnMgv(msg.sender, weiBalanceBefore);
  }

  function updateOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external payable override {
    address owner = ownerOf(outbound_tkn, inbound_tkn, offerId);
    require(owner == msg.sender, "mgvOffer/MultiOwner/unauthorized");
    uint weiBalanceBefore = MGV.balanceOf(address(this));
    if (msg.value > 0) {
      MGV.fund{value: msg.value}();
    }
    MGV.updateOffer(
      outbound_tkn,
      inbound_tkn,
      wants,
      gives,
      gasreq,
      gasprice,
      pivotId,
      offerId
    );
    uint weiBalanceAfter = MGV.balanceOf(address(this));
    updateUserBalanceOnMgv(owner, weiBalanceAfter);
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external override returns (uint received) {
    require(
      _offerOwners[outbound_tkn][inbound_tkn][offerId] == msg.sender,
      "mgvOffer/MultiOwner/unauthorized"
    );
    received = MGV.retractOffer(
      outbound_tkn,
      inbound_tkn,
      offerId,
      deprovision
    );
    if (received > 0) {
      creditOnMgv(msg.sender, received);
    }
  }

  function getMissingProvision(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) public view override returns (uint) {
    uint balance;
    address owner = ownerOf(outbound_tkn, inbound_tkn, offerId);
    if (owner == address(0)) {
      balance = 0;
    } else {
      balance = mgvBalanceOf[owner];
    }
    return
      _getMissingProvision(
        MGV,
        balance,
        outbound_tkn,
        inbound_tkn,
        gasreq,
        gasprice,
        offerId
      );
  }

  // put received inbound tokens on offer owner account
  function __put__(uint amount, MgvLib.SingleOrder calldata order)
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
    creditToken(order.inbound_tkn, owner, amount);
    return 0;
  }

  // get outbound tokens from offer owner account
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
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
    uint ownerBalance = tokenBalanceOf[order.outbound_tkn][owner];
    if (ownerBalance < amount) {
      debitToken(order.outbound_tkn, owner, ownerBalance);
      return (amount - ownerBalance);
    } else {
      debitToken(order.outbound_tkn, owner, amount);
      return 0;
    }
  }
}
