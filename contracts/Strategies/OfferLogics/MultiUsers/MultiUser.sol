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
import "../../../periphery/MgvReader.sol";
import "../../interfaces/IOfferLogicMulti.sol";

abstract contract MultiUser is IOfferLogicMulti, MangroveOffer {
  mapping(IEIP20 => mapping(IEIP20 => mapping(uint => address)))
    internal _offerOwners; // outbound_tkn => inbound_tkn => offerId => ownerAddress

  mapping(address => uint) public mgvBalance; // owner => WEI balance on mangrove
  mapping(IEIP20 => mapping(address => uint)) public tokenBalanceOf; // erc20 => owner => balance on `this`

  function tokenBalance(IEIP20 token, address owner)
    external
    view
    override
    returns (uint)
  {
    return tokenBalanceOf[token][owner];
  }

  function balanceOnMangrove(address owner)
    external
    view
    override
    returns (uint)
  {
    return mgvBalance[owner];
  }

  function offerOwners(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint[] calldata offerIds
  ) public view override returns (address[] memory __offerOwners) {
    __offerOwners = new address[](offerIds.length);
    for (uint i = 0; i < offerIds.length; i++) {
      __offerOwners[i] = ownerOf(outbound_tkn, inbound_tkn, offerIds[i]);
    }
  }

  function creditOnMgv(address owner, uint balance) internal {
    mgvBalance[owner] += balance;
    emit CreditMgvUser(MGV, owner, balance);
  }

  function debitOnMgv(address owner, uint amount) internal {
    require(mgvBalance[owner] >= amount, "Multi/debitOnMgv/insufficient");
    mgvBalance[owner] -= amount;
    emit DebitMgvUser(MGV, owner, amount);
  }

  function creditToken(
    IEIP20 token,
    address owner,
    uint amount
  ) internal {
    tokenBalanceOf[token][owner] += amount;
    emit CreditUserTokenBalance(owner, token, amount);
  }

  function debitToken(
    IEIP20 token,
    address owner,
    uint amount
  ) internal {
    if (amount == 0) {
      return;
    }
    require(
      tokenBalanceOf[token][owner] >= amount,
      "Multi/debitToken/insufficient"
    );
    tokenBalanceOf[token][owner] -= amount;
    emit DebitUserTokenBalance(owner, token, amount);
  }

  function withdrawToken(
    IEIP20 token,
    address receiver,
    uint amount
  ) external override returns (bool success) {
    debitToken(token, msg.sender, amount);
    success = token.transfer(receiver, amount);
  }

  function depositToken(IEIP20 token, uint amount)
    external
    override
    returns (
      //override
      bool success
    )
  {
    uint balBefore = token.balanceOf(address(this));
    success = token.transferFrom(msg.sender, address(this), amount);
    require(
      token.balanceOf(address(this)) - balBefore == amount,
      "Multi/transferFail"
    );
    creditToken(token, msg.sender, amount);
  }

  function addOwner(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId,
    address owner
  ) internal {
    _offerOwners[outbound_tkn][inbound_tkn][offerId] = owner;
    emit NewOwnedOffer(MGV, outbound_tkn, inbound_tkn, offerId, owner);
  }

  function ownerOf(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId
  ) public view override returns (address owner) {
    owner = _offerOwners[outbound_tkn][inbound_tkn][offerId];
    require(owner != address(0), "multiUser/unkownOffer");
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  /// Warning: this function should not be called internally for msg.sender provision is being checked
  function withdrawFromMangrove(address payable receiver, uint amount)
    external
    override
    returns (bool noRevert)
  {
    require(msg.sender != address(this), "Mutli/noReentrancy");
    debitOnMgv(msg.sender, amount);
    return _withdrawFromMangrove(receiver, amount);
  }

  function fundMangrove() external payable override // override
  {
    require(msg.sender != address(this), "Mutli/noReentrancy");
    fundMangroveInternal(msg.sender, msg.value);
  }

  function fundMangroveInternal(address caller, uint provision) internal {
    // increasing the provision of `this` contract
    MGV.fund{value: provision}();
    // increasing the virtual provision of owner
    creditOnMgv(caller, provision);
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

  function newOffer(MakerOrder calldata mko)
    external
    payable
    override
    returns (uint offerId)
  {
    // Just a sanity check for future development
    // If a multi user contract was able to post in its name, the offer would be able to draw from the collective pool
    require(msg.sender != address(this), "Mutli/noReentrancy");
    offerId = newOfferInternal(mko, msg.sender, msg.value);
  }

  // Calls new offer on Mangrove. If successful the function will:
  // 1. Update `_offerOwners` mapping `caller` to returned `offerId`
  // 2. maintain `mgvBalance` with the redeemable WEIs for caller on Mangrove
  // This call will revert if `newOffer` reverts on Mangrove or if `caller` does not have the provisions to cover for the bounty.
  function newOfferInternal(
    MakerOrder memory mko,
    address caller,
    uint provision
  ) internal returns (uint offerId) {
    require(caller != address(this), "Mutli/noReentrancy");

    uint weiBalanceBefore = MGV.balanceOf(address(this));
    uint gasreq = (mko.gasreq > type(uint24).max) ? OFR_GASREQ() : mko.gasreq;
    // this call could revert if this contract does not have the provision to cover the bounty
    offerId = MGV.newOffer{value: provision}(
      $(mko.outbound_tkn),
      $(mko.inbound_tkn),
      mko.wants,
      mko.gives,
      gasreq,
      mko.gasprice,
      mko.pivotId
    );
    //setting owner of offerId
    addOwner(mko.outbound_tkn, mko.inbound_tkn, offerId, caller);
    //updating wei balance of owner will revert if msg.sender does not have the funds
    updateUserBalanceOnMgv(caller, weiBalanceBefore);
  }

  function updateOffer(MakerOrder calldata mko, uint offerId)
    external
    payable
    override
  {
    (uint offerId_, string memory reason) = updateOfferInternal(
      mko,
      offerId,
      msg.sender,
      msg.value
    );
    require(offerId_ > 0, reason);
  }

  // Calls update offer on Mangrove. If successful the function will take care of maintaining `mgvBalance` for offer owner.
  // This call does not revert if `updateOffer` fails on Mangrove, due for instance to low density or incorrect `wants`/`gives`.
  // It will however revert if user does not have the provision to cover the bounty (in case of gas increase).
  // When offer failed to be updated, the returned value is always 0 and the revert message. Otherwise it is equal to `offerId` and the empty string.
  function updateOfferInternal(
    MakerOrder memory mko,
    uint offerId,
    address caller,
    uint provision // dangerous to use msg.value in a internal call
  ) internal returns (uint, string memory) {
    require(
      caller == ownerOf(mko.outbound_tkn, mko.inbound_tkn, offerId),
      "Multi/updateOffer/unauthorized"
    );
    uint weiBalanceBefore = MGV.balanceOf(address(this));
    try
      MGV.updateOffer{value: provision}(
        $(mko.outbound_tkn),
        $(mko.inbound_tkn),
        mko.wants,
        mko.gives,
        (mko.gasreq > type(uint24).max) ? OFR_GASREQ() : mko.gasreq,
        mko.gasprice,
        mko.pivotId,
        offerId
      )
    {
      updateUserBalanceOnMgv(caller, weiBalanceBefore);
      return (offerId, "");
    } catch Error(string memory reason) {
      return (0, reason);
    }
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  function retractOffer(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external override returns (uint received) {
    received = retractOfferInternal(
      outbound_tkn,
      inbound_tkn,
      offerId,
      deprovision,
      msg.sender
    );
  }

  function retractOfferInternal(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint offerId,
    bool deprovision,
    address caller
  ) internal returns (uint received) {
    require(
      _offerOwners[outbound_tkn][inbound_tkn][offerId] == caller,
      "Multi/retractOffer/unauthorized"
    );
    received = MGV.retractOffer(
      $(outbound_tkn),
      $(inbound_tkn),
      offerId,
      deprovision
    );
    if (received > 0) {
      creditOnMgv(caller, received);
    }
  }

  function getMissingProvision(
    IEIP20 outbound_tkn,
    IEIP20 inbound_tkn,
    uint gasreq,
    uint gasprice,
    uint offerId
  ) public view override returns (uint) {
    uint balance;
    if (offerId != 0) {
      address owner = ownerOf(outbound_tkn, inbound_tkn, offerId);
      balance = mgvBalance[owner];
    }
    return
      _getMissingProvision(
        balance,
        outbound_tkn,
        inbound_tkn,
        gasreq,
        gasprice,
        offerId
      );
  }

  // put received inbound tokens on offer owner account
  function __put__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    IEIP20 outTkn = IEIP20(order.outbound_tkn);
    IEIP20 inTkn = IEIP20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    creditToken(IEIP20(order.inbound_tkn), owner, amount);
    return 0;
  }

  // get outbound tokens from offer owner account
  function __get__(uint amount, ML.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    IEIP20 outTkn = IEIP20(order.outbound_tkn);
    IEIP20 inTkn = IEIP20(order.inbound_tkn);
    address owner = ownerOf(outTkn, inTkn, order.offerId);
    uint ownerBalance = tokenBalanceOf[outTkn][owner];
    if (ownerBalance < amount) {
      debitToken(outTkn, owner, ownerBalance);
      return (amount - ownerBalance);
    } else {
      debitToken(outTkn, owner, amount);
      return 0;
    }
  }
}
