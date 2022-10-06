// SPDX-License-Identifier:	BSD-2-Clause

// IOfferLogic.sol

// Copyright (c) 2021 Giry SAS. All rights reserved.

// Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

// 1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
// 2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

pragma solidity >=0.8.0;

pragma abicoder v2;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20, IMaker} from "mgv_src/MgvLib.sol";
import {AbstractRouter} from "mgv_src/strategies/routers/AbstractRouter.sol";

///@title IOfferLogic interface for offer management
///@notice It is an IMaker for Mangrove

interface IOfferLogic is IMaker {
  ///@notice Log incident (during post trade execution)
  event LogIncident(
    IMangrove mangrove,
    IERC20 indexed outbound_tkn,
    IERC20 indexed inbound_tkn,
    uint indexed offerId,
    bytes32 makerData,
    bytes32 mgvData
  );

  ///@notice Logging change of router address
  event SetRouter(AbstractRouter);

  ///@notice Logging change in default gasreq
  event SetGasreq(uint);

  ///@notice Actual gas requirement when posting offers via `this` strategy. Returned value may change if `this` contract's router is updated.
  ///@return total gas cost including router specific costs (if any).
  function offerGasreq() external view returns (uint total);

  ///@notice returns offer gas requirements.
  ///@param constantPartOnly whether one wishes to know the gas requirement w/o the router cost
  function detailedOfferGasreq(bool constantPartOnly) external view returns (uint);

  ///@notice Computes missing provision to repost `offerId` at given `gasreq` and `gasprice` ignoring current contract's balance on Mangrove.
  ///@return missingProvision to repost `offerId`.
  function getMissingProvision(IERC20 outbound_tkn, IERC20 inbound_tkn, uint gasreq, uint gasprice, uint offerId)
    external
    view
    returns (uint missingProvision);

  ///@notice sets `this` contract's default gasreq for `new/updateOffer`.
  ///@param gasreq an overapproximation of the gas required to handle trade and posthook without considering liquidity routing specific costs.
  ///@dev this should only take into account the gas cost of managing offer posting/updating during trade execution. Router specific gas cost are taken into account in the getter `offerGasreq()`
  function setGasreq(uint gasreq) external;

  ///@notice sets a new router to pull outbound tokens from contract's reserve to `this` and push inbound tokens to reserve.
  ///@param router_ the new router contract that this contract should use. Use `NO_ROUTER` for no router.
  ///@dev new router needs to be approved by `this` contract to push funds to reserve (see `activate` function). It also needs to be approved by reserve to pull from it.
  function setRouter(AbstractRouter router_) external;

  ///@notice Approves a spender to transfer a certain amount of tokens on behalf of `this` contract.
  ///@param token the ERC20 token contract
  ///@param spender the approved spender
  ///@param amount the spending amount
  ///@dev admin may use this function to revoke approvals of `this` contract that are set after a call to `activate`.
  function approve(IERC20 token, address spender, uint amount) external returns (bool);

  ///@notice Withdraws tokens from offer maker's reserve
  ///@param token the type of asset one is willing to retrieve
  ///@param receiver the address of the receiver of the tokens (must not be `address(0)`)
  ///@param amount the quantity of tokens to withdraw from reserve (in WEI units).
  ///@return success whether funds were successfully transferred to `receiver`
  ///@dev notice anyone can call but only `msg.sender` can withdraw from its reserve
  function withdrawToken(IERC20 token, address receiver, uint amount) external returns (bool success);

  ///@notice computes the amount of native tokens that can be redeemed when deprovisioning a certain offer.
  ///@param outbound_tkn the outbound token of the offer list
  ///@param inbound_tkn the inbound token of the offer list
  ///@param offerId the identifier of the offer in the offer list
  ///@return provision the amount of native tokens that can be redeemed when deprovisioning the offer
  function provisionOf(IERC20 outbound_tkn, IERC20 inbound_tkn, uint offerId) external view returns (uint provision);

  ///@notice verifies that this contract's current state is ready to be used by msg.sender to post offers on Mangrove
  ///@dev throws with a reason when there is a missing approval
  function checkList(IERC20[] calldata tokens) external view;

  ///@notice View of offer maker's reserve balance for a particular asset.
  ///@param token the asset type one wishes to know the reserve balance of
  ///@return balance the `token` amount in offer maker's reserve
  function tokenBalance(IERC20 token) external view returns (uint balance);

  /// @notice allows `this` contract to be a liquidity provider for a particular asset by performing the necessary approvals
  /// @param tokens the ERC20 `this` contract will approve to be able to trade on Mangrove's corresponding markets.
  function activate(IERC20[] calldata tokens) external;

  ///@notice withdraws ETH from the `this` contract's balance on Mangrove.
  ///@param amount the amount of WEI one wishes to withdraw.
  ///@param receiver the address of the receiver of the funds.
  ///@dev Since a call is made to the `receiver`, this function is subject to reentrancy.
  function withdrawFromMangrove(uint amount, address payable receiver) external;

  ///@notice updates an offer existing on Mangrove (not necessarily live).
  ///@param outbound_tkn the outbound token of the offer list of the offer
  ///@param inbound_tkn the outbound token of the offer list of the offer
  ///@param wants the new amount of outbound tokens the offer maker requires for a complete fill
  ///@param gives the new amount of inbound tokens the offer maker gives for a complete fill
  ///@param gasreq the new amount of gas units that are required to execute the trade (use type(uint).max for using `this.offerGasReq()`)
  ///@param gasprice the new gasprice used to compute offer's provision (use 0 to use Mangrove's gasprice)
  ///@param pivotId the pivot to use for re-inserting the offer in the list (use `offerId` if updated offer is live)
  ///@param offerId the id of the offer in the offer list.
  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) external payable;

  ///@notice Retracts an offer from an Offer List of Mangrove.
  ///@param outbound_tkn the outbound token of the offer list.
  ///@param inbound_tkn the inbound token of the offer list.
  ///@param offerId the identifier of the offer in the (`outbound_tkn`,`inbound_tkn`) offer list
  ///@param deprovision positioned if `msg.sender` wishes to redeem the offer's provision.
  ///@return received the amount of native tokens (in WEI) that have been retrieved by retracting the offer.
  ///@dev Function's authorized caller is offer owner or Mangrove in order to let `makerExecute/Posthook` retract an offer.
  /// An offer that is retracted without `deprovision` is off the offer list but still has its provisions locked.
  /// Calling this function, with the `deprovision` flag, on an offer that is already off the offer list can be used to retrieve the locked provisions.
  function retractOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint offerId,
    bool deprovision // if set to `true`, `this` contract will receive the remaining provision (in WEI) associated to `offerId`.
  ) external returns (uint received);

  ///@notice view of offer maker's reserve
  ///@dev if offer maker is `this` (`Direct` logics) then it returns the liquidity reserve of `address(this)`
  /// otherwise (`Forwarder` logics) it returns the reserve of `msg.sender`.
  function reserve() external view returns (address);

  /**
   * @notice sets the address of the reserve of an offer maker.
   * @dev If offer maker is `this` (`Direct` logics) it sets the reserve for `address(this)`.
   * @dev Otherwise (`Forwarder` logics) it sets the reserve for `msg.sender`.
   * @param reserve the address of offer maker's reserve
   */
  function setReserve(address reserve) external;

  /// @notice Contract's router getter.
  /// @dev if contract has a no router, function returns `NO_ROUTER`.
  function router() external view returns (AbstractRouter);
}
