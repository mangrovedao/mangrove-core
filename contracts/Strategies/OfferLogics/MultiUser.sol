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

abstract contract MultiUser is MangroveOffer {
  mapping(address => mapping(address => mapping(uint => address)))
    internal _offerOwners; // outbound_tkn => inbound_tkn => offerId => ownerAddress
  mapping(address => mapping(address => uint)) public tokenBalances; // owner => erc20 => balance
  mapping(address => uint) public weiBalances; // owner => WEI balance

  event CreditWei(address owner, uint amount);
  event DebitWei(address owner, uint amount);
  event CreditToken(address owner, address token, uint amount);
  event DebitToken(address owner, address token, uint amount);

  // Offer management
  event NewOffer(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    address owner
  );
  event UnkownOffer(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId
  );

  function creditWei(address owner, uint balance) internal {
    emit CreditWei(owner, balance);
    weiBalances[owner] += balance;
  }

  function debitWei(address owner, uint amount) internal {
    require(weiBalances[owner] >= amount, "MultiOwner/debitWei/insufficient");
    weiBalances[owner] -= amount;
    emit DebitWei(owner, amount);
  }

  function putToken(
    address owner,
    address token,
    uint amount
  ) internal {
    emit CreditToken(owner, token, amount);
    tokenBalances[owner][token] += amount;
  }

  // making function public to be able to catch it but is essentially internal
  function getToken(
    address owner,
    address token,
    uint amount
  ) public {
    require(msg.sender == address(this), "MultiOwner/debitTkn/unauthorized");
    require(
      tokenBalances[owner][token] >= amount,
      "MultiOwner/debitTkn/insufficient"
    );
    tokenBalances[owner][token] -= amount;
    emit DebitToken(owner, token, amount);
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
  ) public returns (address owner) {
    owner = _offerOwners[outbound_tkn][inbound_tkn][offerId];
    require(owner != address(0), "multiUser/unkownOffer");
  }

  /// transfers tokens of msg.sender stored in `this` contract to some recipient address
  /// Warning: this function should never be called internally for msg.sender provision has to be verified
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external returns (bool success) {
    // making sure msg.sender has the tokens, will throw otherwise
    getToken(msg.sender, token, amount);
    return _transferToken(token, recipient, amount);
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  /// Warning: anyone can approve here.
  function approveMangrove(address outbound_tkn, uint amount) external {
    _approveMangrove(outbound_tkn, amount);
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  /// Warning: this function should not be called internally for msg.sender provision is being checked
  function withdrawFromMangrove(address receiver, uint amount)
    external
    returns (bool noRevert)
  {
    debitWei(msg.sender, amount);
    return _withdrawFromMangrove(receiver, amount);
  }

  function fundMangrove() external payable {
    MGV.fund{value: msg.value}();
    creditWei(msg.sender, msg.value);
  }

  function newOffer(
    address outbound_tkn, // address of the ERC20 contract managing outbound tokens
    address inbound_tkn, // address of the ERC20 contract managing outbound tokens
    uint wants, // amount of `inbound_tkn` required for full delivery
    uint gives, // max amount of `outbound_tkn` promised by the offer
    uint gasreq, // max gas required by the offer when called. If maxUint256 is used here, default `OFR_GASREQ` will be considered instead
    uint gasprice, // gasprice that should be consider to compute the bounty (Mangrove's gasprice will be used if this value is lower)
    uint pivotId // identifier of an offer in the (`outbound_tkn,inbound_tkn`) Offer List after which the new offer should be inserted (gas cost of insertion will increase if the `pivotId` is far from the actual position of the new offer)
  ) external returns (uint offerId) {
    uint weiBalanceBefore = MGV.balanceOf(address(this));
    // this call could revert if this contract does not have the provision to cover the bounty
    offerId = _newOffer(
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
    debitWei(msg.sender, weiBalanceBefore - MGV.balanceOf(address(this)));
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
  ) external {
    require(
      ownerOf(outbound_tkn, inbound_tkn, offerId) == msg.sender,
      "mgvOffer/MultiOwner/unauthorized"
    );
    uint weiBalanceBefore = MGV.balanceOf(address(this));
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
    uint weiBalanceAfter = MGV.balanceOf(address(this));
    if (weiBalanceBefore >= weiBalanceAfter) {
      // will throw if use doesn't have the funds
      debitWei(msg.sender, weiBalanceBefore - weiBalanceAfter);
    } else {
      creditWei(msg.sender, weiBalanceAfter - weiBalanceBefore);
    }
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the owner of `offerId`.
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external returns (uint received) {
    require(
      _offerOwners[outbound_tkn][inbound_tkn][offerId] == msg.sender,
      "mgvOffer/MultiOwner/unauthorized"
    );
    received = _retractOffer(outbound_tkn, inbound_tkn, offerId, deprovision);
    if (received > 0) {
      creditWei(msg.sender, received);
    }
  }

  function __put__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    try
      this.ownerOf(order.outbound_tkn, order.inbound_tkn, order.offerId)
    returns (address owner) {
      putToken(owner, order.inbound_tkn, amount);
      return 0;
    } catch Error(string memory message) {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
  }

  // Override this hook to implement fetching `amount` of outbound tokens, possibly from another source than `this` contract during Taker Order's execution.
  // For composability, return value MUST be the remaining quantity (i.e <= `amount`) of tokens remaining to be fetched.
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    try
      this.ownerOf(order.outbound_tkn, order.inbound_tkn, order.offerId)
    returns (address owner) {
      try this.getToken(owner, order.outbound_tkn, amount) {
        return 0;
      } catch Error(string memory message) {
        //getToken throws if amount > tokenBalance
        return (amount - tokenBalances[owner][order.outbound_tkn]);
      }
    } catch {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
  }
}
