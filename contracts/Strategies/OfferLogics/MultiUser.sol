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
    internal _offerUsers; // outbound_tkn => inbound_tkn => offerId => userAddress
  mapping(address => mapping(address => uint)) public tokenBalances; // user => erc20 => balance
  mapping(address => uint) public weiBalances; // user => WEI balance

  event CreditWei(address user, uint amount);
  event DebitWei(address user, uint amount);
  event CreditToken(address user, address token, uint amount);
  event DebitToken(address user, address token, uint amount);

  // Offer management
  event NewOffer(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId,
    address user
  );
  event UnkownOffer(
    address indexed outbound_tkn,
    address indexed inbound_tkn,
    uint indexed offerId
  );

  function creditWei(address user, uint balance) internal {
    emit CreditWei(user, balance);
    weiBalances[user] += balance;
  }

  function debitWei(address user, uint amount) internal {
    require(weiBalances[user] >= amount, "mgvOffer/MultiUser/insufficientWei");
    weiBalances[user] -= amount;
    emit DebitWei(user, amount);
  }

  function creditToken(
    address user,
    address token,
    uint amount
  ) internal {
    emit CreditToken(user, token, amount);
    tokenBalances[user][token] += amount;
  }

  // making function public to be able to catch it but is essentially internal
  function debitToken(
    address user,
    address token,
    uint amount
  ) public {
    require(msg.sender == address(this), "mgvOffer/MultiUser/unauthorize");
    require(
      tokenBalances[user][token] >= amount,
      "mgvOffer/MultiUser/insufficientTokens"
    );
    tokenBalances[user][token] -= amount;
    emit DebitToken(user, token, amount);
  }

  function addUser(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    address user
  ) internal {
    _offerUsers[outbound_tkn][inbound_tkn][offerId] = user;
    emit NewOffer(outbound_tkn, inbound_tkn, offerId, user);
  }

  /// transfers tokens of msg.sender stored in `this` contract to some recipient address
  /// Warning: this function should never be called internally for msg.sender provision has to be verified
  function transferToken(
    address token,
    address recipient,
    uint amount
  ) external override returns (bool success) {
    // making sure msg.sender has the tokens
    debitToken(msg.sender, token, amount);
    require(
      IERC20(token).transfer(recipient, amount),
      "mgvOffer/MultiUser/transferFail"
    );
    return true;
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  /// Warning: anyone can approve here.
  function approveMangrove(address outbound_tkn, uint amount) public override {
    super.approveMangrove(outbound_tkn, amount);
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  /// Warning: this function should not be called internally for msg.sender provision is being checked
  function withdrawFromMangrove(address receiver, uint amount)
    public
    override
    returns (bool noRevert)
  {
    debitWei(msg.sender, amount);
    require(
      super.withdrawFromMangrove(receiver, amount),
      "mgvOffer/MultiUser/weiTransferFail"
    );
    return true;
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
  ) external override returns (uint offerId) {
    uint weiBalanceBefore = MGV.balanceOf(address(this));
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
    //setting user of offerId
    addUser(outbound_tkn, inbound_tkn, offerId, msg.sender);
    //updating wei balance of user
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
  ) public override {
    require(
      _offerUsers[outbound_tkn][inbound_tkn][offerId] == msg.sender,
      "mgvOffer/MultiUser/unauthorized"
    );
    uint weiBalanceBefore = MGV.balanceOf(address(this));
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
    if (weiBalanceBefore >= weiBalanceAfter) {
      debitWei(msg.sender, weiBalanceBefore - weiBalanceAfter);
    } else {
      creditWei(msg.sender, weiBalanceAfter - weiBalanceBefore);
    }
  }

  // Retracts `offerId` from the (`outbound_tkn`,`inbound_tkn`) Offer list of Mangrove. Function call will throw if `this` contract is not the user of `offerId`.
  function retractOffer(
    address outbound_tkn,
    address inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external override returns (uint received) {
    require(
      _offerUsers[outbound_tkn][inbound_tkn][offerId] == msg.sender,
      "mgvOffer/MultiUser/unauthorized"
    );
    received = MGV.retractOffer(
      outbound_tkn,
      inbound_tkn,
      offerId,
      deprovision
    );
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
    address user = _offerUsers[order.outbound_tkn][order.inbound_tkn][
      order.offerId
    ];
    if (user != address(0)) {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
    creditToken(user, order.inbound_tkn, amount);
    return 0;
  }

  // Override this hook to implement fetching `amount` of outbound tokens, possibly from another source than `this` contract during Taker Order's execution.
  // For composability, return value MUST be the remaining quantity (i.e <= `amount`) of tokens remaining to be fetched.
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    override
    returns (uint)
  {
    address user = _offerUsers[order.outbound_tkn][order.inbound_tkn][
      order.offerId
    ];
    if (user != address(0)) {
      emit UnkownOffer(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return amount;
    }
    try this.debitToken(user, order.outbound_tkn, amount) {
      return 0;
    } catch Error(string memory message) {
      //debitToken throws if amount > tokenBalance
      return (amount - tokenBalances[user][order.outbound_tkn]);
    }
  }
}
