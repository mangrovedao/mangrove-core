// SPDX-License-Identifier:	BSD-2-Clause

// MangroveOffer.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
pragma solidity ^0.8.10;
pragma abicoder v2;

import "../../MgvLib.sol";
import "../lib/AccessControlled.sol";
import "../lib/Exponential.sol";
import "../lib/consolerr/consolerr.sol";
import "../interfaces/IOfferLogic.sol";
import "../../Mangrove.sol";

/// MangroveOffer is the basic building block to implement a reactive offer that interfaces with the Mangrove
abstract contract MangroveOffer is AccessControlled, IOfferLogic, Exponential {
  using P.Offer for P.Offer.t;
  using P.OfferDetail for P.OfferDetail.t;
  using P.Global for P.Global.t;
  using P.Local for P.Local.t;

  bytes32 immutable RENEGED = "MangroveOffer/reneged";
  bytes32 immutable PUTFAILURE = "MangroveOffer/putFailure";
  bytes32 immutable OUTOFLIQUIDITY = "MangroveOffer/outOfLiquidity";

  Mangrove public immutable MGV; // Address of the deployed Mangrove contract

  modifier mgvOrAdmin() {
    require(
      msg.sender == admin || msg.sender == address(MGV),
      "AccessControlled/Invalid"
    );
    _;
  }
  // default values
  uint public override OFR_GASREQ = 100_000;

  receive() external payable virtual {}

  constructor(address payable _mgv) {
    MGV = Mangrove(_mgv);
  }

  function setGasreq(uint gasreq) public override mgvOrAdmin {
    require(uint24(gasreq) == gasreq, "MangroveOffer/gasreq/overflow");
    OFR_GASREQ = gasreq;
  }

  function _transferToken(
    address token,
    address recipient,
    uint amount
  ) internal returns (bool success) {
    success = IERC20(token).transfer(recipient, amount);
  }

  function _transferTokenFrom(
    address token,
    address sender,
    uint amount
  ) internal returns (bool success) {
    success = IERC20(token).transferFrom(sender, address(this), amount);
  }

  /// trader needs to approve Mangrove to let it perform outbound token transfer at the end of the `makerExecute` function
  /// NB anyone can call
  function approveMangrove(address outbound_tkn, uint amount) public {
    require(
      IERC20(outbound_tkn).approve(address(MGV), amount),
      "mgvOffer/approve/Fail"
    );
  }

  /// withdraws ETH from the bounty vault of the Mangrove.
  /// NB: `Mangrove.fund` function need not be called by `this` so is not included here.
  function _withdrawFromMangrove(address receiver, uint amount)
    internal
    returns (bool noRevert)
  {
    require(MGV.withdraw(amount), "MangroveOffer/withdraw/transferFail");
    (noRevert, ) = receiver.call{value: amount}("");
  }

  // returns missing provision to repost `offerId` at given `gasreq` and `gasprice`
  // if `offerId` is not in the offerList, will simply return how much is needed to post
  function _getMissingProvision(
    uint balance, // offer owner balance on Mangrove
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq, // give > type(uint24).max to use `this.OFR_GASREQ()`
    uint gasprice, // give 0 to use Mangrove's gasprice
    uint offerId // set this to 0 if one is not reposting an offer
  ) internal view returns (uint) {
    (P.Global.t globalData, P.Local.t localData) = MGV.config(
      outbound_tkn,
      inbound_tkn
    );
    P.OfferDetail.t offerDetailData = MGV.offerDetails(
      outbound_tkn,
      inbound_tkn,
      offerId
    );
    uint _gp;
    if (globalData.gasprice() > gasprice) {
      _gp = globalData.gasprice();
    } else {
      _gp = gasprice;
    }
    if (gasreq > type(uint24).max) {
      gasreq = OFR_GASREQ;
    }
    uint bounty = (gasreq + localData.offer_gasbase()) * _gp * 10**9; // in WEI
    // if `offerId` is not in the OfferList, all returned values will be 0
    uint currentProvisionLocked = (offerDetailData.gasreq() +
      offerDetailData.offer_gasbase()) *
      offerDetailData.gasprice() *
      10**9;
    uint currentProvision = currentProvisionLocked + balance;
    return (currentProvision >= bounty ? 0 : bounty - currentProvision);
  }

  function giveAtDensity(
    address outbound_tkn,
    address inbound_tkn,
    uint gasreq
  ) public view returns (uint) {
    (, P.Local.t localData) = MGV.config(outbound_tkn, inbound_tkn);
    gasreq = gasreq > type(uint24).max ? OFR_GASREQ : gasreq;
    return (gasreq + localData.offer_gasbase()) * localData.density();
  }

  /////// Mandatory callback functions

  // `makerExecute` is the callback function to execute all offers that were posted on Mangrove by `this` contract.
  // it may not be overriden although it can be customized using `__lastLook__`, `__put__` and `__get__` hooks.
  // NB #1: When overriding the above hooks, the Offer Maker SHOULD make sure they do not revert in order to be able to post logs in case of bad executions.
  // NB #2: if `makerExecute` does revert, the offer will be considered to be refusing the trade.
  function makerExecute(MgvLib.SingleOrder calldata order)
    external
    override
    onlyCaller(address(MGV))
    returns (bytes32 ret)
  {
    if (!__lastLook__(order)) {
      // hook to check order details and decide whether `this` contract should renege on the offer.
      emit Reneged(order.outbound_tkn, order.inbound_tkn, order.offerId);
      return RENEGED;
    }
    uint missingPut = __put__(order.gives, order); // implements what should be done with the liquidity that is flashswapped by the offer taker to `this` contract
    if (missingPut > 0) {
      emit PutFail(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        missingPut
      );
      return PUTFAILURE;
    }
    uint missingGet = __get__(order.wants, order); // implements how `this` contract should make the outbound tokens available
    if (missingGet > 0) {
      emit GetFail(
        order.outbound_tkn,
        order.inbound_tkn,
        order.offerId,
        missingGet
      );
      return OUTOFLIQUIDITY;
    }
  }

  // `makerPosthook` is the callback function that is called by Mangrove *after* the offer execution.
  // It may not be overriden although it can be customized via the post-hooks `__posthookSuccess__`, `__posthookGetFailure__`, `__posthookReneged__` and `__posthookFallback__` (see below).
  // Offer Maker SHOULD make sure the overriden posthooks do not revert in order to be able to post logs in case of bad executions.
  function makerPosthook(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) external override onlyCaller(address(MGV)) {
    if (result.mgvData == "mgv/tradeSuccess") {
      // if trade was a success
      __posthookSuccess__(order);
      return;
    }
    // if trade was aborted because of a lack of liquidity
    if (result.makerData == OUTOFLIQUIDITY) {
      __posthookGetFailure__(order);
      return;
    }
    // if trade was reneged on during lastLook
    if (result.makerData == RENEGED) {
      __posthookReneged__(order);
      return;
    }
    // if trade failed unexpectedly (`makerExecute` reverted or Mangrove failed to transfer the outbound tokens to the Offer Taker)
    __posthookFallback__(order, result);
    return;
  }

  ////// Customizable hooks for Taker Order'execution

  // Override this hook to describe where the inbound token, which are flashswapped by the Offer Taker, should go during Taker Order's execution.
  // `amount` is the quantity of outbound tokens whose destination is to be resolved.
  // All tokens that are not transfered to a different contract remain listed in the balance of `this` contract
  function __put__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (uint);

  // Override this hook to implement fetching `amount` of outbound tokens, possibly from another source than `this` contract during Taker Order's execution.
  // For composability, return value MUST be the remaining quantity (i.e <= `amount`) of tokens remaining to be fetched.
  function __get__(uint amount, MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (uint);

  // Override this hook to implement a last look check during Taker Order's execution.
  // Return value should be `true` if Taker Order is acceptable.
  function __lastLook__(MgvLib.SingleOrder calldata order)
    internal
    virtual
    returns (bool proceed)
  {
    order; //shh
    proceed = true;
  }

  ////// Customizable post-hooks.

  // Override this post-hook to implement what `this` contract should do when called back after a successfully executed order.
  function __posthookSuccess__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; // shh
  }

  // Override this post-hook to implement what `this` contract should do when called back after an order that failed to be executed because of a lack of liquidity (not enough outbound tokens).
  function __posthookGetFailure__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order;
  }

  // Override this post-hook to implement what `this` contract should do when called back after an order that did not pass its last look (see `__lastLook__` hook).
  function __posthookReneged__(MgvLib.SingleOrder calldata order)
    internal
    virtual
  {
    order; //shh
  }

  // Override this post-hook to implement fallback behavior when Taker Order's execution failed unexpectedly. Information from Mangrove is accessible in `result.mgvData` for logging purpose.
  function __posthookFallback__(
    MgvLib.SingleOrder calldata order,
    MgvLib.OrderResult calldata result
  ) internal virtual {
    order;
    result;
  }
}
